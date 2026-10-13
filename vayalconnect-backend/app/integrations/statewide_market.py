"""Deterministic Tamil Nadu medians over primary-source observations.

No inference or HTTP is performed by cache validation. Raw observations live in
the existing market_prices collection alongside additive statewide records.
"""
import json
import httpx
from collections import defaultdict
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from statistics import median

from app.core.config import settings
from app.integrations.groq_market import crop_id, matches as observation_matches
from app.integrations.market_evidence import IST, OGD_URL, MarketEvidenceRetriever, SourceQuote
from app.integrations.pypricing_market import normalized, canonical_commodity
from app.integrations.tn_market import TamilNaduMarketRetriever, METHOD as TN_METHOD, CROPS, crop_mapping

LABEL = "Tamil Nadu statewide reference price — calculated from available market observations"
METHOD = "median_distinct_market_modal"
UNIT_ALIASES = {"kilogram": "kg", "qtl": "quintal", "ton": "tonne", "count": "piece"}


def statewide_query(query):
    aliases = list(query.get("aliases", []))
    mapping = crop_mapping(query)
    if mapping is not None:
        aliases = list(dict.fromkeys([*aliases, CROPS[mapping][0], *CROPS[mapping][1]]))
    return {"commodity": query.get("commodity"), "category": query.get("category"),
            "variety": query.get("variety"), "aliases": aliases,
            "state": "Tamil Nadu", "market": None, "district": None, "scope": "statewide"}


def aggregate(quotes, queries, stamp, minimum=None, history=False):
    minimum = minimum or settings.MARKET_STATEWIDE_MIN_OBSERVATIONS
    if type(minimum) is not int or minimum < 3:
        raise ValueError("At least three distinct markets are required")
    valid = []
    for raw in quotes:
        try:
            q = SourceQuote.model_validate_json(raw.model_dump_json(), context={"history": history})
            if normalized(q.state) == "tamil nadu" and (
                    q.source_url == OGD_URL and q.modal_price_paise is not None
                    or q.market_type == "uzhavar_santhai"):
                valid.append(q)
        except (ValueError, TypeError, AttributeError):
            continue
    records = []
    seen = set()
    for target in queries:
        query = statewide_query(target)
        identity = (crop_id(query), normalized(query.get("variety")))
        if identity in seen:
            continue
        seen.add(identity)
        groups = defaultdict(dict)
        conflicts = set()
        for q in valid:
            if not q.matches(query):
                continue
            unit = UNIT_ALIASES.get(q.unit.lower(), q.unit.lower())
            key = (normalized(q.commodity), normalized(q.variety), normalized(q.grade), unit,
                   q.currency, q.source_url, q.observation_date, q.market_type, q.calculation_method)
            market = (normalized(q.market), normalized(q.district))
            old = groups[key].get(market)
            if old is not None and (old.price_paise, old.min_price_paise, old.max_price_paise) != (q.price_paise, q.min_price_paise, q.max_price_paise):
                conflicts.add((key, market))
            # Exact duplicates and alternative IDs cannot multiply a market's weight.
            if old is None or q.evidence_id < old.evidence_id:
                groups[key][market] = q
        for key, markets in groups.items():
            selected = [q for market, q in markets.items() if (key, market) not in conflicts]
            if len(selected) < minimum:
                continue
            selected.sort(key=lambda q: q.evidence_id)
            amount = int(Decimal(median([q.price_paise if q.market_type == "uzhavar_santhai" else q.modal_price_paise for q in selected])).quantize(
                Decimal("1"), rounding=ROUND_HALF_UP))
            exemplar = selected[0]
            tn = exemplar.market_type == "uzhavar_santhai"
            observed = exemplar.observation_date.isoformat()
            records.append({"commodity": query["commodity"], "crop_name": query["commodity"],
                "commodity_id": crop_id(query), "category": query.get("category"),
                "crop_aliases": query["aliases"], "market": "Tamil Nadu statewide reference",
                "district": None, "state": "Tamil Nadu", "variety": exemplar.variety,
                "grade": exemplar.grade, "unit": key[3], "currency": "INR",
                "price_paise": amount, "price_display": f"₹{amount / 100:,.2f}",
                "price_type": "calculated_reference", "quote_type": "median_range_midpoint" if tn else "median_modal",
                "arrival_date": observed, "observation_date": observed,
                "observation_dates": [observed], "observation_count": len(selected),
                "aggregation_method": TN_METHOD if tn else METHOD, "aggregation_minimum": minimum,
                "reference_scope": "statewide", "reference_label": LABEL,
                "source": exemplar.source, "source_url": exemplar.source_url,
                **({"market_type": "uzhavar_santhai", "reference_label": "Tamil Nadu Uzhavar Santhai reference — median of available market range midpoints"} if tn else {}),
                "source_records": [q.model_dump(mode="json") for q in selected],
                "evidence_ids": [q.evidence_id for q in selected],
                "verification_status": "verified", "verification_method": "statewide_source_median",
                "retrieved_at": stamp, "last_successful_refresh_at": stamp,
                "stale": exemplar.observation_date != stamp.astimezone(IST).date(),
                "freshness_status": "fresh" if exemplar.observation_date == stamp.astimezone(IST).date() else "stale"})
    return records


def matches(record, commodity=None, market=None, state=None, district=None):
    if record.get("verification_method") != "statewide_source_median":
        return observation_matches(record, commodity, market, state, district)
    try:
        if state and normalized(state) != "tamil nadu":
            return False
        query = statewide_query({"commodity": record["commodity"], "category": record.get("category"),
                                "variety": record.get("variety"), "aliases": record.get("crop_aliases", [])})
        if commodity and not any(canonical_commodity(commodity) == canonical_commodity(n)
                                 for n in [query["commodity"], *query["aliases"]]):
            return False
        quotes = [SourceQuote.model_validate_json(json.dumps(q), context={"history": True})
                  for q in record["source_records"]]
        stamp = record["retrieved_at"]
        if isinstance(stamp, str):
            stamp = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=timezone.utc)
        candidates = aggregate(quotes, [query], stamp, record["aggregation_minimum"], history=True)
        fields = ("commodity_id", "market", "state", "district", "variety", "grade", "unit", "currency",
                  "price_paise", "arrival_date", "observation_dates", "observation_count", "aggregation_method",
                  "reference_scope", "source_url", "source", "evidence_ids", "verification_status", "verification_method",
                  "quote_type", "price_type", "reference_label", "market_type")
        return len(candidates) == 1 and all(record.get(k) == candidates[0].get(k) for k in fields)
    except (ValueError, KeyError, TypeError, AttributeError):
        return False


class StatewideMarketProvider:
    name = "Tamil Nadu primary-source median"
    matches = staticmethod(matches)

    def __init__(self, retriever=None):
        self.retriever = retriever or TamilNaduMarketRetriever()

    async def search_prices(self, **kwargs):
        return {"records": [], "live": False, "message": "Read the daily statewide cache."}

    async def discover_daily(self, queries):
        base = {"records": [], "observations": [], "live": False, "groq_requests": 0}
        if not settings.MARKET_STATEWIDE_ENABLED or not settings.MARKET_SOURCE_VERIFIED:
            return {**base, "error_code": "DISABLED", "message": "Statewide discovery or source verification gate is disabled."}
        try:
            targets = [statewide_query(q) for q in queries]
            quotes, diagnostics = await self.retriever.retrieve(targets, primary_only=True)
            if any(d in diagnostics for d in ("OGD_SOURCE_UNAVAILABLE", "SOURCE_ROW_LIMIT", "SOURCE_PAGINATION_INVALID")):
                return {**base, "error_code": "SOURCE_INCOMPLETE", "diagnostics": diagnostics,
                        "message": "Official retrieval failed or was incomplete; cache preserved."}
            stamp = datetime.now(timezone.utc)
            records = aggregate(quotes, targets, stamp)
            # Preserve every accepted contributing observation in the existing collection.
            from app.integrations.groq_market import normalized_record
            observations = {}
            for raw in quotes:
                quote = SourceQuote.model_validate_json(raw.model_dump_json())
                if normalized(quote.state) != "tamil nadu" or not (quote.source_url == OGD_URL or quote.market_type == "uzhavar_santhai"):
                    continue
                for query in targets:
                    if quote.matches(query):
                        observations[(crop_id(query), quote.evidence_id)] = normalized_record(quote, query, stamp)
            return {**base, "records": records, "observations": list(observations.values()),
                    "diagnostics": diagnostics, "message": "Calculated Tamil Nadu references; insufficient groups remain unavailable."}
        except (TimeoutError, httpx.HTTPError, ValueError, TypeError, KeyError) as exc:
            # Only a stable category is exposed. HTTP exception strings may contain API keys.
            return {**base, "error_code": "SOURCE_" + type(exc).__name__.upper(),
                    "message": "Official source or validation failed; cache preserved."}


market_price_provider = StatewideMarketProvider()
