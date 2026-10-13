"""Official Uzhavar Santhai feed. No credentials, retries or generated prices."""
import asyncio
import json
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP

import httpx

from app.core.config import settings
from app.integrations.market_evidence import IST, SourceQuote, paise
from app.integrations.pypricing_market import normalized

BASE = "https://www.agrimark.tn.gov.in/home/us_dist_report_api/"
SOURCE = "Tamil Nadu Agricultural Marketing Department — Uzhavar Santhai"
METHOD = "median_distinct_market_range_midpoint"
# IDs and bilingual names checked against the official crop selector.
CROPS = {
    8: ("Tomato", ("tomato", "தக்காளி")),
    27: ("Banana (fruit)", ("banana fruit", "banana (fruit)", "வாழைப்பழம்")),
    109: ("Jasmine", ("jasmine", "மல்லிகை")),
    107: ("Marigold", ("marigold",)),
}


def crop_mapping(query):
    # A supplied alias cannot override an explicitly different supported crop.
    names = [query.get("commodity"), *query.get("aliases", [])]
    ids = {key for key, (_, aliases) in CROPS.items()
           if any(normalized(name) in aliases for name in names if name)}
    return next(iter(ids)) if len(ids) == 1 else None


def parse_records(data, crop, observed):
    if crop not in CROPS:
        raise ValueError("Unsupported source crop ID")
    if not isinstance(data, dict):
        raise ValueError("Unexpected source response type")
    quotes, rejected = [], 0
    url = BASE + observed.strftime("%d-%m-%Y") + "/" + str(crop)
    for market, row in data.items():
        try:
            if not isinstance(market, str) or len(market.strip()) < 2 or not isinstance(row, dict):
                raise ValueError("Malformed market record")
            # Date/crop are bound by the official request; reject contradictory metadata.
            if row.get("date", observed.strftime("%d-%m-%Y")) != observed.strftime("%d-%m-%Y"):
                raise ValueError("Wrong observation date")
            if str(row.get("crop_id", crop)) != str(crop):
                raise ValueError("Wrong crop ID")
            if row.get("observation_date", observed.isoformat()) != observed.isoformat():
                raise ValueError("Wrong observation date")
            if row.get("currency", "INR") != "INR":
                raise ValueError("Unexpected currency")
            if row.get("unit", "kg") not in ("kg", "kilogram"):
                raise ValueError("Unexpected price unit")
            low, high = paise(row["min"]), paise(row["max"])
            if not 0 <= low <= high <= 10**12:
                raise ValueError("Invalid price range")
            midpoint = int((Decimal(low + high) / 2).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
            quote = SourceQuote(
                commodity=CROPS[crop][0], market=market.strip(), district="Not provided",
                state="Tamil Nadu", unit="kg", currency="INR", price_paise=midpoint,
                min_price_paise=low, max_price_paise=high, observation_date=observed,
                source=SOURCE, source_url=url, source_record_id=str(crop) + ":" + market.strip(),
                original_min_value=str(row["min"]), original_max_value=str(row["max"]),
                original_unit="kg", market_type="uzhavar_santhai", calculation_method=METHOD,
                unit_evidence_url="https://www.agrimark.tn.gov.in/",
            )
            quotes.append(quote)
        except (ValueError, TypeError, KeyError):
            rejected += 1
    return quotes, rejected


class TamilNaduMarketRetriever:
    def __init__(self, transport=None):
        self.transport = transport

    async def retrieve(self, queries, primary_only=True):
        ids = sorted({crop_mapping(q) for q in queries} - {None})
        diagnostics, quotes = [], []
        if any(crop_mapping(q) is None for q in queries):
            diagnostics.append("TN_UNSUPPORTED_CROP")
        observed = datetime.now(IST).date()
        async with asyncio.timeout(120):
            # trust_env=False prevents forwarding proxy credentials/configuration.
            async with httpx.AsyncClient(timeout=httpx.Timeout(25, connect=10),
                    follow_redirects=False, trust_env=False,
                    transport=self.transport or httpx.AsyncHTTPTransport(retries=0)) as client:
                for crop in ids:
                    url = BASE + observed.strftime("%d-%m-%Y") + "/" + str(crop)
                    try:
                        async with client.stream("POST", url, content=b"") as response:
                            response.raise_for_status()
                            content = bytearray()
                            async for chunk in response.aiter_bytes():
                                content.extend(chunk)
                                if len(content) > 2_000_000:
                                    raise ValueError("Response limit exceeded")
                        data = json.loads(content)
                        if len(data) > settings.MARKET_SOURCE_MAX_ROWS:
                            raise ValueError("Row limit exceeded")
                        batch, rejected = parse_records(data, crop, observed)
                        quotes.extend(batch)
                        if rejected:
                            diagnostics.append(f"TN_ROWS_REJECTED_{crop}_{rejected}")
                        if not batch:
                            diagnostics.append(f"TN_EMPTY_{crop}")
                    except httpx.HTTPStatusError as exc:
                        diagnostics.append(f"TN_HTTP_{crop}_{exc.response.status_code}")
                    except (httpx.HTTPError, ValueError, TypeError):
                        diagnostics.append(f"TN_SOURCE_UNAVAILABLE_{crop}")
        return quotes, diagnostics
