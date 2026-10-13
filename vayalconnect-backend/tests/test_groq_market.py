"""Synthetic source records and MockTransport only; zero live API quota."""
import asyncio
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from fastapi.testclient import TestClient
from pymongo.errors import PyMongoError, DuplicateKeyError
from app.core.config import settings
from app.integrations.market_evidence import SourceQuote, MarketEvidenceRetriever, IST, paise
from app.integrations.groq_market import GroqMarketProvider, context_id, crop_id, matches, normalized_record
from app.services.market_discovery import MarketDiscoveryService
from tests.market_fixtures import daily_db


def target(crop="Jasmine", **changes):
    return {**dict(commodity=crop, market="Madurai", district="Madurai", state="Tamil Nadu", category="Flowers"), **changes}


def quote(crop="Jasmine", **changes):
    return SourceQuote(commodity=crop, market="Madurai", district="Madurai", state="Tamil Nadu",
        unit="bunch", currency="INR", price_paise=12500,
        observation_date=datetime.now(IST).date(), source="Synthetic reviewed feed",
        source_url="https://example.org/prices.json", **changes)


@pytest.fixture
def configured(monkeypatch):
    monkeypatch.setattr(settings, "GROQ_API_KEY", "synthetic-secret-not-real")
    monkeypatch.setattr(settings, "GROQ_MARKET_ENABLED", True)
    monkeypatch.setattr(settings, "GROQ_MODEL", "openai/gpt-oss-120b")
    monkeypatch.setattr(settings, "GROQ_REQUEST_TOKEN_BUDGET", 100000)
    monkeypatch.setattr(settings, "GROQ_MAX_COMPLETION_TOKENS", 4096)
    monkeypatch.setattr(settings, "MARKET_CURRENT_MAX_DAYS", 0)
    monkeypatch.setattr(settings, "MARKET_STATEWIDE_ENABLED", True)
    monkeypatch.setattr(settings, "MARKET_SOURCE_VERIFIED", True)


def provider_with(quotes):
    return GroqMarketProvider(retriever=MagicMock(retrieve=AsyncMock(return_value=(quotes, []))))


def transport_factory(respond):
    real = httpx.AsyncClient
    def factory(**kwargs):
        assert kwargs.get("follow_redirects") is False
        kwargs["transport"] = httpx.MockTransport(respond)
        return real(**kwargs)
    return factory


def completion(results):
    return {"choices": [{"finish_reason": "stop", "message": {"content": json.dumps({"results": results})}}]}


def selection(q, evidence=None, status="verified"):
    return dict(context_id=context_id(q), crop_id=crop_id(q), status=status, evidence_id=evidence.evidence_id if evidence else None)


@pytest.mark.asyncio
async def test_missing_key_no_retrieval_or_http(configured, monkeypatch):
    monkeypatch.setattr(settings, "GROQ_API_KEY", "")
    provider = provider_with([quote()])
    with patch("httpx.AsyncClient") as client:
        result = await provider.discover_daily([target()])
    assert result["error_code"] == "MISSING_API_KEY"
    client.assert_not_called()
    provider.retriever.retrieve.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["401", "403", "429", "500", "timeout", "malformed", "truncated", "wrong_schema", "missing_source", "unknown_crop", "wrong_location", "duplicates", "invented_price", "missing_context"])
async def test_failures_one_dispatch_no_retry_no_secret(configured, kind, caplog):
    q, evidence, requests = target(), quote(), []
    def respond(request):
        requests.append(request)
        if kind.isdigit():
            return httpx.Response(int(kind), json={"error": "synthetic-secret-not-real"})
        if kind == "timeout":
            raise httpx.ReadTimeout("synthetic-secret-not-real", request=request)
        if kind == "malformed":
            return httpx.Response(200, content=b"{bad")
        row = selection(q, evidence)
        if kind == "unknown_crop": row["crop_id"] = "unknown"
        if kind == "missing_source": row["evidence_id"] = "invented"
        if kind == "wrong_location": row["context_id"] = "unrequested-location"
        if kind == "invented_price": row["price_paise"] = 123
        rows = [row, row] if kind == "duplicates" else [] if kind == "missing_context" else [row]
        body = completion(rows)
        if kind == "truncated": body["choices"][0]["finish_reason"] = "length"
        if kind == "wrong_schema": body = {"results": rows}
        return httpx.Response(200, json=body)
    with patch("httpx.AsyncClient", side_effect=transport_factory(respond)):
        result = await provider_with([evidence]).discover_daily([q])
    assert len(requests) == 1 and result["groq_requests"] == 1
    assert not result["records"] and result["error_code"]
    assert "synthetic-secret-not-real" not in json.dumps(result) + caplog.text


@pytest.mark.asyncio
async def test_complete_batch_new_categories_flowers_tamil_english_and_unavailable(configured):
    targets = [target(), target("மல்லிகை"), target("Novel aromatic plant", category="New category"), target("Rose")]
    quotes = [quote(), quote("மல்லிகை"), quote("Novel aromatic plant")]
    requests = []
    def respond(request):
        requests.append(request)
        body = json.loads(request.content)
        assert body["model"] == settings.GROQ_MODEL and body["response_format"]["json_schema"]["strict"]
        batch = json.loads(body["messages"][1]["content"])
        assert len(batch["contexts"]) == 4
        assert {c["commodity"] for c in batch["contexts"]} == {q["commodity"] for q in targets}
        return httpx.Response(200, json=completion([selection(q, quotes[i]) if i < 3 else
            selection(q, status="unavailable") for i, q in enumerate(targets)]))
    with patch("httpx.AsyncClient", side_effect=transport_factory(respond)):
        result = await provider_with(quotes).discover_daily(targets)
    assert len(requests) == 1 and len(result["records"]) == 3
    for row in result["records"]:
        assert row["price_paise"] == 12500 and row["unit"] == "bunch" and matches(row)
        assert matches(row, row["commodity"], "Madurai", "Tamil Nadu", "Madurai")
        assert not matches(row, "Unrelated crop")
    assert result["context_statuses"][-1]["status"] == "unavailable"


@pytest.mark.parametrize("field,value", [("price_paise", -1), ("price_paise", True), ("price_paise", "123"),
    ("price_paise", 1.2), ("price_paise", 0), ("unit", "bucket"), ("currency", "USD"),
    ("source_url", "http://example.org"), ("source_url", "https://localhost/x"),
    ("source_url", "https://example.org/?api-key=hidden"), ("market", ""), ("source", ""),
    ("observation_date", "bad"), ("observation_date", "2999-01-01"), ("min_price_paise", 999999)])
def test_source_invalid_fields_rejected(field, value):
    raw = quote().model_dump(mode="json")
    raw[field] = value
    with pytest.raises(ValueError): SourceQuote.model_validate_json(json.dumps(raw))


@pytest.mark.parametrize("value", ["NaN", "Infinity", "-Infinity", "1.001", True, None])
def test_amount_invalid_or_imprecise(value):
    with pytest.raises(ValueError): paise(value)


@pytest.mark.parametrize("change", [
    {"original_price_value": "NaN", "original_unit": "bunch"},
    {"original_price_value": "Infinity", "original_unit": "bunch"},
    {"original_price_value": "0", "original_unit": "bunch"},
    {"original_price_value": "125", "original_unit": "kg"},
    {"original_price_value": "125", "original_unit": None},
    {"original_min_value": "200", "original_unit": "bunch"},
])
def test_original_source_value_must_match_normalized_quote(change):
    raw = quote().model_dump(mode="json") | change
    with pytest.raises(ValueError):
        SourceQuote.model_validate_json(json.dumps(raw))


@pytest.mark.asyncio
async def test_no_evidence_no_ai_and_batch_limits_no_silent_split(configured, monkeypatch):
    with patch("httpx.AsyncClient") as client:
        assert (await provider_with([]).discover_daily([target()]))["error_code"] == "NO_CURRENT_EVIDENCE"
        monkeypatch.setattr(settings, "GROQ_REQUEST_TOKEN_BUDGET", 1024)
        assert (await provider_with([quote()]).discover_daily([target()]))["error_code"] == "BATCH_LIMIT"
    client.assert_not_called()


@pytest.mark.asyncio
async def test_missing_market_or_state_cannot_select_arbitrary_source(configured):
    for incomplete in (target(market=None), target(state=None)):
        with patch("httpx.AsyncClient") as client:
            result = await provider_with([quote()]).discover_daily([incomplete])
        assert result["error_code"] == "NO_CURRENT_EVIDENCE"
        client.assert_not_called()


def test_legacy_ai_and_unverified_provider_rows_remain_history_only():
    row = normalized_record(quote(), target(), datetime.now(timezone.utc))
    for method in ("grounding_and_source_excerpt", "provider_reported_quote"):
        assert not matches({**row, "verification_method": method})


@pytest.mark.asyncio
async def test_missing_market_location_skips_source_network(configured, monkeypatch):
    monkeypatch.setattr(settings, "GOVERNMENT_MARKET_API_KEY", "synthetic-ogd-key")
    with patch("httpx.AsyncClient") as client:
        quotes, diagnostics = await MarketEvidenceRetriever().retrieve([target(market=None)])
    assert quotes == [] and diagnostics == ["NO_CONFIRMED_MARKET_LOCATION"]
    client.assert_not_called()


@pytest.mark.asyncio
async def test_ist_daily_claim_uses_next_calendar_day_after_1830_utc(configured, monkeypatch):
    import app.services.market_discovery as discovery_module
    actual_datetime = datetime
    class NextISTDay(actual_datetime):
        @classmethod
        def now(cls, tz=None):
            return actual_datetime(2026, 10, 13, 18, 31, tzinfo=timezone.utc)
    monkeypatch.setattr(discovery_module, "datetime", NextISTDay)
    db, _, runs = daily_db([target()])
    provider = MagicMock(name="mock-provider", matches=matches,
        discover_daily=AsyncMock(return_value={"records": [], "error_code": "NO_CURRENT_EVIDENCE"}))
    result = await MarketDiscoveryService(db, provider).refresh_daily()
    assert result["day"] == "2026-10-14" and "batch:2026-10-14" in runs
    provider.discover_daily.assert_awaited_once()


def test_repository_root_cron_command_time_and_disabled_flags():
    root = Path(__file__).parents[2]
    blueprint = (root / "render.yaml" if (root / "lib").exists() else
                 root / "vayalconnect-flutter" / "render.yaml").read_text(encoding="utf-8")
    if "  - type: cron\n" not in blueprint:
        # Existing deployments need not provision a new service with this change.
        instructions = (Path(__file__).parents[1] / "docs/STATEWIDE_MARKET_PRICES.md").read_text(encoding="utf-8")
        assert "30 2 * * *" in instructions and "python -m scripts.refresh_market_prices" in instructions
        from app.core.config import Settings
        for flag in ("MARKET_DAILY_REFRESH_ENABLED", "MARKET_SOURCE_VERIFIED", "MARKET_STATEWIDE_ENABLED"):
            assert Settings.model_fields[flag].default is False
        return
    cron = blueprint.split("  - type: cron\n", 1)[1]
    assert "dockerContext: vayalconnect-backend" in cron
    assert "dockerCommand: python -m scripts.refresh_market_prices" in cron
    assert 'schedule: "30 2 * * *"' in cron
    assert 'GROQ_MARKET_ENABLED\n        value: "false"' in cron
    assert 'MARKET_DAILY_REFRESH_ENABLED\n        value: "false"' in cron


@pytest.mark.asyncio
async def test_cron_disabled_switch_does_not_connect_or_dispatch(configured, monkeypatch):
    from scripts.refresh_market_prices import main
    monkeypatch.setattr(settings, "MARKET_DAILY_REFRESH_ENABLED", False)
    with patch("scripts.refresh_market_prices.connect_db", AsyncMock()) as connect, \
         patch("app.services.market_discovery.market_price_provider.discover_daily", AsyncMock()) as discover:
        await main()
    connect.assert_not_awaited()
    discover.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["401", "429", "timeout", "connection", "invalid_json",
    "empty", "missing_fields", "missing_source", "unsupported_unit", "stale"])
async def test_reviewed_source_failures_are_unavailable_with_diagnostic(configured, monkeypatch, kind):
    url = "https://example.org/prices.json"
    monkeypatch.setattr(settings, "GOVERNMENT_MARKET_API_KEY", "")
    monkeypatch.setattr(settings, "MARKET_SOURCE_URLS", json.dumps([url]))
    raw = quote().model_dump(mode="json")
    if kind == "missing_fields": raw.pop("observation_date")
    if kind == "missing_source": raw.pop("source_url")
    if kind == "unsupported_unit": raw["unit"] = "basket"
    if kind == "stale": raw["observation_date"] = "2020-01-01"
    requests = []
    def respond(request):
        requests.append(request)
        if kind == "401": return httpx.Response(401)
        if kind == "429": return httpx.Response(429)
        if kind == "timeout": raise httpx.ReadTimeout("synthetic timeout", request=request)
        if kind == "connection": raise httpx.ConnectError("synthetic failure", request=request)
        if kind == "invalid_json": return httpx.Response(200, content=b"{bad")
        return httpx.Response(200, json={"records": [] if kind == "empty" else [raw]})
    with patch("app.integrations.market_evidence.public_source", AsyncMock(return_value=True)), \
         patch("httpx.AsyncClient", side_effect=transport_factory(respond)):
        quotes, diagnostics = await MarketEvidenceRetriever().retrieve([target()])
    assert not quotes and len(requests) == 1
    expected = ("REVIEWED_SOURCE_EMPTY" if kind == "empty" else
                "REVIEWED_ROW_REJECTED" if kind in {"missing_fields", "missing_source", "unsupported_unit", "stale"}
                else "REVIEWED_SOURCE_UNAVAILABLE")
    assert expected in diagnostics


@pytest.mark.asyncio
async def test_lease_database_failure_records_failed_without_provider_call(configured):
    db, claims, runs = daily_db([target()])
    claims.find_one_and_update.side_effect = PyMongoError("synthetic lock failure")
    provider = provider_with([quote()])
    result = await MarketDiscoveryService(db, provider).refresh_daily()
    assert result["failed"] == 1 and len(runs) == 1
    provider.retriever.retrieve.assert_not_awaited()
    assert any(call.args[1]["$set"].get("status") == "failed" for call in claims.update_one.call_args_list)


@pytest.mark.asyncio
async def test_unverified_ai_selection_not_displayable(configured):
    q = target()
    with patch("httpx.AsyncClient", side_effect=transport_factory(lambda request:
            httpx.Response(200, json=completion([selection(q, status="unverified")])))):
        result = await provider_with([quote()]).discover_daily([q])
    assert result["records"] == [] and result["context_statuses"][0]["status"] == "unverified"


@pytest.mark.asyncio
async def test_two_workers_only_one_actual_groq_post(configured):
    q, evidence, requests = target(), quote(), []
    db, claims, runs = daily_db([q])
    def respond(request):
        requests.append(request)
        assert len(runs) == 1 # Durable reservation precedes dispatch.
        return httpx.Response(200, json=completion([selection(next(iter(runs.values()))["contexts"][0], evidence)]))
    service = MarketDiscoveryService(db, provider_with([evidence]))
    service.repo.store_market_prices_bulk = AsyncMock()
    with patch("httpx.AsyncClient", side_effect=transport_factory(respond)):
        outcomes = await asyncio.gather(service.refresh_daily(), service.refresh_daily())
        third = await service.refresh_daily()
    assert len(requests) == 1 and sum(o["completed"] for o in outcomes) == 1
    assert third["skipped"] == 1
    service.repo.store_market_prices_bulk.assert_awaited_once()
    assert claims.with_options.call_args.kwargs["write_concern"].document["w"] == "majority"


@pytest.mark.asyncio
async def test_mongo_write_failure_keeps_claim_no_second_groq(configured):
    q, evidence = target(), quote()
    db, claims, runs = daily_db([q])
    service = MarketDiscoveryService(db)
    service.provider = MagicMock(matches=matches, discover_daily=AsyncMock(return_value={"records": [normalized_record(evidence, q, datetime.now(timezone.utc))]}))
    service.repo.store_market_prices_bulk = AsyncMock(side_effect=PyMongoError("synthetic write failure"))
    result = await service.refresh_daily()
    assert result["failed"] == 1 and (await service.refresh_daily())["skipped"] == 1
    service.provider.discover_daily.assert_awaited_once()
    claims.update_one.assert_awaited()


@pytest.mark.asyncio
async def test_busy_lease_no_ai(configured):
    db, claims, _ = daily_db([target()])
    claims.find_one_and_update.side_effect = DuplicateKeyError("busy")
    provider = provider_with([quote()])
    service = MarketDiscoveryService(db, provider)
    assert (await service.refresh_daily())["skipped"] == 1
    provider.retriever.retrieve.assert_not_awaited()


@pytest.mark.asyncio
async def test_history_stale_reads_do_not_register_or_dispatch(configured):
    q = target()
    row = normalized_record(quote(), q, datetime.now(timezone.utc) - timedelta(days=2))
    row["arrival_date"] = row["observation_date"] = row["source_record"]["observation_date"] = "2022-02-11"
    db, _, _ = daily_db([])
    service = MarketDiscoveryService(db)
    service.repo.list_market_prices = AsyncMock(return_value=[row])
    with patch("httpx.AsyncClient") as http:
        result = await service.lookup(commodity="Jasmine", refresh=True)
    assert result["records"][0]["stale"] and not result["live"]
    db["market_watchlist"].update_one.assert_not_awaited()
    http.assert_not_called()


def test_api_compatibility_get_read_only_and_admin_authorization(configured):
    from app.main import app
    from app.core.database import get_database
    from app.api.deps import get_current_user
    db, _, _ = daily_db([])
    row = normalized_record(quote(), target(), datetime.now(timezone.utc))
    app.dependency_overrides[get_database] = lambda: db
    app.dependency_overrides[get_current_user] = lambda: {"id": "fixture", "role": "FARMER", "is_active": True}
    try:
        with patch("app.repositories.pricing.PricingRepository.list_market_prices", AsyncMock(return_value=[row])), patch("httpx.AsyncClient") as http:
            client = TestClient(app)
            response = client.get("/api/v1/market-prices", params={"commodity": "Jasmine", "scope": "market"})
            assert response.status_code == 200
            price = response.json()["data"]["records"][0]
            assert price["price_paise"] == 12500 and price["unit"] == "bunch"
            assert client.get("/api/v1/market-prices/latest?commodity=Jasmine&scope=market").status_code == 200
            assert client.post("/api/v1/market-prices/refresh").status_code == 403
            assert client.get("/api/v1/market-prices/status").status_code == 403
            http.assert_not_called()
            db["market_watchlist"].update_one.assert_not_awaited()
    finally:
        app.dependency_overrides.pop(get_database, None)
        app.dependency_overrides.pop(get_current_user, None)


def test_flutter_has_no_groq_key_or_calls_and_selling_price_independent():
    workspace = Path(__file__).parents[2]
    root = workspace if (workspace / "lib").exists() else workspace / "vayalconnect-flutter"
    for file in (root / "lib").rglob("*.dart"):
        text = file.read_text(encoding="utf-8")
        assert "api.groq.com" not in text and "GROQ_API_KEY" not in text and "gsk_" not in text
    screen = (root / "lib/screens/add_product_screen.dart").read_text(encoding="utf-8")
    lookup = screen.split("Future<void> _lookup(", 1)[1].split("Future<void> _save()", 1)[0]
    assert "selling_price" not in lookup


@pytest.mark.asyncio
async def test_reviewed_source_actual_units_and_missing_source_rejected(configured, monkeypatch):
    url = "https://example.org/prices.json"
    monkeypatch.setattr(settings, "GOVERNMENT_MARKET_API_KEY", "")
    monkeypatch.setattr(settings, "MARKET_SOURCE_URLS", json.dumps([url]))
    raw = quote().model_dump(mode="json")
    rows = [raw, {**raw, "unit": "bucket"}, {**raw, "price_paise": -1},
            {**raw, "source_url": "https://unreviewed.example/prices"}]
    with patch("app.integrations.market_evidence.public_source", AsyncMock(return_value=True)), patch("httpx.AsyncClient", side_effect=transport_factory(lambda request: httpx.Response(200, json={"records": rows}))):
        quotes, _ = await MarketEvidenceRetriever().retrieve([target()])
    assert len(quotes) == 1 and quotes[0].unit == "bunch"


@pytest.mark.asyncio
async def test_connection_check_one_non_inference_request(configured, capsys):
    from scripts.check_groq_connection import main
    requests = []
    def respond(request):
        requests.append(request)
        assert request.method == "GET" and request.url.path.endswith("/models")
        return httpx.Response(200, json={"data": [{"id": settings.GROQ_MODEL, "active": True}]})
    with patch("httpx.AsyncClient", side_effect=transport_factory(respond)):
        assert await main() == 0
    assert len(requests) == 1 and "synthetic-secret-not-real" not in capsys.readouterr().out


@pytest.mark.asyncio
@pytest.mark.parametrize("status", [401, 403, 429])
async def test_connection_check_failure_sanitized_and_not_retried(configured, capsys, status):
    from scripts.check_groq_connection import main
    requests = []
    def respond(request):
        requests.append(request)
        assert request.method == "GET" and request.url.path.endswith("/models")
        return httpx.Response(status, json={"error": {"message": "synthetic-secret-not-real private-upstream-detail"}})
    with patch("httpx.AsyncClient", side_effect=transport_factory(respond)):
        assert await main() == 1
    output = capsys.readouterr().out
    assert len(requests) == 1 and f"HTTP {status}" in output and "No retry" in output
    assert "synthetic-secret-not-real" not in output and "private-upstream-detail" not in output


@pytest.mark.asyncio
async def test_catalog_includes_inactive_products_bilingual_aliases_and_onboarding(configured):
    db, _, _ = daily_db([], products=[{"product_name": "மல்லிகை", "product_name_en": "Jasmine",
        "product_name_ta": "மல்லிகை", "category": "New flower category", "status": "INACTIVE"}])
    async def profiles():
        yield {"application": {"crops": "Rose; Novel crop\nMarigold", "farm_address": "Private address"}}
    db["farmer_profiles"].find = lambda *args: profiles()
    queries = await MarketDiscoveryService(db)._load_queries(datetime.now(timezone.utc))
    assert {q["commodity"] for q in queries.values()} == {"மல்லிகை", "Rose", "Novel crop", "Marigold"}
    tamil = next(q for q in queries.values() if q["commodity"] == "மல்லிகை")
    assert tamil["aliases"] == ["Jasmine", "மல்லிகை"]
    assert quote().matches(tamil)
    assert all(q["market"] is None for q in queries.values())


@pytest.mark.asyncio
async def test_repository_filters_pagination_crop_id_category_and_preserves_created_at():
    from app.repositories.pricing import PricingRepository
    db = MagicMock()
    async def empty():
        if False: yield None
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.skip.return_value = cursor
    cursor.limit.return_value = empty()
    db["market_prices"].find.return_value = cursor
    db["market_prices"].update_one = AsyncMock()
    repo = PricingRepository(db)
    await repo.list_market_prices(commodity="மல்லிகை", category="New flower category", commodity_id="crop:test", limit=5, offset=10)
    query = db["market_prices"].find.call_args.args[0]
    assert query["commodity_id"] == "crop:test" and "category" in query
    assert "crop_aliases" in query["$or"][1]
    cursor.skip.assert_called_once_with(10)
    cursor.limit.assert_called_once_with(5)
    row = normalized_record(quote(), target(), datetime.now(timezone.utc))
    await repo.store_market_prices_bulk([row, row])
    calls = db["market_prices"].update_one.call_args_list
    assert calls[0].args[0] == calls[1].args[0]
    assert "created_at" not in calls[0].args[1]["$set"]
    assert "created_at" in calls[0].args[1]["$setOnInsert"]


def test_admin_manual_refresh_uses_daily_workflow(configured):
    from app.main import app
    from app.core.database import get_database
    from app.api.deps import get_current_user
    db, _, _ = daily_db([])
    app.dependency_overrides[get_database] = lambda: db
    app.dependency_overrides[get_current_user] = lambda: {"id": "fixture", "role": "ADMIN", "is_active": True}
    try:
        with patch("app.services.market_discovery.MarketDiscoveryService.refresh_daily", AsyncMock(return_value={"skipped": 1})) as refresh:
            assert TestClient(app).post("/api/v1/market-prices/refresh").status_code == 200
            refresh.assert_awaited_once()
    finally:
        app.dependency_overrides.pop(get_database, None)
        app.dependency_overrides.pop(get_current_user, None)


@pytest.mark.asyncio
async def test_ogd_feed_preserves_explicit_unit_and_validates_currency_price_dates(configured, monkeypatch):
    monkeypatch.setattr(settings, "GOVERNMENT_MARKET_API_KEY", "synthetic-ogd-key")
    monkeypatch.setattr(settings, "GOVERNMENT_MARKET_UNIT", "quintal")
    monkeypatch.setattr(settings, "MARKET_SOURCE_URLS", "[]")
    row = {"commodity": "Jasmine", "market": "Madurai", "district": "Madurai", "state": "Tamil Nadu",
           "arrival_date": datetime.now(IST).strftime("%d/%m/%Y"), "min_price": "100", "modal_price": "125", "max_price": "150", "unit": "bunch"}
    calls = []
    def respond(request):
        calls.append(request)
        assert request.url.host == "api.data.gov.in"
        return httpx.Response(200, json={"status": "ok", "total": 2,
            "records": [row, {**row, "modal_price": "-10"}]})
    with patch("httpx.AsyncClient", side_effect=transport_factory(respond)):
        quotes, diagnostics = await MarketEvidenceRetriever().retrieve([target()])
    assert len(calls) == 1 and len(quotes) == 1
    assert quotes[0].unit == "bunch" and quotes[0].price_paise == 12500
    assert quotes[0].original_price_value == "125" and quotes[0].original_unit == "bunch"
    assert quotes[0].source_url.endswith("9ef84268-d588-465a-a308-a864a43d0070")


@pytest.mark.asyncio
async def test_ogd_missing_unit_contract_never_guesses_flower_unit(configured, monkeypatch):
    monkeypatch.setattr(settings, "GOVERNMENT_MARKET_API_KEY", "synthetic-ogd-key")
    monkeypatch.setattr(settings, "GOVERNMENT_MARKET_UNIT", "quintal")
    monkeypatch.setattr(settings, "MARKET_SOURCE_URLS", "[]")
    row = {"commodity": "Jasmine", "market": "Madurai", "district": "Madurai", "state": "Tamil Nadu",
           "arrival_date": datetime.now(IST).strftime("%d/%m/%Y"), "modal_price": "125"}
    with patch("app.integrations.market_evidence.read_json", AsyncMock(return_value={
            "status": "ok", "total": 1, "records": [row]})) as read:
        quotes, diagnostics = await MarketEvidenceRetriever().retrieve([target()])
    assert not quotes and "OGD_ROW_UNIT_MISSING" in diagnostics
    read.assert_awaited_once()


@pytest.mark.asyncio
async def test_expired_lease_after_catalog_load_cannot_dispatch(configured):
    db, claims, _ = daily_db([target()])
    claims.find_one_and_update.side_effect = [{"_id": "refresh-lock"}, None]
    provider = provider_with([quote()])
    result = await MarketDiscoveryService(db, provider).refresh_daily()
    assert result["skipped"] == 1 and "expired" in result["message"]
    provider.retriever.retrieve.assert_not_awaited()


def test_yesterday_never_labelled_today_even_with_relaxed_retrieval_policy(monkeypatch):
    monkeypatch.setattr(settings, "MARKET_CURRENT_MAX_DAYS", 2)
    raw = quote().model_dump(mode="json")
    raw["observation_date"] = (datetime.now(IST).date() - timedelta(days=1)).isoformat()
    prior = SourceQuote.model_validate_json(json.dumps(raw))
    row = normalized_record(prior, target(), datetime.now(timezone.utc))
    assert row["stale"] and not MarketDiscoveryService._current(row, datetime.now(timezone.utc))
    from app.api.v1.products import reference_view
    assert reference_view({"pricing_mode": "FARMER_SELECTED", "reference_price_date": raw["observation_date"]})["reference_price_stale"]
