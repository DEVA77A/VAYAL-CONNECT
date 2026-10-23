"""Synthetic/mocked responses only. These fixtures are not live market prices."""
import json
import re
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from fastapi.testclient import TestClient
from pymongo.errors import DuplicateKeyError

from app.integrations.pypricing_market import (
    ENDPOINT, SOURCE, PyPricingMarketProvider, canonical_commodity, matches,
    parse_documented_output,
)
from app.services.market_discovery import MarketDiscoveryService
from app.services.pricing_service import PricingEngine
from tests.market_fixtures import daily_db


def query(crop="Tomato", **changes):
    return dict(commodity=crop, market="Madurai", state="Tamil Nadu", **changes)


def feed(amount="123.45", crop="TOMATO", market="MADURAI", observed=None):
    return {"data": {"value": f"Latest reported prices:\n- {crop} : {amount} RS/Qui, {market}, {observed or datetime.now(timezone.utc).date().isoformat()}\n"}}


def record(**changes):
    return {**parse_documented_output(feed(), [query()])[0], **changes}


def test_documented_format_preserves_unknowns_original_unit_and_crop():
    result = parse_documented_output(feed(), [query(" tomato ")])[0]
    assert result["commodity"] == "TOMATO" and result["crop_name"] == " tomato "
    assert result["price_paise"] == 12345 and result["currency"] == "INR"
    assert result["unit"] == "Qui" and result["price_type"] == "unknown"
    assert result["district"] is None and result["variety"] is None
    assert "modal_price_paise" not in result and "price_per_kg_paise" not in result
    assert result["source"] == SOURCE and result["source_url"] == ENDPOINT
    assert matches(result, "Tomato", "Madurai", "Tamil Nadu")


def test_zero_is_distinct_from_missing_price():
    result = parse_documented_output(feed("0"), [query()])[0]
    assert result["price_paise"] == 0 and matches(result)


@pytest.mark.parametrize("payload", [{}, [], {"data": []}, {"data": {"value": []}},
    {"data": {"value": None}}, "", {"records": []}])
def test_unsupported_schema_is_rejected(payload):
    with pytest.raises(ValueError):
        parse_documented_output(payload, [query()])


def test_empty_documented_feed_is_unavailable():
    assert parse_documented_output("Latest reported prices:\n", [query()]) == []


@pytest.mark.parametrize("amount", ["-1", "NaN", "Infinity", "1e10", "1.001", "", "10000000001"])
def test_invalid_price_is_rejected(amount):
    with pytest.raises(ValueError):
        parse_documented_output(feed(amount), [query()])


@pytest.mark.parametrize("observed", ["missing", "2026-02-30", "2999-01-01"])
def test_missing_invalid_or_future_date_rejected(observed):
    with pytest.raises(ValueError):
        parse_documented_output(feed(observed=observed), [query()])


def test_unknown_unit_and_currency_rejected():
    for wrong in ["RS/bucket", "USD/Qui"]:
        with pytest.raises(ValueError):
            parse_documented_output(feed()["data"]["value"].replace("RS/Qui", wrong), [query()])


def test_historical_observation_keeps_actual_date_and_is_stale():
    old = "2022-02-11"
    result = parse_documented_output(feed(observed=old), [query()])[0]
    assert result["arrival_date"] == old and result["stale"]
    assert matches(result)


@pytest.mark.parametrize("changes", [{"commodity": "Rice"}, {"commodity": "Jasmine"},
    {"variety": "Hybrid"}, {"market": "Coimbatore"}, {"state": "Karnataka"}, {"district": "Madurai"}])
def test_unsupported_crop_variety_or_location_never_substituted(changes):
    target = query()
    target.update(changes)
    assert parse_documented_output(feed(), [target]) == []


@pytest.mark.parametrize("name", ["Jasmine", "Rose", "Marigold", "Chrysanthemum", "Tuberose", "Novel seedling"])
def test_new_crops_and_flowers_require_actual_matching_quote(name):
    assert parse_documented_output(feed(), [query(name)]) == []
    rows = parse_documented_output(feed(crop=name.upper()), [query(name)])
    assert len(rows) == 1  # Mocked coverage only; not evidence of live support.


def test_safe_aliases_whitespace_and_no_fuzzy_or_rice_paddy_matching():
    assert canonical_commodity(" Ground   Nut ") == "groundnut"
    assert parse_documented_output(feed(crop="GROUND NUT"), [query("Groundnut")])
    assert parse_documented_output(feed(crop="URAD (BLACK GRAM)"), [query("Black Gram")])
    assert not parse_documented_output(feed(crop="PADDY"), [query("Rice")])
    assert not parse_documented_output(feed(crop="TOMATO"), [query("Tomatillo")])


@pytest.mark.asyncio
async def test_disabled_provider_makes_no_http_or_gemini_call(monkeypatch):
    monkeypatch.setattr("app.integrations.pypricing_market.settings.PYPRICING_ENABLED", False)
    with patch("httpx.AsyncClient") as http, patch("google.genai.Client") as ai:
        result = await PyPricingMarketProvider().discover_daily([query()])
    http.assert_not_called()
    ai.assert_not_called()
    assert result["error_code"] == "PROVIDER_NOT_VERIFIED" and not result["records"]


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["valid", "empty", "invalid_json", "schema", "timeout", "connection", "429", "502", "302", "oversized"])
async def test_http_is_bounded_shared_no_retry_and_no_ai(monkeypatch, kind):
    monkeypatch.setattr("app.integrations.pypricing_market.settings.PYPRICING_ENABLED", True)
    requests = []
    def respond(request):
        requests.append(request)
        assert str(request.url).startswith(ENDPOINT)
        assert request.method == "GET"
        assert request.url.params["place"] == "Coimbatore,Madurai"
        assert request.url.params["output"] == "String"
        assert "commodities" not in request.url.params
        if kind == "timeout":
            raise httpx.ReadTimeout("synthetic timeout", request=request)
        if kind == "connection":
            raise httpx.ConnectError("synthetic connection failure", request=request)
        if kind.isdigit():
            return httpx.Response(int(kind), json={"message": "Synthetic HTTP failure"})
        if kind == "invalid_json":
            return httpx.Response(200, content=b"{bad")
        if kind == "oversized":
            return httpx.Response(200, content=b"x" * 1_000_001)
        payload = feed() if kind == "valid" else {"data": {"value": "Latest reported prices:\n"}} if kind == "empty" else {}
        return httpx.Response(200, json=payload)
    real_client = httpx.AsyncClient
    def mock_client(**kwargs):
        assert kwargs["timeout"].connect == 5 and kwargs["timeout"].read == 15
        assert kwargs["follow_redirects"] is False
        kwargs["transport"] = httpx.MockTransport(respond)
        return real_client(**kwargs)
    with patch("httpx.AsyncClient", side_effect=mock_client), patch("google.genai.Client") as ai:
        result = await PyPricingMarketProvider().discover_daily([query(), query("Onion"),
            dict(commodity="Jasmine", market="Coimbatore", state="Tamil Nadu")])
    assert len(requests) == 1
    ai.assert_not_called()
    assert bool(result["records"]) == (kind == "valid")
    if kind not in {"valid", "empty"}:
        assert result["error_code"]


@pytest.mark.asyncio
async def test_default_daily_failure_keeps_old_verified_cache_and_duplicate_guard(monkeypatch):
    monkeypatch.setattr("app.integrations.pypricing_market.settings.PYPRICING_ENABLED", False)
    db, claims, runs = daily_db([query(), query("Jasmine"), query("Novel crop")])
    service = MarketDiscoveryService(db)
    old = record(arrival_date="2022-02-11", observation_date="2022-02-11", retrieved_at=datetime.now(timezone.utc) - timedelta(days=90))
    service.repo.store_market_prices_bulk = AsyncMock()
    service.repo.list_market_prices = AsyncMock(return_value=[old])
    with patch("google.genai.Client") as ai:
        first = await service.refresh_daily()
        second = await service.refresh_daily()
        lookup = await service.lookup(commodity="Tomato", market="Madurai", refresh=True)
    assert first["failed"] == 1 and second["skipped"] == 1
    assert len(runs) == 1 and first["contexts"] == 7
    service.repo.store_market_prices_bulk.assert_not_awaited()
    assert lookup["records"] == [] # Legacy third-party history is not source-verified.
    ai.assert_not_called()


@pytest.mark.asyncio
async def test_valid_refresh_uses_existing_cache_upsert_and_releases_lease():
    db, claims, runs = daily_db([query()])
    provider = PyPricingMarketProvider()
    provider.discover_daily = AsyncMock(return_value={"records": [record()], "message": "Synthetic fixture"})
    service = MarketDiscoveryService(db, provider=provider)
    service.repo.store_market_prices_bulk = AsyncMock()
    assert (await service.refresh_daily())["completed"] == 1
    service.repo.store_market_prices_bulk.assert_awaited_once()
    assert claims.find_one_and_update.call_args_list[0].kwargs["upsert"] is True
    assert not claims.find_one_and_update.call_args.kwargs.get("upsert", False)
    assert "owner" in claims.find_one_and_update.call_args.args[0]
    assert claims.update_one.call_args.args[0] == {"_id": "refresh-lock", "owner": next(iter(runs))}


@pytest.mark.asyncio
async def test_overlap_lease_blocks_even_a_different_day_claim():
    db, claims, runs = daily_db([query()])
    claims.find_one_and_update.side_effect = DuplicateKeyError("already active")
    provider = PyPricingMarketProvider()
    provider.discover_daily = AsyncMock()
    assert (await MarketDiscoveryService(db, provider=provider).refresh_daily())["skipped"] == 1
    provider.discover_daily.assert_not_awaited()


@pytest.mark.asyncio
async def test_oversized_context_batch_fails_explicitly_without_dispatch():
    db, claims, runs = daily_db([query(f"Crop {index}") for index in range(10001)])
    provider = PyPricingMarketProvider()
    provider.discover_daily = AsyncMock()
    result = await MarketDiscoveryService(db, provider=provider).refresh_daily()
    assert result["failed"] == 1 and "10000" in result["message"]
    provider.discover_daily.assert_not_awaited()
    assert len(runs) == 1 # Claim is consumed before batch loading, even on limits.


@pytest.mark.asyncio
async def test_oversized_location_batch_makes_no_http_request(monkeypatch):
    monkeypatch.setattr("app.integrations.pypricing_market.settings.PYPRICING_ENABLED", True)
    targets = [dict(commodity="Tomato", market=f"Place {index}") for index in range(21)]
    with patch("httpx.AsyncClient") as http:
        result = await PyPricingMarketProvider().discover_daily(targets)
    assert result["error_code"] == "INVALID_LOCATIONS"
    http.assert_not_called()


@pytest.mark.asyncio
async def test_reference_does_not_convert_unverified_qui_to_kg_or_change_selling_price():
    engine = PricingEngine(MagicMock())
    result = dict(records=[record(stale=False)], live=False, message="Synthetic fixture", source=SOURCE)
    with patch.object(MarketDiscoveryService, "lookup", AsyncMock(return_value=result)):
        reference = await engine.get_verified_reference("Tomato", "Madurai", "KG")
        assert reference["reference_price_available"] is False
        engine.selling_amounts = AsyncMock(return_value={"buyer_price_per_unit_paise": 1000, "commission_per_unit_paise": 100})
        snapshot = await engine.calculate_pricing("Tomato", "Vegetables", 2, "KG", "A", "Madurai", "Madurai", "farmer", selling_price_per_unit_paise=900)
    engine.selling_amounts.assert_awaited_once_with(900)
    assert snapshot["farmer_total_payout_paise"] == 1800
    assert snapshot["buyer_total_paise"] == 2000 and snapshot["pricing_mode"] == "FARMER_SELECTED"


@pytest.mark.parametrize("role,expected", [(None, 401), ("FARMER", 403), ("BUYER", 403), ("ADMIN", 200)])
def test_administrative_status_is_protected_and_read_only(role, expected):
    from app.main import app
    from app.api.deps import get_current_user
    from app.core.database import get_database
    db = MagicMock()
    db["market_daily_runs"].find_one = AsyncMock(return_value=None)
    app.dependency_overrides[get_database] = lambda: db
    if role:
        app.dependency_overrides[get_current_user] = lambda: {"id": "synthetic", "role": role}
    try:
        with patch.object(PyPricingMarketProvider, "discover_daily", AsyncMock()) as provider, patch("google.genai.Client") as ai:
            response = TestClient(app).get("/api/v1/market-prices/status")
        assert response.status_code == expected
        provider.assert_not_awaited()
        ai.assert_not_called()
        if role == "ADMIN":
            assert response.json()["data"]["last_successful_at"] is None
    finally:
        app.dependency_overrides.pop(get_database, None)
        app.dependency_overrides.pop(get_current_user, None)


def test_public_api_hides_unverified_provider_history_without_http():
    from app.main import app
    from app.core.database import get_database
    db, _, _ = daily_db([])
    app.dependency_overrides[get_database] = lambda: db
    try:
        with patch("app.repositories.pricing.PricingRepository.list_market_prices", AsyncMock(return_value=[record()])), patch("httpx.AsyncClient") as http, patch("google.genai.Client") as ai:
            response = TestClient(app).get("/api/v1/market-prices", params={"commodity": "Tomato", "market": "Madurai"})
        assert response.status_code == 200
        assert response.json()["data"]["records"] == []
        http.assert_not_called()
        ai.assert_not_called()
    finally:
        app.dependency_overrides.pop(get_database, None)


@pytest.mark.asyncio
async def test_repository_alias_filter_and_stable_record_upsert():
    from app.repositories.pricing import PricingRepository
    db = MagicMock()
    async def empty():
        if False:
            yield None
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.skip.return_value = cursor
    cursor.limit.return_value = empty()
    db["market_prices"].find.return_value = cursor
    db["market_prices"].update_one = AsyncMock()
    repo = PricingRepository(db)
    await repo.list_market_prices(commodity=" Ground   nut ")
    pattern = db["market_prices"].find.call_args.args[0]["$or"][0]["commodity"]["$regex"]
    assert re.match(pattern, "GROUND NUT", re.I) and re.match(pattern, "groundnut", re.I)
    assert not re.match(pattern, "groundnut oil", re.I)
    await repo.store_market_prices_bulk([record(), record(price_paise=999, commodity=" tomato ", market="madurai")])
    calls = db["market_prices"].update_one.call_args_list
    assert calls[0].args[0] == calls[1].args[0]  # Same observed identity, not duplicate documents.


def test_cron_uses_ist_time_and_external_refresh_stays_disabled():
    from pathlib import Path
    config = (Path(__file__).parents[1] / "render.yaml").read_text(encoding="utf-8")
    if "  - type: cron" not in config:
        instructions = (Path(__file__).parents[1] / "docs/STATEWIDE_MARKET_PRICES.md").read_text(encoding="utf-8")
        assert "30 2 * * *" in instructions and "python -m scripts.refresh_market_prices" in instructions
        from app.core.config import Settings
        assert Settings.model_fields["PYPRICING_ENABLED"].default is False
        assert Settings.model_fields["MARKET_DAILY_REFRESH_ENABLED"].default is False
        return
    cron = config.split("  - type: cron")[1]
    assert 'schedule: "30 2 * * *"' in cron
    assert 'dockerCommand: python -m scripts.refresh_market_prices' in cron
    assert 'key: PYPRICING_ENABLED\n        value: "false"' in cron


@pytest.mark.asyncio
async def test_disabled_cron_command_never_connects_database_or_google(monkeypatch):
    from scripts.refresh_market_prices import main
    monkeypatch.setattr("app.core.config.settings.PYPRICING_ENABLED", False)
    with patch("scripts.refresh_market_prices.connect_db", AsyncMock()) as connect, patch("google.genai.Client") as ai:
        await main()
    connect.assert_not_awaited()
    ai.assert_not_called()
