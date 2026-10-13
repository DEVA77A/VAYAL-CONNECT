"""Synthetic fixtures test contracts; live verification is performed separately."""
import json
import os
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock

import httpx
import pytest

from app.core.config import settings
from app.integrations.market_evidence import IST, SourceQuote
from app.integrations.tn_market import BASE, METHOD, TamilNaduMarketRetriever, crop_mapping, parse_records
from app.integrations.statewide_market import aggregate, matches, StatewideMarketProvider
from app.repositories.pricing import PricingRepository
from tests.test_market_cache_mongo import isolated_market_db


def rows():
    return {"Test market A": {"min": "10", "max": "20", "modal": 99999},
            "Test market B": {"min": "20", "max": "40"},
            "Test market C": {"min": "30", "max": "50"}}


def quotes():
    return parse_records(rows(), 8, datetime.now(IST).date())[0]


@pytest.mark.parametrize("name,expected", [("Tomato", 8), ("தக்காளி", 8),
    ("Banana fruit", 27), ("Banana (fruit)", 27), ("வாழைப்பழம்", 27),
    ("Jasmine", 109), ("மல்லிகை", 109), ("Marigold", 107), ("சாமந்தி", None),
    ("Banana", None), ("Banana stem", None), ("Paddy", None), ("Rose", None)])
def test_explicit_mapping(name, expected):
    assert crop_mapping({"commodity": name}) == expected


def test_ambiguous_aliases_are_unavailable():
    assert crop_mapping({"commodity": "Tomato", "aliases": ["Jasmine"]}) is None


def test_validation_midpoint_provenance_duplicates_and_tampering():
    qs = quotes()
    assert qs[0].price_paise == 1500 and qs[0].modal_price_paise is None
    assert qs[0].original_min_value == "10" and qs[0].unit == "kg"
    r = aggregate(qs + qs, [{"commodity": "Tomato"}], datetime.now(timezone.utc))[0]
    assert r["price_paise"] == 3000 and r["observation_count"] == 3
    assert r["aggregation_method"] == METHOD and matches(r)
    assert not matches({**r, "quote_type": "median_modal"})
    assert not matches({**r, "price_paise": 999})
    bad = qs[0].model_dump(mode="json") | {"observation_date": (datetime.now(IST).date() - timedelta(days=1)).isoformat()}
    with pytest.raises(ValueError):
        SourceQuote.model_validate_json(json.dumps(bad), context={"history": True})
    assert not aggregate(qs[:2], [{"commodity": "Tomato"}], datetime.now(timezone.utc))


@pytest.mark.parametrize("market,row", [("", {"min": "10", "max": "20"}),
    ("Test", {}), ("Test", {"min": None, "max": "20"}),
    ("Test", {"min": "10"}), ("Test", {"min": "-1", "max": "20"}),
    ("Test", {"min": "NaN", "max": "20"}), ("Test", {"min": "10", "max": "Infinity"}),
    ("Test", {"min": "30", "max": "20"}), ("Test", {"min": True, "max": "20"}),
    ("Test", {"min": "10", "max": "20", "unit": "basket"}),
    ("Test", {"min": "10", "max": "20", "date": "01-01-2020"}),
    ("Test", {"min": "10", "max": "20", "crop_id": 999}), ("Test", [])])
def test_one_malformed_market_does_not_break_batch(market, row):
    result, rejected = parse_records({**rows(), market: row}, 8, datetime.now(IST).date())
    assert len(result) == 3 and rejected == 1


def test_zero_lower_bound_and_unknown_crop():
    result, rejected = parse_records({"Test": {"min": "0", "max": "20"}}, 8, datetime.now(IST).date())
    assert rejected == 0 and result[0].price_paise == 1000
    with pytest.raises(ValueError):
        parse_records(rows(), 999, datetime.now(IST).date())


def test_legacy_evidence_hash_is_unchanged():
    import hashlib
    from tests.test_statewide_market import observations
    q = observations()[0]
    old_json = q.model_dump_json(exclude={"market_type", "calculation_method", "unit_evidence_url"})
    assert q.evidence_id == hashlib.sha256(old_json.encode()).hexdigest()


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", [403, 404, 500, "timeout", "connection", "json", "type", "empty"])
async def test_bounded_errors_and_no_credentials(failure):
    calls = []
    def respond(request):
        calls.append(request)
        assert request.method == "POST" and request.content == b""
        assert "authorization" not in request.headers and "cookie" not in request.headers
        assert not request.url.query and str(request.url).startswith(BASE)
        if isinstance(failure, int):
            return httpx.Response(failure)
        if failure == "timeout":
            raise httpx.ReadTimeout("private", request=request)
        if failure == "connection":
            raise httpx.ConnectError("private", request=request)
        if failure == "json":
            return httpx.Response(200, content=b"not JSON")
        return httpx.Response(200, json=[] if failure == "type" else {})
    result, diagnostics = await TamilNaduMarketRetriever(httpx.MockTransport(respond)).retrieve([{"commodity": "Tomato"}])
    assert len(calls) == 1 and not result and diagnostics
    assert "private" not in json.dumps(diagnostics)


@pytest.mark.asyncio
async def test_deduplicated_requests_unsupported_crop_and_partial_failure(monkeypatch):
    monkeypatch.setattr(settings, "MARKET_STATEWIDE_ENABLED", True)
    monkeypatch.setattr(settings, "MARKET_SOURCE_VERIFIED", True)
    monkeypatch.setattr(settings, "GOVERNMENT_MARKET_API_KEY", "")
    calls = []
    def respond(request):
        calls.append(request)
        return httpx.Response(500) if str(request.url).endswith("/109") else httpx.Response(200, json=rows())
    provider = StatewideMarketProvider(TamilNaduMarketRetriever(httpx.MockTransport(respond)))
    result = await provider.discover_daily([{"commodity": "Tomato"}, {"commodity": "தக்காளி"},
        {"commodity": "Jasmine"}, {"commodity": "Paddy"}])
    assert len(calls) == 2 and len(result["records"]) == 2
    assert result["groq_requests"] == 0 and "TN_HTTP_109_500" in result["diagnostics"]
    assert all(matches(r) for r in result["records"])


@pytest.mark.asyncio
async def test_unsupported_crop_sends_no_request():
    def fail(request):
        pytest.fail("Unsupported crop must not trigger HTTP")
    result, diagnostics = await TamilNaduMarketRetriever(httpx.MockTransport(fail)).retrieve([{"commodity": "Paddy"}])
    assert not result and diagnostics == ["TN_UNSUPPORTED_CROP"]


@pytest.mark.asyncio
async def test_repository_repeated_refresh_uses_same_upsert_identity():
    from unittest.mock import MagicMock
    db = MagicMock()
    db.__getitem__.return_value.update_one = AsyncMock()
    r = aggregate(quotes(), [{"commodity": "Tomato"}], datetime.now(timezone.utc))[0]
    repo = PricingRepository(db)
    await repo.store_market_prices_bulk([r])
    await repo.store_market_prices_bulk([r])
    calls = db.__getitem__.return_value.update_one.call_args_list
    assert len(calls) == 2 and calls[0].args[0] == calls[1].args[0]
    assert calls[0].kwargs["upsert"] and "$setOnInsert" in calls[0].args[1]


@pytest.mark.asyncio
@pytest.mark.skipif(os.environ.get("VAYALCONNECT_RUN_MONGO_TESTS") != "1", reason="Isolated loopback Mongo opt-in")
async def test_tn_real_cache_roundtrip_failed_refresh_and_rerun(isolated_market_db, monkeypatch):
    from types import SimpleNamespace
    from app.integrations.groq_market import normalized_record
    from app.services.market_discovery import MarketDiscoveryService
    monkeypatch.setattr(settings, "MARKET_DAILY_REFRESH_ENABLED", True)
    db = isolated_market_db
    qs = quotes()
    stamp = datetime.now(timezone.utc)
    query = {"commodity": "Tomato"}
    records = aggregate(qs, [query], stamp)
    raw = [normalized_record(q, query, stamp) for q in qs]
    repo = PricingRepository(db)
    for _ in range(2):
        await repo.store_market_prices_bulk(raw + records)
    assert await db.market_prices.count_documents({}) == 4
    provider = SimpleNamespace(matches=matches, name="Synthetic TN test", discover_daily=AsyncMock(
        return_value={"records": [], "error_code": "SOURCE_TIMEOUT", "diagnostics": ["TN_SOURCE_UNAVAILABLE_8"]}))
    service = MarketDiscoveryService(db, provider)
    lookup = await service.lookup(commodity="Tomato", scope="statewide")
    assert lookup["count"] == 1 and not lookup["records"][0]["stale"]
    assert matches(lookup["records"][0])
    provider.discover_daily.assert_not_awaited()
    service._load_queries = AsyncMock(return_value={"test": query})
    failure = await service.refresh_daily()
    assert failure["failed"] == 1
    assert await db.market_prices.count_documents({}) == 4
    assert (await service.lookup(commodity="Tomato", scope="statewide"))["count"] == 1
    assert (await service.refresh_daily())["skipped"] == 1
    assert provider.discover_daily.await_count == 1
