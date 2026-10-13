"""Bounded retrieval before AI. Only configured, reviewed sources are requested.

No unit is inferred from crop type. OGD rows without an explicit trading unit
remain unavailable; a deployment-wide fallback cannot cover local unit choices.
"""
import asyncio
import hashlib
import ipaddress
import json
import socket
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from typing import Literal, get_args
from urllib.parse import urlsplit

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationInfo, model_validator, field_validator
from app.core.config import settings
from app.integrations.pypricing_market import canonical_commodity, normalized, valid_public_url

IST = timezone(timedelta(hours=5, minutes=30))
OGD_URL = "https://api.data.gov.in/resource/9ef84268-d588-465a-a308-a864a43d0070"
Unit = Literal["kg", "kilogram", "quintal", "qtl", "tonne", "ton", "piece", "count", "dozen", "bunch", "bundle"]


class SourceQuote(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, hide_input_in_errors=True)
    commodity: str = Field(min_length=2, max_length=200)
    market: str = Field(min_length=2, max_length=200)
    district: str = Field(min_length=2, max_length=100)
    state: str = Field(min_length=2, max_length=100)
    unit: str = Field(min_length=1, max_length=20)
    currency: Literal["INR"]
    price_paise: int = Field(gt=0, le=10**12)
    min_price_paise: int | None = Field(default=None, ge=0, le=10**12)
    max_price_paise: int | None = Field(default=None, ge=0, le=10**12)
    modal_price_paise: int | None = Field(default=None, gt=0, le=10**12)
    observation_date: date
    source: str = Field(min_length=2, max_length=200)
    source_url: str
    source_record_id: str | None = Field(default=None, min_length=1, max_length=200)
    original_price_value: str | None = Field(default=None, max_length=32)
    original_min_value: str | None = Field(default=None, max_length=32)
    original_max_value: str | None = Field(default=None, max_length=32)
    original_unit: str | None = Field(default=None, max_length=20)
    variety: str | None = None
    grade: str | None = None
    market_type: str | None = None
    calculation_method: str | None = None
    unit_evidence_url: str | None = None

    @field_validator("unit")
    @classmethod
    def supported_unit(cls, value):
        if value.lower() not in get_args(Unit):
            raise ValueError("Unsupported trading unit")
        return value # Preserve the original source spelling.

    @model_validator(mode="after")
    def evidence_valid(self, info: ValidationInfo):
        if not valid_public_url(self.source_url) or urlsplit(self.source_url).query or urlsplit(self.source_url).fragment:
            raise ValueError("Invalid evidence URL")
        today = datetime.now(IST).date()
        age = (today - self.observation_date).days
        if age < 0 or (not (info.context or {}).get("history") and age > settings.MARKET_CURRENT_MAX_DAYS):
            raise ValueError("Observation is not current")
        low, high = self.min_price_paise, self.max_price_paise
        if self.market_type == "uzhavar_santhai":
            from app.integrations.tn_market import BASE, CROPS, METHOD, SOURCE
            expected_urls = {BASE + self.observation_date.strftime("%d-%m-%Y") + "/" + str(crop)
                             for crop, (name, _) in CROPS.items() if name == self.commodity}
            if (self.source_url not in expected_urls or self.source != SOURCE or self.unit != "kg"
                    or self.currency != "INR" or self.state != "Tamil Nadu"
                    or self.calculation_method != METHOD or low is None or high is None
                    or self.original_min_value is None or self.original_max_value is None
                    or self.original_unit != "kg"
                    or self.modal_price_paise is not None
                    or self.unit_evidence_url != "https://www.agrimark.tn.gov.in/"):
                raise ValueError("Invalid Uzhavar Santhai provenance")
            from decimal import ROUND_HALF_UP
            midpoint = int((Decimal(low + high) / 2).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
            if self.price_paise != midpoint:
                raise ValueError("Invalid source range midpoint")
        if low is not None and high is not None and low > high:
            raise ValueError("Invalid price range")
        for amount in (self.price_paise, self.modal_price_paise):
            if amount is not None and ((low is not None and amount < low) or (high is not None and amount > high)):
                raise ValueError("Price outside source range")
        originals = ((self.original_price_value, self.price_paise),
                     (self.original_min_value, self.min_price_paise),
                     (self.original_max_value, self.max_price_paise))
        if any(value is not None for value, _ in originals):
            if self.original_unit != self.unit:
                raise ValueError("Original trading unit differs from quoted unit")
            for value, normalized_price in originals:
                if value is not None and paise(value) != normalized_price:
                    raise ValueError("Original source value differs from normalized price")
        return self

    def matches(self, query):
        names = [query.get("commodity"), *query.get("aliases", [])]
        return ((not any(names) or any(canonical_commodity(self.commodity) == canonical_commodity(n) for n in names if n))
                and all(not query.get(k) or normalized(getattr(self, k)) == normalized(query[k])
                        for k in ("market", "state", "district", "variety")))

    @property
    def evidence_id(self):
        # Preserve hashes of existing cache evidence created before the additive
        # Uzhavar Santhai provenance fields were introduced.
        exclude = {"market_type", "calculation_method", "unit_evidence_url"} if all(
            getattr(self, field) is None for field in ("market_type", "calculation_method", "unit_evidence_url")) else set()
        return hashlib.sha256(self.model_dump_json(exclude=exclude).encode()).hexdigest()


def paise(value):
    if isinstance(value, bool):
        raise ValueError("Invalid amount")
    try:
        amount = Decimal(str(value)) * 100
        if not amount.is_finite() or amount != amount.to_integral_value():
            raise ValueError("Invalid amount precision")
        return int(amount)
    except (InvalidOperation, ValueError, TypeError, OverflowError):
        raise ValueError("Invalid amount") from None


async def public_source(url):
    if not valid_public_url(url):
        return False
    parts = urlsplit(url)
    if parts.port not in (None, 443) or parts.query or parts.fragment:
        return False
    addresses = await asyncio.to_thread(socket.getaddrinfo, parts.hostname, 443, type=socket.SOCK_STREAM)
    return bool(addresses) and all(ipaddress.ip_address(a[4][0]).is_global for a in addresses)


async def read_json(client, url, params=None):
    # Streaming bounds decompressed data. No redirects or automatic retries.
    async with client.stream("GET", url, params=params) as response:
        response.raise_for_status()
        data = bytearray()
        async for chunk in response.aiter_bytes():
            data.extend(chunk)
            if len(data) > 2_000_000:
                raise ValueError("Source response exceeds limit")
        return json.loads(data)


class MarketEvidenceRetriever:
    async def retrieve(self, queries, primary_only=False):
        quotes, diagnostics = {}, []
        located = [q for q in queries if q.get("state") and
                   (q.get("market") or q.get("scope") == "statewide")]
        if not located:
            return [], ["NO_CONFIRMED_MARKET_LOCATION"]
        async with asyncio.timeout(120):
            async with httpx.AsyncClient(timeout=15, follow_redirects=False,
                    transport=httpx.AsyncHTTPTransport(retries=0)) as client:
                if settings.GOVERNMENT_MARKET_API_KEY:
                    # Paginate by state, never make AI requests per crop.
                    states = sorted({q["state"] for q in located})
                    for state in states:
                        try:
                            offset = 0
                            expected_total = None
                            while offset < settings.MARKET_SOURCE_MAX_ROWS:
                                data = await read_json(client, OGD_URL, {"api-key": settings.GOVERNMENT_MARKET_API_KEY,
                                    "format": "json", "filters[state]": state, "limit": 100, "offset": offset})
                                rows = data.get("records")
                                if not isinstance(rows, list) or str(data.get("status", "")).lower() not in ("ok", "success"):
                                    raise ValueError("Invalid official source structure")
                                total = int(data["total"])
                                if isinstance(data["total"], bool) or total < 0 or not rows and offset < total or len(rows) > 100:
                                    raise ValueError("Invalid official pagination")
                                if expected_total is not None and expected_total != total:
                                    raise ValueError("Official result count changed during retrieval")
                                expected_total = total
                                for row in rows:
                                    try:
                                        if row.get("currency") not in (None, "INR"):
                                            raise ValueError("Unsupported source currency")
                                        # AGMARKNET can report different units by commodity and
                                        # market. A deployment-wide fallback would mislabel prices.
                                        if not row.get("unit"):
                                            if "OGD_ROW_UNIT_MISSING" not in diagnostics:
                                                diagnostics.append("OGD_ROW_UNIT_MISSING")
                                            continue
                                        observed = datetime.strptime(row["arrival_date"], "%d/%m/%Y").date()
                                        quote = SourceQuote(commodity=row["commodity"].strip(), market=row["market"].strip(),
                                            district=row["district"].strip(), state=row["state"].strip(),
                                            unit=row["unit"], currency="INR",
                                            price_paise=paise(row["modal_price"]), modal_price_paise=paise(row["modal_price"]),
                                            min_price_paise=paise(row["min_price"]) if row.get("min_price") is not None else None,
                                            max_price_paise=paise(row["max_price"]) if row.get("max_price") is not None else None,
                                            observation_date=observed, source="data.gov.in AGMARKNET", source_url=OGD_URL,
                                            source_record_id=str(row["id"]) if row.get("id") is not None else None,
                                            original_price_value=str(row["modal_price"]),
                                            original_min_value=str(row["min_price"]) if row.get("min_price") is not None else None,
                                            original_max_value=str(row["max_price"]) if row.get("max_price") is not None else None,
                                            original_unit=row["unit"],
                                            variety=row.get("variety"), grade=row.get("grade"))
                                        if any(quote.matches(q) for q in located):
                                            quotes[quote.evidence_id] = quote
                                    except (ValueError, KeyError, TypeError, AttributeError):
                                        if "OGD_ROW_REJECTED" not in diagnostics:
                                            diagnostics.append("OGD_ROW_REJECTED")
                                        continue
                                offset += len(rows)
                                if not rows or offset >= total:
                                    break
                            else:
                                diagnostics.append("SOURCE_ROW_LIMIT")
                        except httpx.HTTPStatusError as exc:
                            diagnostics.extend(["OGD_SOURCE_UNAVAILABLE", "OGD_HTTP_" + str(exc.response.status_code)])
                        except (httpx.HTTPError, ValueError, KeyError, TypeError, AttributeError):
                            diagnostics.append("OGD_SOURCE_UNAVAILABLE")
                else:
                    diagnostics.append("OGD_KEY_MISSING")
                urls = [] if primary_only else json.loads(settings.MARKET_SOURCE_URLS)
                if not isinstance(urls, list) or len(urls) > 10 or not all(isinstance(u, str) for u in urls):
                    raise ValueError("Invalid reviewed source configuration")
                for url in urls:
                    try:
                        if not await public_source(url):
                            raise ValueError("Source is not public HTTPS")
                        data = await read_json(client, url)
                        rows = data.get("records")
                        if not isinstance(rows, list) or len(rows) > settings.MARKET_SOURCE_MAX_ROWS:
                            raise ValueError("Invalid reviewed source structure")
                        if not rows:
                            diagnostics.append("REVIEWED_SOURCE_EMPTY")
                        for row in rows:
                            try:
                                quote = SourceQuote.model_validate_json(json.dumps(row))
                                # Operator review of this endpoint is the trust boundary.
                                if quote.source_url != url:
                                    continue
                                if any(quote.matches(q) for q in located):
                                    quotes[quote.evidence_id] = quote
                            except (ValueError, TypeError):
                                if "REVIEWED_ROW_REJECTED" not in diagnostics:
                                    diagnostics.append("REVIEWED_ROW_REJECTED")
                                continue
                    except (httpx.HTTPError, ValueError, OSError, TypeError, AttributeError):
                        diagnostics.append("REVIEWED_SOURCE_UNAVAILABLE")
        return list(quotes.values()), diagnostics
