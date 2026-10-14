"""Market repair regressions; synthetic evidence and isolated loopback DB only."""

from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient
from pymongo.errors import ServerSelectionTimeoutError

from app.core.database import get_database
from app.main import app
from app.services.market_discovery import MarketDiscoveryService
from app.services.pricing_service import PricingEngine
from app.repositories.pricing import PricingRepository
from app.integrations.statewide_market import aggregate
from tests.test_tn_market import quotes


def test_cache_outage_has_specific_503_and_empty_search_is_200():
    db = MagicMock()
    app.dependency_overrides[get_database] = lambda: db
    try:
        with patch.object(
            PricingRepository,
            "list_market_prices",
            AsyncMock(side_effect=ServerSelectionTimeoutError("private")),
        ):
            r = TestClient(app).get("/api/v1/market-prices?commodity=Tomato")
        assert r.status_code == 503
        assert r.json()["error"]["code"] == "MARKET_CACHE_UNAVAILABLE"
        assert "private" not in r.text
        with patch.object(
            PricingRepository, "list_market_prices", AsyncMock(return_value=[])
        ):
            r = TestClient(app).get("/api/v1/market-prices?commodity=Unsupported")
        assert r.status_code == 200 and r.json()["data"]["records"] == []
    finally:
        app.dependency_overrides.pop(get_database, None)


@pytest.mark.asyncio
async def test_refresh_has_verified_targets_without_products_or_watchlist():
    db = MagicMock()

    async def empty():
        if False:
            yield {}

    db.__getitem__.return_value.find.side_effect = lambda *args: empty()
    queries = await MarketDiscoveryService(db)._load_queries(datetime.now(timezone.utc))
    assert {q["commodity"] for q in queries.values()} == {
        "Tomato",
        "Banana (fruit)",
        "Jasmine",
        "Marigold",
    }


@pytest.mark.asyncio
async def test_reference_ignores_farmer_category_and_returns_converted_verified_price():
    rows = aggregate(quotes(), [{"commodity": "Tomato"}], datetime.now(timezone.utc))
    rows[0]["stale"] = False
    lookup = AsyncMock(
        return_value={
            "records": rows,
            "live": False,
            "source": "test",
            "message": "test",
        }
    )
    with patch.object(MarketDiscoveryService, "lookup", lookup):
        result = await PricingEngine(MagicMock()).get_verified_reference(
            "Tomato", "", "QUINTAL", category="Grains"
        )
    assert lookup.call_args.kwargs.get("category") is None
    assert result["reference_verification_status"] == "verified"
    assert result["reference_price_per_listing_unit_paise"] == 300000


@pytest.mark.asyncio
async def test_invalid_batch_cannot_overwrite_valid_cache():
    db = MagicMock()
    db.__getitem__.return_value.update_one = AsyncMock()
    row = aggregate(quotes(), [{"commodity": "Tomato"}], datetime.now(timezone.utc))[0]
    with pytest.raises(ValueError, match="cache preserved"):
        await PricingRepository(db).store_market_prices_bulk(
            [row, {**row, "price_paise": 999}]
        )
    db.__getitem__.return_value.update_one.assert_not_awaited()


def test_tomato_api_returns_observation_provenance():
    from app.integrations.groq_market import normalized_record

    row = normalized_record(
        quotes()[0], {"commodity": "Tomato"}, datetime.now(timezone.utc)
    )
    app.dependency_overrides[get_database] = lambda: MagicMock()
    try:
        with patch.object(
            PricingRepository, "list_market_prices", AsyncMock(return_value=[row])
        ):
            r = TestClient(app).get(
                "/api/v1/market-prices?commodity=Tomato&scope=market"
            )
        assert r.status_code == 200
        item = r.json()["data"]["records"][0]
        assert item["commodity"] == "Tomato" and item["unit"] == "kg"
        assert item["arrival_date"] and item["market"] and item["source_url"]
        assert item["verification_status"] == "verified"
    finally:
        app.dependency_overrides.pop(get_database, None)
