"""Documented pyPricingAPI formatted-output adapter; no AI dependency.

Live contract/data verification failed (DNS). Activation therefore defaults off.
Only the README's output=String format is parsed; unknown JSON shapes fail closed.
"""
import asyncio
import hashlib
import ipaddress
import logging
import re
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from urllib.parse import urlsplit

import httpx
from app.core.config import settings

logger = logging.getLogger(__name__)
ENDPOINT = "https://k14y5popkj.execute-api.ap-south-1.amazonaws.com/stage/commodities"
SOURCE = "pyPricingAPI (Chitta)"
IST = timezone(timedelta(hours=5, minutes=30))
# Membership only, from the repository's uppercase APMCs. Coordinates in that
# file are not independently verified and are never used to infer distance.
DOCUMENTED_MARKETS = frozenset("VIRUDHUNAGAR VIKIRAVANDI VELLAKOIL USILAMPATTI THENI THIRUPPUR SIRKALI SATHYAMANGALAM PERUNDURAI PALANI ODDANCHATRAM NATHAM VIRUDHACHALAM HARUR GUDIYATHAM GOBICHETTIPALAYAM ERODE DESUR ANTHIYUR ANNUR ANAIMALAI CHETPET CHEYYAR KALLAKURUCHI PANRUTI VELLORE VETTAVALAM CUMBUM RAMANATHAPURAM DINDIGUL KALAVAI MADURANATHANGAM VANIYAMBADI ARANI GINGEE ULUNDURPETTAI VIKKIRAVANDI AMMOOR KANCHEEPURAM KALLAKURICHI MADURAI POLUR SANKARAPURAM USILAMPATTY VILLUPURAM VANDAVASI VELLANKOIL".split())
ALIASES = {"ground nut": "groundnut", "urad (black gram)": "black gram"}


def normalized(value):
    return " ".join(str(value or "").split()).casefold()


def canonical_commodity(value):
    name = normalized(value)
    return ALIASES.get(name, name)


def commodity_names(value):
    canonical = canonical_commodity(value)
    return sorted({canonical, *(alias for alias, target in ALIASES.items() if target == canonical)})


def valid_public_url(value):
    if not isinstance(value, str):
        return False
    try:
        url = urlsplit(value)
        if url.scheme != "https" or not url.hostname or url.username or url.password:
            return False
        host = url.hostname.lower()
        if host in {"localhost", "localhost.localdomain"} or "." not in host:
            return False
        try:
            return ipaddress.ip_address(host).is_global
        except ValueError:
            return not host.endswith((".local", ".internal", ".localhost"))
    except ValueError:
        return False


def matches(record, commodity=None, market=None, state=None, district=None):
    """Validate cached evidence without network or AI, retaining old good cache."""
    if not isinstance(record, dict) or record.get("verification_status") != "verified":
        return False
    method = record.get("verification_method")
    if method not in {"grounding_and_source_excerpt", "provider_reported_quote"}:
        return False
    if not valid_public_url(record.get("source_url")) or not record.get("evidence"):
        return False
    if record.get("currency") != "INR" or not record.get("unit"):
        return False
    price = record.get("price_paise")
    if type(price) is not int or price < 0 or price > 10**12:
        return False
    if method == "grounding_and_source_excerpt":
        if price == 0 or record.get("source") != urlsplit(record["source_url"]).hostname:
            return False
    else:
        if (record["source_url"] != ENDPOINT or record.get("source") != SOURCE
                or record.get("unit") != "Qui" or record.get("state") != "Tamil Nadu"
                or record.get("market", "").upper() not in DOCUMENTED_MARKETS):
            return False
    for field, expected in (("commodity", commodity), ("market", market), ("state", state), ("district", district)):
        if not expected:
            continue
        actual = record.get(field)
        if field == "commodity":
            equal = canonical_commodity(actual) == canonical_commodity(expected)
        elif field == "market" and method == "grounding_and_source_excerpt":
            equal = normalized(actual) == normalized(expected) or normalized(actual).startswith(normalized(expected) + " ")
        else:
            equal = normalized(actual) == normalized(expected)
        if not equal:
            return False
    try:
        observed = date.fromisoformat(str(record["arrival_date"]))
        retrieved = record["retrieved_at"]
        if isinstance(retrieved, str):
            retrieved = datetime.fromisoformat(retrieved.replace("Z", "+00:00"))
        if retrieved.tzinfo is None:
            retrieved = retrieved.replace(tzinfo=timezone.utc)
        return observed <= datetime.now(IST).date() and retrieved <= datetime.now(timezone.utc)
    except (ValueError, KeyError, TypeError, AttributeError):
        return False


def parse_documented_output(payload, queries, retrieved_at=None):
    """Parse only the published String example, never invent modal/variety data.

    Only exact requested markets are retained. Radius-based substitution needs
    verified coordinates/distances and is not enabled by this adapter.
    RS is INR in the documented Indian context. 'Qui' stays the original unit:
    no conversion to KG until the provider confirms what this abbreviation means.
    """
    if isinstance(payload, dict) and isinstance(payload.get("data"), dict):
        payload = payload["data"].get("value")
    if not isinstance(payload, str) or not payload.startswith("Latest reported prices:"):
        raise ValueError("Unsupported pyPricingAPI response schema")
    if len(payload) > 1_000_000 or len(payload.splitlines()) > 5001:
        raise ValueError("Oversized pyPricingAPI response")
    stamp = retrieved_at or datetime.now(timezone.utc)
    today = stamp.astimezone(IST).date()
    records = {}
    targets = {}
    for query in queries:
        requested_market = query.get("market") or query.get("district")
        if (not requested_market or query.get("district") or query.get("variety")
                or query.get("state") and normalized(query["state"]) != "tamil nadu"):
            continue
        targets.setdefault((canonical_commodity(query.get("commodity")), normalized(requested_market)), []).append(query)
    pattern = re.compile(r"^-\s+([^:\r\n]{1,200}?)\s*:\s*(\d+(?:\.\d{1,2})?) RS/Qui,\s*([^,\r\n]{1,200}?),\s*(\d{4}-\d{2}-\d{2})\s*$")
    for line in payload.splitlines()[1:5001]:
        line = line.strip()
        if not line:
            continue
        match = pattern.fullmatch(line)
        if not match:
            # Reject the entire malformed feed rather than hide corrupt rows.
            raise ValueError("Malformed pyPricingAPI price quote")
        crop, amount, market, observed_text = match.groups()
        crop, market = crop.strip(), market.strip()
        try:
            price = Decimal(amount)
            observed = date.fromisoformat(observed_text)
        except (InvalidOperation, ValueError):
            raise ValueError("Invalid pyPricingAPI price/date") from None
        if not price.is_finite() or price < 0 or price > Decimal("10000000000") or observed > today:
            raise ValueError("Invalid pyPricingAPI price/date")
        if market.upper() not in DOCUMENTED_MARKETS:
            continue
        for query in targets.get((canonical_commodity(crop), normalized(market)), []):
            paise = int(price * 100)
            record = dict(commodity=crop, commodity_id="pypricing:" + hashlib.sha256(canonical_commodity(crop).encode()).hexdigest(),
                crop_name=query["commodity"], category=query.get("category"), variety=None,
                market=market, state="Tamil Nadu", district=None, price_paise=paise,
                price_display=f"₹{price:,.2f}", currency="INR", unit="Qui", price_type="unknown",
                quote_type="unknown", observation_date=observed_text, arrival_date=observed_text,
                retrieved_at=stamp, source=SOURCE, source_organization="Chitta",
                source_title="Latest reported prices", source_url=ENDPOINT, evidence=line,
                verification_status="verified", verification_method="provider_reported_quote",
                freshness_status="fresh" if (today - observed).days <= settings.MARKET_CURRENT_MAX_DAYS else "stale",
                stale=(today - observed).days > settings.MARKET_CURRENT_MAX_DAYS)
            records.setdefault((canonical_commodity(crop), normalized(market), observed_text), record)
    return list(records.values())


class PyPricingMarketProvider:
    matches = staticmethod(matches)

    async def search_prices(self, **kwargs):
        return {"records": [], "live": False, "message": "Read the daily market cache."}

    async def discover_daily(self, queries):
        if not settings.PYPRICING_ENABLED:
            return self._unavailable("PROVIDER_NOT_VERIFIED", "pyPricingAPI refresh disabled: live endpoint/data verification is pending; cached prices preserved.")
        # One shared request, not a request for each crop. Location count and
        # body size are bounded; no truncation silently loses registered crops.
        places = sorted({" ".join((q.get("market") or q.get("district") or "").split())
            for q in queries if not q.get("state") or normalized(q["state"]) == "tamil nadu"})
        places = [p for p in places if p]
        if not places or len(places) > 20 or any(len(p) > 100 or "," in p for p in places):
            return self._unavailable("INVALID_LOCATIONS", "Market locations missing or batch exceeds the safe limit; cache preserved.")
        params = dict(place=",".join(places), radius=settings.PYPRICING_RADIUS_KM, type="current", output="String", language="ENGLISH")
        try:
            async with asyncio.timeout(30):
                async with httpx.AsyncClient(timeout=httpx.Timeout(15, connect=5), follow_redirects=False,
                        transport=httpx.AsyncHTTPTransport(retries=0)) as client:
                    async with client.stream("GET", ENDPOINT, params=params) as response:
                        response.raise_for_status()
                        content = bytearray()
                        async for chunk in response.aiter_bytes():
                            content.extend(chunk)
                            if len(content) > 1_000_000:
                                raise ValueError("Oversized provider response")
                        import json
                        payload = json.loads(content)
                records = parse_documented_output(payload, queries)
            return {"records": records, "count": len(records), "live": bool(records), "source": SOURCE,
                    "message": "Source-reported prices; check original units, market and observation date. No modal price is implied." if records else "No matching source-reported market price; cached prices preserved."}
        except httpx.HTTPStatusError as exc:
            logger.warning("pypricing_failed category=http status=%s", exc.response.status_code)
            return self._unavailable(exc.response.status_code, "Market provider HTTP error; cache preserved. No retry.")
        except (httpx.HTTPError, TimeoutError, ValueError) as exc:
            logger.warning("pypricing_failed category=%s", type(exc).__name__)
            return self._unavailable(type(exc).__name__, "Market provider unavailable or response invalid; cache preserved. No retry.")

    @staticmethod
    def _unavailable(code, message):
        return {"records": [], "count": 0, "live": False, "source": SOURCE, "error_code": code, "message": message}


market_price_provider = PyPricingMarketProvider()
