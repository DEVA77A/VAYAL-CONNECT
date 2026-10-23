"""Synthetic fixtures only: never treat these numbers as actual market prices."""
import json
from contextlib import asynccontextmanager
from datetime import datetime, timezone, timedelta
from types import SimpleNamespace as NS
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from pymongo.errors import DuplicateKeyError
from google.genai import types

from app.integrations.gemini_market import GeminiMarketPriceProvider, validate_candidate, public_url, source_page, SourcePage, error_diagnostics
from app.integrations.market_evidence import SourceQuote, IST
from app.integrations.groq_market import normalized_record
from app.services.market_discovery import MarketDiscoveryService
from app.services.pricing_service import PricingEngine


def candidate(**changes):
    today = datetime.now(timezone.utc).date().isoformat()
    quote = f"{today} Coimbatore flower market, Coimbatore district, Tamil Nadu. Wholesale Jasmine Rs. 500 per bunch."
    return dict(crop_name="Jasmine", category="Flowers", variety=None, state="Tamil Nadu",
        district="Coimbatore", market="Coimbatore flower market", unit="bunch", currency="INR",
        observation_date=today, price_type="wholesale", price="500", min_price=None,
        max_price=None, modal_price=None, source_url="https://example.org/flowers",
        evidence=quote, price_evidence="Jasmine Rs. 500 per bunch", **changes)


def verified_record(**changes):
    observed = changes.get("arrival_date") or datetime.now(IST).date().isoformat()
    query = {"commodity": "Jasmine", "category": "Flowers", "market": "Coimbatore flower market",
             "state": "Tamil Nadu", "district": "Coimbatore", "variety": changes.get("variety")}
    source = SourceQuote.model_validate_json(json.dumps({"commodity": "Jasmine",
        "market": query["market"], "district": query["district"], "state": query["state"],
        "unit": changes.get("unit", "bunch"), "currency": "INR", "price_paise": 50000,
        "observation_date": observed, "source": "Synthetic flower feed",
        "source_url": changes.get("source_url", "https://example.org/flowers"),
        "variety": changes.get("variety")}), context={"history": True})
    record = normalized_record(source, query, changes.get("retrieved_at", datetime.now(timezone.utc)))
    return {**record, "price_type": "wholesale", **changes}


def discovery(records, live=True):
    return dict(records=records, live=live, count=len(records), source="Gemini grounded discovery", message="Verified test fixture")


def db_fixture():
    db = MagicMock()
    collections = {}
    def get(name):
        if name not in collections:
            collections[name] = NS(update_one=AsyncMock(return_value=NS(modified_count=1, upserted_id=None)))
        return collections[name]
    db.__getitem__.side_effect = get
    return db


@pytest.mark.parametrize("unit", ["bunch", "bundle", "kg", "count"])
def test_original_units_and_missing_modal_preserved(unit):
    raw = candidate()
    raw.update(unit=unit, evidence=raw["evidence"].replace("bunch", unit),
               price_evidence=raw["price_evidence"].replace("bunch", unit))
    result = validate_candidate(raw, "Jasmine", "Tamil Nadu", "Coimbatore", None,
        raw["evidence"], raw["evidence"], "Bulletin")
    assert result["unit"] == unit and result["price_paise"] == 50000
    assert result["modal_price_paise"] is None and not result["modal_price_verified"]
    assert (result["price_per_kg_paise"] is not None) == (unit == "kg")


@pytest.mark.parametrize("field,value", [("crop_name", "Rose"), ("state", "Kerala"),
    ("district", "Madurai"), ("market", "Other"), ("price", "NaN"), ("price", -1),
    ("price", True), ("price", "500.001"), ("price", 600), ("currency", "USD"),
    ("unit", "kg"), ("observation_date", "2999-01-01"), ("observation_date", None),
    ("evidence", "invented statement"), ("price_evidence", "Rose Rs. 500 per bunch"),
    ("price_type", "retail"), ("modal_price", 500), ("variety", "Invented variety")])
def test_candidate_rejects_wrong_identity_or_unbacked_fields(field, value):
    raw = candidate()
    page = raw["evidence"]
    raw[field] = value
    assert validate_candidate(raw, "Jasmine", "Tamil Nadu", "Coimbatore",
        "Coimbatore flower market", page, page, "Bulletin") is None


def response_for(raw, grounded=True):
    text = json.dumps({"records": [raw]})
    metadata = types.GroundingMetadata(grounding_chunks=[types.GroundingChunk(
        web=types.GroundingChunkWeb(uri=raw["source_url"], title="Bulletin"))],
        grounding_supports=[types.GroundingSupport(grounding_chunk_indices=[0],
            segment=types.Segment(text=text))]) if grounded else None
    return types.GenerateContentResponse(candidates=[types.Candidate(
        content=types.Content(parts=[types.Part(text=text)]), grounding_metadata=metadata)])


@pytest.mark.asyncio
async def test_grounding_and_source_access_are_both_required():
    provider = GeminiMarketPriceProvider()
    raw = candidate()
    with patch("app.integrations.gemini_market.source_page", AsyncMock(return_value=raw["evidence"])):
        assert await provider._validate_response(response_for(raw), "Jasmine", None, None, None)
        assert not await provider._validate_response(response_for(raw, False), "Jasmine", None, None, None)
        assert not await provider._validate_response(response_for(raw), "Rose", None, None, None)
    with patch("app.integrations.gemini_market.source_page", AsyncMock(return_value=None)):
        assert not await provider._validate_response(response_for(raw), "Jasmine", None, None, None)


@pytest.mark.asyncio
async def test_missing_key_returns_clear_unavailability(monkeypatch):
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "")
    result = await GeminiMarketPriceProvider().discover_daily([dict(commodity="Unlisted medicinal crop")])
    assert not result["live"] and "GEMINI_API_KEY" in result["message"] and not result["records"]


@pytest.mark.asyncio
async def test_local_model_priority_selects_one_eligible_model_without_extra_calls(monkeypatch):
    from google import genai
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "synthetic-private-key")
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_MARKET_MODELS", "invented,gemini-3.8-flash,gemini-3.8-flash,gemini-3.5-flash-lite")
    raw = candidate()
    generate = AsyncMock(return_value=response_for(raw))
    listing = AsyncMock(side_effect=AssertionError("model listing violates one-request budget"))
    @asynccontextmanager
    async def aio_client():
        yield NS(models=NS(list=listing, generate_content=generate))
    client = MagicMock(return_value=NS(aio=aio_client()))
    with patch.object(genai, "Client", client), \
        patch("app.integrations.gemini_market.source_page", AsyncMock(return_value=raw["evidence"])):
        result = await GeminiMarketPriceProvider().discover_daily([dict(commodity="Jasmine", category="Flowers")])
    assert result["live"] and len(result["records"]) == 1
    generate.assert_awaited_once()
    listing.assert_not_awaited()
    assert generate.call_args.kwargs["model"] == "gemini-3.8-flash"
    assert generate.call_args.kwargs["config"].tools[0].google_search is not None
    assert client.call_args.kwargs["http_options"].retry_options.attempts == 1
    assert "synthetic-private-key" not in json.dumps(result, default=str)


@pytest.mark.asyncio
@pytest.mark.parametrize("code, expected", [(400, "key validity"), (401, "credentials invalid"),
    (429, "quota/billing"), (403, "access denied"), (404, "model unavailable"), (503, "failed or timed out")])
async def test_upstream_failure_never_retries_or_falls_back(monkeypatch, code, expected):
    from google import genai
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "synthetic-private-key")
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_MARKET_RETRIES", 2)
    error = Exception("synthetic-private-key must never appear in the response")
    error.code = code
    generate = AsyncMock(side_effect=error)
    @asynccontextmanager
    async def aio_client():
        yield NS(models=NS(generate_content=generate))
    with patch.object(genai, "Client", return_value=NS(aio=aio_client())):
        result = await GeminiMarketPriceProvider().discover_daily([dict(commodity="Jasmine")])
    assert not result["live"] and not result["records"]
    assert expected in result["message"] and result["error_code"] == code
    assert "synthetic-private-key" not in json.dumps(result)
    generate.assert_awaited_once()


def quota_error():
    from google.genai.errors import ClientError
    return ClientError(429, {"error": {"code": 429, "status": "RESOURCE_EXHAUSTED",
        "message": "synthetic-private-key and private project data must not be logged",
        "details": [{"@type": "type.googleapis.com/google.rpc.QuotaFailure",
            "violations": [{"quotaMetric": "generativelanguage.googleapis.com/generate_content_free_tier_requests",
                "quotaId": "GenerateRequestsPerDayPerProjectPerModel-FreeTier", "quotaValue": "0",
                "quotaDimensions": {"model": "gemini-3.8-flash", "location": "global", "project": "private-project"}}]},
            {"@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": "RATE_LIMIT_EXCEEDED",
                "metadata": {"api_key": "synthetic-private-key", "consumer": "private-project"}}]}})


def test_quota_diagnostics_extract_exact_structured_fields_without_secrets(monkeypatch):
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "synthetic-private-key")
    result = error_diagnostics(quota_error(), "gemini-3.8-flash")
    assert result["http_status"] == 429 and result["status"] == "RESOURCE_EXHAUSTED"
    assert result["quota_violations"] == [{
        "quotaMetric": "generativelanguage.googleapis.com/generate_content_free_tier_requests",
        "quotaId": "GenerateRequestsPerDayPerProjectPerModel-FreeTier", "quotaValue": "0",
        "quotaDimensions": {"model": "gemini-3.8-flash", "location": "global"}}]
    assert result["reasons"] == ["RATE_LIMIT_EXCEEDED"]
    assert "synthetic-private-key" not in json.dumps(result)
    assert "private-project" not in json.dumps(result)


@pytest.mark.parametrize("details", [None, "unstructured", {"error": {"details": None}},
    {"error": {"details": [None, {"@type": "type.googleapis.com/google.rpc.QuotaFailure", "violations": None}]}}])
def test_quota_diagnostics_do_not_infer_a_missing_metric_or_reason(details):
    result = error_diagnostics(NS(code=429, details=details), "gemini-3.8-flash")
    assert result["quota_violations"] == [] and result["reasons"] == []


@pytest.mark.asyncio
async def test_real_sdk_quota_error_captured_once_and_saved_without_cache_overwrite(monkeypatch, caplog):
    from google import genai
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "synthetic-private-key")
    generate = AsyncMock(side_effect=quota_error())
    @asynccontextmanager
    async def aio_client():
        yield NS(models=NS(generate_content=generate))
    db, claims, runs = daily_db([dict(commodity="Jasmine", category="Flowers"),
                               dict(commodity="Tomato", category="Vegetables")])
    service = MarketDiscoveryService(db, provider=GeminiMarketPriceProvider())
    service.repo.store_market_prices_bulk = AsyncMock()
    service.repo.list_market_prices = AsyncMock(return_value=[verified_record()])
    with patch.object(genai, "Client", return_value=NS(aio=aio_client())):
        first = await service.refresh_daily()
        second = await service.refresh_daily()
    assert first["error_code"] == 429 and second["skipped"] == 1
    generate.assert_awaited_once()
    service.repo.store_market_prices_bulk.assert_not_awaited()
    saved = next(call.args[1]["$set"]["diagnostics"] for call in claims.update_one.call_args_list
                 if "diagnostics" in call.args[1]["$set"])
    assert saved["request_model"] == "gemini-3.8-flash"
    assert saved["quota_violations"][0]["quotaValue"] == "0"
    assert "synthetic-private-key" not in caplog.text
    assert "private-project" not in caplog.text
    active_cache = MarketDiscoveryService(db)
    active_cache.repo.list_market_prices = service.repo.list_market_prices
    assert (await active_cache.lookup(commodity="Jasmine"))["count"] == 1


@pytest.mark.asyncio
async def test_invalid_grounding_does_not_trigger_second_model(monkeypatch):
    from google import genai
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "fixture")
    generate = AsyncMock(return_value=response_for(candidate(), grounded=False))
    @asynccontextmanager
    async def aio_client():
        yield NS(models=NS(generate_content=generate))
    with patch.object(genai, "Client", return_value=NS(aio=aio_client())):
        result = await GeminiMarketPriceProvider().discover_daily([dict(commodity="Jasmine")])
    assert not result["live"] and not result["records"]
    generate.assert_awaited_once()


@pytest.mark.asyncio
async def test_batch_validates_each_requested_crop_and_reuses_source_fetch():
    raw = candidate()
    rows = [raw]
    for crop in ("Tomato", "Mango", "Novel aromatic seedling", "Unrequested crop"):
        rows.append({**raw, "crop_name": crop,
            "evidence": raw["evidence"].replace("Jasmine", crop),
            "price_evidence": raw["price_evidence"].replace("Jasmine", crop)})
    response = response_for(raw)
    text = json.dumps({"records": rows})
    response.candidates[0].content.parts[0].text = text
    response.candidates[0].grounding_metadata.grounding_supports[0].segment.text = text
    queries = [dict(commodity=c, category=category) for c, category in
        (("Jasmine", "Flowers"), ("Tomato", "Vegetables"), ("Mango", "Fruits"),
         ("Novel aromatic seedling", "Nursery"))]
    with patch("app.integrations.gemini_market.source_page", AsyncMock(return_value=" ".join(
            r["evidence"] for r in rows))) as fetch:
        records = await GeminiMarketPriceProvider()._validate_response(response, queries=queries)
    assert {r["commodity"] for r in records} == {q["commodity"] for q in queries}
    assert {r["category"] for r in records} == {q["category"] for q in queries}
    assert all(r["unit"] == "bunch" for r in records)
    fetch.assert_awaited_once()


@pytest.mark.asyncio
async def test_legacy_on_demand_provider_entrypoint_cannot_dispatch():
    from google import genai
    with patch.object(genai, "Client") as client:
        outcome = await GeminiMarketPriceProvider().search_prices(commodity="Jasmine")
    client.assert_not_called()
    assert not outcome["live"] and "disabled" in outcome["message"]


@pytest.mark.asyncio
async def test_total_timeout_is_bounded(monkeypatch):
    import asyncio
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "fixture")
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_MARKET_TOTAL_TIMEOUT_SECONDS", 0.01)
    provider = GeminiMarketPriceProvider()
    async def hanging(*args):
        await asyncio.sleep(10)
    with patch.object(provider, "_discover", hanging):
        result = await provider.discover_daily([dict(commodity="Jasmine")])
    assert not result["live"] and "timed out" in result["message"]


@pytest.mark.asyncio
@pytest.mark.parametrize("records_kind", ["fresh", "stale", "empty"])
async def test_all_application_lookups_are_cache_only_even_with_refresh(records_kind):
    service = MarketDiscoveryService(db_fixture())
    record = verified_record(arrival_date=(datetime.now(IST).date() - timedelta(days=3)).isoformat()) \
        if records_kind == "stale" else verified_record()
    cached = [] if records_kind == "empty" else [record, {**record, "verification_status": "unverified"}]
    service.repo.list_market_prices = AsyncMock(return_value=cached)
    with patch("app.services.market_discovery.market_price_provider.discover_daily", AsyncMock()) as batch, \
        patch("app.services.market_discovery.market_price_provider.search_prices", AsyncMock()) as per_crop:
        for refresh in (False, True):
            result = await service.lookup(commodity="Jasmine", refresh=refresh)
            assert not result["live"]
            assert result["count"] == (0 if records_kind == "empty" else 1)
            if result["records"]:
                assert result["records"][0]["stale"] == (records_kind == "stale")
        batch.assert_not_awaited()
        per_crop.assert_not_awaited()


@pytest.mark.asyncio
async def test_flower_reference_has_no_invalid_weight_conversion():
    from tests.test_statewide_market import reference_fixture
    record = reference_fixture("Jasmine", "Flowers", "bunch", 50000)
    with patch("app.services.pricing_service.MarketDiscoveryService.lookup", AsyncMock(return_value=discovery([record]))):
        result = await PricingEngine(MagicMock()).get_verified_reference("Jasmine", "Coimbatore flower market", "KG")
    assert result["reference_price_available"]
    assert result["reference_price_unit"] == "bunch"
    assert result["reference_price_per_listing_unit_paise"] is None
    assert len(result["reference_records"]) == 1


@pytest.mark.asyncio
async def test_count_reference_is_comparable_with_same_listing_unit():
    from tests.test_statewide_market import reference_fixture
    record = reference_fixture("Jasmine", "Flowers", "count", 50000)
    with patch("app.services.pricing_service.MarketDiscoveryService.lookup", AsyncMock(return_value=discovery([record]))):
        result = await PricingEngine(MagicMock()).get_verified_reference("Jasmine", "Coimbatore flower market", "COUNT")
    assert result["reference_price_per_listing_unit_paise"] == 50000
    assert result["reference_price_unit"] == "piece"


@pytest.mark.asyncio
async def test_internal_sources_are_never_requested():
    with patch("socket.getaddrinfo", return_value=[(2, 1, 6, "", ("127.0.0.1", 443))]), \
        patch("httpx.AsyncClient") as client:
        assert await source_page("https://internal.example/price") is None
        client.assert_not_called()
    for url in ("http://example.org", "https://user:password@example.org", "https://example.org:8443"):
        assert not public_url(url)


@pytest.mark.asyncio
async def test_google_grounding_redirect_resolves_to_actual_source():
    provider = GeminiMarketPriceProvider()
    raw = candidate()
    response = response_for(raw)
    redirect = "https://vertexaisearch.cloud.google.com/grounding-api-redirect/fixture"
    response.candidates[0].grounding_metadata.grounding_chunks[0].web.uri = redirect
    with patch("app.integrations.gemini_market.source_page", AsyncMock(return_value=SourcePage(raw["evidence"], raw["source_url"]))) as fetch:
        result = await provider._validate_response(response, "Jasmine", None, None, None)
    assert result[0]["source_url"] == raw["source_url"]
    fetch.assert_awaited_once_with(redirect)


@pytest.mark.parametrize("crop", ["Rose", "Marigold", "Chrysanthemum", "Tuberose", "Novel aromatic seedling"])
def test_no_crop_whitelist(crop):
    raw = candidate()
    raw.update(crop_name=crop, evidence=raw["evidence"].replace("Jasmine", crop),
               price_evidence=raw["price_evidence"].replace("Jasmine", crop))
    record = validate_candidate(raw, crop, None, None, None, raw["evidence"], raw["evidence"], "Bulletin")
    assert record and record["commodity"] == crop


def test_price_from_another_crop_row_is_rejected():
    raw = candidate()
    raw.update(price=100, evidence=raw["evidence"] + " Rose Rs. 100 per bunch.",
               price_evidence="Jasmine Rs. 500 per bunch. Rose Rs. 100 per bunch.")
    assert validate_candidate(raw, "Jasmine", None, None, None, raw["evidence"], raw["evidence"], "Bulletin") is None


def daily_db(queries, products=None):
    db = db_fixture()
    async def iterate(items):
        for item in items:
            yield item
    db["products"].find = lambda *args: iterate(products or [])
    db["farmer_profiles"].find = lambda *args: iterate([])
    db["market_watchlist"].find = lambda *args: iterate([{"query": q} for q in queries])
    claims = NS(update_one=AsyncMock(), insert_one=AsyncMock(), find_one_and_update=AsyncMock(return_value={"_id": "refresh-lock"}))
    claims.with_options = MagicMock(return_value=claims)
    runs = {}
    async def update(query, change, **kwargs):
        if query.get("_id") in runs:
            runs[query["_id"]].update(change.get("$set", {}))
    claims.update_one.side_effect = update
    async def insert(doc):
        if doc["_id"] in runs:
            raise DuplicateKeyError("already reserved")
        runs[doc["_id"]] = dict(doc)
    claims.insert_one.side_effect = insert
    db["market_daily_runs"].with_options = claims.with_options
    return db, claims, runs


@pytest.mark.asyncio
async def test_daily_batch_covers_deduplicated_crops_categories_and_duplicate_workers(monkeypatch):
    import asyncio
    from google import genai
    monkeypatch.setattr("app.services.market_discovery.settings.GEMINI_API_KEY", "fixture")
    crops = [("Jasmine", "Flowers"), ("Tomato", "Vegetables"), ("Mango", "Fruits"),
             ("Novel medicinal plant", "Medicinal plants")]
    queries = [dict(commodity=crop, category=category) for crop, category in crops]
    db, claims, runs = daily_db(queries + [dict(commodity=" jasmine ", category="flowers")],
        products=[dict(product_name="Rose", category="Flowers", status="ACTIVE")])
    # Retain the legacy Gemini provider's one-request test through explicit
    # dependency injection; the application default now selects pyPricingAPI.
    service = MarketDiscoveryService(db, provider=GeminiMarketPriceProvider())
    service.lookup = AsyncMock(side_effect=AssertionError("no per-crop lookups"))
    service.repo.store_market_prices_bulk = AsyncMock()
    raw = candidate()
    async def respond(**kwargs):
        assert len(runs) == 1  # Reserve before any upstream dispatch.
        return response_for(raw)
    generate = AsyncMock(side_effect=respond)
    @asynccontextmanager
    async def aio_client():
        yield NS(models=NS(generate_content=generate))
    with patch.object(genai, "Client", return_value=NS(aio=aio_client())), \
        patch("app.integrations.gemini_market.source_page", AsyncMock(return_value=raw["evidence"])), \
        patch("app.services.market_discovery.market_price_provider.search_prices", AsyncMock()) as per_crop:
        results = await asyncio.gather(service.refresh_daily(), service.refresh_daily())
        third = await service.refresh_daily()
    assert sum(r["completed"] for r in results) == 1
    assert sum(r["skipped"] for r in results) == 1 and third["skipped"] == 1
    generate.assert_awaited_once()
    prompt = generate.call_args.kwargs["contents"]
    for crop, category in crops + [("Rose", "Flowers")]:
        assert crop in prompt and category in prompt
    assert next(r for r in results if r["completed"])["contexts"] == 5
    assert len(runs) == 1
    assert len(next(iter(runs.values()))["contexts"]) == 5
    assert claims.with_options.call_args.kwargs["write_concern"].document["w"] == "majority"
    service.lookup.assert_not_awaited()
    per_crop.assert_not_awaited()
    service.repo.store_market_prices_bulk.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize("outcome", [dict(records=[], live=False, message="HTTP 429 quota restriction", error_code=429),
    RuntimeError("failure")])
async def test_failure_consumes_daily_claim_and_preserves_cache(outcome):
    db, claims, runs = daily_db([dict(commodity="Jasmine", category="Flowers")])
    service = MarketDiscoveryService(db)
    before = verified_record()
    service.repo.list_market_prices = AsyncMock(return_value=[before])
    service.repo.store_market_prices_bulk = AsyncMock()
    upstream = AsyncMock(side_effect=outcome) if isinstance(outcome, Exception) else AsyncMock(return_value=outcome)
    with patch("app.services.market_discovery.market_price_provider.discover_daily", upstream):
        first = await service.refresh_daily()
        second = await service.refresh_daily()
        lookup = await service.lookup(commodity="Jasmine", refresh=True)
    assert first["failed"] + first["unavailable"] == 1 and second["skipped"] == 1
    upstream.assert_awaited_once()
    service.repo.store_market_prices_bulk.assert_not_awaited()
    assert lookup["records"][0]["price_paise"] == before["price_paise"]
    assert before == verified_record(retrieved_at=before["retrieved_at"])
    assert len(runs) == 1


@pytest.mark.asyncio
async def test_crash_after_reservation_cannot_repeat_daily_attempt():
    import asyncio
    db, claims, runs = daily_db([dict(commodity="Jasmine")])
    upstream = AsyncMock(side_effect=asyncio.CancelledError())
    with patch("app.services.market_discovery.market_price_provider.discover_daily", upstream):
        with pytest.raises(asyncio.CancelledError):
            await MarketDiscoveryService(db).refresh_daily()
        resumed = await MarketDiscoveryService(db).refresh_daily()
    assert resumed["skipped"] == 1 and len(runs) == 1
    upstream.assert_awaited_once()


@pytest.mark.asyncio
async def test_daily_day_key_uses_ist_and_next_day_allows_one_new_attempt(monkeypatch):
    import app.services.market_discovery as module
    stamp = datetime(2026, 10, 12, 21, tzinfo=timezone.utc)  # 13 October IST.
    class Clock(datetime):
        @classmethod
        def now(cls, tz=None):
            return stamp.astimezone(tz) if tz else stamp.replace(tzinfo=None)
    monkeypatch.setattr(module, "datetime", Clock)
    db, claims, runs = daily_db([dict(commodity="Jasmine")])
    with patch.object(module.market_price_provider, "discover_daily",
            AsyncMock(return_value=discovery([]))) as upstream:
        await MarketDiscoveryService(db).refresh_daily()
        assert "batch:2026-10-13" in runs
        assert (await MarketDiscoveryService(db).refresh_daily())["skipped"] == 1
        stamp += timedelta(days=1)
        await MarketDiscoveryService(db).refresh_daily()
        assert "batch:2026-10-14" in runs
    assert upstream.await_count == 2


@pytest.mark.asyncio
async def test_unacknowledged_reservation_never_dispatches():
    from pymongo.errors import AutoReconnect
    db, claims, runs = daily_db([dict(commodity="Jasmine")])
    claims.insert_one.side_effect = AutoReconnect("ambiguous reservation acknowledgement")
    with patch("app.services.market_discovery.market_price_provider.discover_daily", AsyncMock()) as upstream:
        with pytest.raises(AutoReconnect):
            await MarketDiscoveryService(db).refresh_daily()
    upstream.assert_not_awaited()


@pytest.mark.asyncio
async def test_watchlist_failure_does_not_hide_verified_cache():
    from pymongo.errors import AutoReconnect
    db = db_fixture()
    db["market_watchlist"].update_one.side_effect = AutoReconnect("unavailable")
    service = MarketDiscoveryService(db)
    service.repo.list_market_prices = AsyncMock(return_value=[verified_record()])
    with patch("app.services.market_discovery.market_price_provider.discover_daily", AsyncMock()) as upstream:
        result = await service.lookup(commodity="Jasmine")
    assert result["count"] == 1 and not result["live"]
    upstream.assert_not_awaited()


def test_render_cron_is_scheduled_at_eight_ist():
    from pathlib import Path
    blueprint = (Path(__file__).parents[1] / "render.yaml").read_text(encoding="utf-8")
    cron = blueprint.split("  - type: cron", 1)[1]
    assert 'schedule: "30 2 * * *"' in cron
    assert 'dockerCommand: python -m scripts.refresh_market_prices' in cron


def test_flower_reference_api_preserves_multiple_sources_and_original_unit():
    from fastapi.testclient import TestClient
    from app.main import app
    from app.core.database import get_database
    from app.api.deps import get_current_farmer
    db = db_fixture()
    app.dependency_overrides[get_database] = lambda: db
    app.dependency_overrides[get_current_farmer] = lambda: {"id": "fixture", "role": "FARMER"}
    from tests.test_statewide_market import reference_fixture
    first = reference_fixture("Jasmine", "Flowers", "bunch", 50000)
    second = reference_fixture("Jasmine", "Flowers", "bunch", 50000, variety="Local")
    try:
        with patch("app.repositories.pricing.PricingRepository.list_market_prices", AsyncMock(return_value=[first, second])), \
             patch("app.services.market_discovery.market_price_provider.discover_daily", AsyncMock()) as upstream:
            cache_response = TestClient(app).get("/api/v1/market-prices", params={
                "commodity": "Jasmine", "state": "Tamil Nadu", "district": "Coimbatore"})
            latest_response = TestClient(app).get("/api/v1/market-prices/latest", params={
                "commodity": "Jasmine", "state": "Tamil Nadu"})
            result = TestClient(app).get("/api/v1/products/price-reference", params={
                "commodity": "Jasmine", "market": "Coimbatore flower market", "unit": "KG",
                "state": "Tamil Nadu", "district": "Coimbatore", "category": "Flowers"})
        assert result.status_code == 200
        assert cache_response.status_code == 200 and latest_response.status_code == 200
        assert cache_response.json()["data"]["live"] is False
        upstream.assert_not_awaited()
        data = result.json()["data"]
        assert data["reference_price_available"]
        assert data["reference_price_per_listing_unit_paise"] is None
        assert len(data["reference_records"]) == 2
        assert data["reference_records"][0]["modal_price_paise"] is None
        assert data["reference_records"][0]["unit"] == "bunch"
        assert data["reference_market"] == "Tamil Nadu statewide reference"
        assert all(r["observation_count"] == 3 for r in data["reference_records"])
    finally:
        app.dependency_overrides.pop(get_database, None)
        app.dependency_overrides.pop(get_current_farmer, None)


@pytest.mark.asyncio
async def test_discovery_does_not_hold_financial_transaction_open():
    from app.core.transactions import current_session
    service = MarketDiscoveryService(db_fixture())
    outer_session = object()
    token = current_session.set(outer_session)
    async def check_scope(**query):
        assert current_session.get() is None
        return discovery([])
    try:
        with patch.object(service, "_lookup", check_scope):
            await service.lookup(commodity="Jasmine")
        assert current_session.get() is outer_session
    finally:
        current_session.reset(token)
