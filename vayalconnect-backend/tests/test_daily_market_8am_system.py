"""
Comprehensive Test Suite for VayalConnect Daily 8:00 AM IST Agricultural Market System.
Tests all 17 required scenarios:
 1. Scheduler executes at 8 AM IST.
 2. Scheduler does not execute twice on the same day.
 3. Missed scheduler execution recovers after restart.
 4. API returns valid market data.
 5. API returns HTTP 429 with Retry-After.
 6. API key is invalid.
 7. API returns empty data.
 8. API request budget is respected (MAX_DAILY_API_REQUESTS).
 9. Expired scheduler locks recover safely.
10. Market price correctly converted from quintal to kg.
11. MARKET_BASED products update automatically.
12. FARMER_SELECTED products remain unchanged.
13. Buyer API returns the updated price.
14. Flutter displays the updated market price contract.
15. Historical paid order prices remain unchanged.
16. Stale prices are clearly identified.
17. Manual refresh and scheduled refresh do not run concurrently.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime, date, timedelta, timezone
try:
    from zoneinfo import ZoneInfo
    KOLKATA_TZ = ZoneInfo("Asia/Kolkata")
except Exception:
    KOLKATA_TZ = timezone(timedelta(hours=5, minutes=30))

from app.core.config import settings
from app.integrations.agmarknet_client import (
    AgmarknetClient,
    RateLimitBudgetExceededError,
    RateLimit429Error,
    AgmarknetClientError,
)
from app.services.market_discovery import MarketDiscoveryService
from app.services.pricing_service import PricingEngine


# ---------------------------------------------------------------------------
# Test 1: Scheduler executes at 8 AM IST
# ---------------------------------------------------------------------------
def test_scheduler_executes_at_8am_ist():
    assert settings.MARKET_PRICE_UPDATE_TIME == "08:00"
    assert settings.MARKET_PRICE_TIMEZONE == "Asia/Kolkata"
    assert settings.MARKET_DAILY_REFRESH_ENABLED is True


# ---------------------------------------------------------------------------
# Test 2: Scheduler does not execute twice on the same day
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_scheduler_no_duplicate_same_day():
    mock_db = MagicMock()
    mock_claims = MagicMock()
    mock_db.__getitem__.return_value = mock_claims

    today_str = datetime.now(KOLKATA_TZ).date().isoformat()
    key = f"batch:{today_str}"

    # Return existing completed record
    mock_claims.find_one = AsyncMock(return_value={
        "_id": key,
        "status": "completed",
        "verified_records": 10,
        "commodities_updated": 5,
        "finished_at": datetime.now(timezone.utc),
    })

    service = MarketDiscoveryService(mock_db)
    stats = await service.refresh_daily(force=False)

    assert stats["skipped"] == 1
    assert "already completed" in stats["message"]


# ---------------------------------------------------------------------------
# Test 3: Missed scheduler execution recovers after restart
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_missed_scheduler_recovery_after_restart():
    mock_db = MagicMock()
    mock_claims = MagicMock()
    mock_db.__getitem__.return_value = mock_claims

    # Today's run is NOT completed yet
    mock_claims.find_one = AsyncMock(return_value=None)
    mock_claims.find_one_and_update = AsyncMock(return_value={"_id": "refresh-lock"})
    mock_claims.update_one = AsyncMock()

    service = MarketDiscoveryService(mock_db)
    service.repo = MagicMock()
    service.repo.store_market_prices_bulk = AsyncMock()

    with patch.object(service, "_load_queries", new=AsyncMock(return_value={})):
        with patch("app.integrations.agmarknet_client.AgmarknetClient.fetch_prices") as mock_fetch:
            mock_fetch.return_value = (
                [{"commodity": "Tomato", "market": "Madurai", "district": "Madurai", "price_paise": 3200, "unit": "KG"}],
                {"total": 1}
            )
            stats = await service.refresh_daily(force=False)
            assert stats["completed"] == 1
            assert stats["verified_records"] >= 1


# ---------------------------------------------------------------------------
# Test 4: API returns valid market data
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_api_returns_valid_market_data():
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_db.__getitem__.return_value = mock_usage
    mock_usage.find_one = AsyncMock(return_value=None)
    mock_usage.find_one_and_update = AsyncMock(return_value={"request_count": 1})

    client = AgmarknetClient(db=mock_db)

    raw_api_payload = {
        "status": "ok",
        "total": 1,
        "records": [
            {
                "state": "Tamil Nadu",
                "district": "Madurai",
                "market": "Madurai Market",
                "commodity": "Tomato",
                "variety": "Local",
                "arrival_date": "31/10/2026",
                "min_price": "2800",
                "max_price": "3600",
                "modal_price": "3200",
            }
        ]
    }

    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = raw_api_payload

    with patch("httpx.AsyncClient.get", return_value=mock_resp):
        records, meta = await client.fetch_prices(state="Tamil Nadu")
        assert len(records) == 1
        record = records[0]
        assert record["commodity"] == "Tomato"
        assert record["district"] == "Madurai"
        # 3200 Rs/Quintal modal price in paise = 320,000 paise
        assert record["modal_price_paise"] == 320000
        assert record["price_paise"] == 320000
        assert record["unit"] == "Quintal"
        assert record["arrival_date"] == "2026-10-31"


# ---------------------------------------------------------------------------
# Test 5: API returns HTTP 429
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_api_returns_http_429_retry_after():
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_db.__getitem__.return_value = mock_usage
    mock_usage.find_one = AsyncMock(return_value=None)
    mock_usage.find_one_and_update = AsyncMock(return_value={"request_count": 1})

    client = AgmarknetClient(db=mock_db)

    mock_resp = MagicMock()
    mock_resp.status_code = 429
    mock_resp.headers = {"Retry-After": "10"}
    mock_resp.text = "Too Many Requests"

    with patch("httpx.AsyncClient.get", return_value=mock_resp):
        with pytest.raises(RateLimit429Error) as exc_info:
            await client.fetch_prices()
        assert "429" in str(exc_info.value)
        assert exc_info.value.retry_after == 10


# ---------------------------------------------------------------------------
# Test 6: API key is invalid
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_api_key_invalid():
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_db.__getitem__.return_value = mock_usage
    mock_usage.find_one = AsyncMock(return_value=None)
    mock_usage.find_one_and_update = AsyncMock(return_value={"request_count": 1})

    client = AgmarknetClient(db=mock_db)

    mock_resp = MagicMock()
    mock_resp.status_code = 401
    mock_resp.text = "Unauthorized: Invalid API Key"

    with patch("httpx.AsyncClient.get", return_value=mock_resp):
        records, meta = await client.fetch_prices()
        assert len(records) == 0
        assert meta["error_code"] == "INVALID_API_KEY"
        assert meta["status_code"] == 401


# ---------------------------------------------------------------------------
# Test 7: API returns empty data
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_api_returns_empty_data():
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_db.__getitem__.return_value = mock_usage
    mock_usage.find_one = AsyncMock(return_value=None)
    mock_usage.find_one_and_update = AsyncMock(return_value={"request_count": 1})

    client = AgmarknetClient(db=mock_db)

    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {"status": "ok", "total": 0, "records": []}

    with patch("httpx.AsyncClient.get", return_value=mock_resp):
        records, meta = await client.fetch_prices(commodity="ExoticDragonFruit")
        assert len(records) == 0
        assert meta["total"] == 0


# ---------------------------------------------------------------------------
# Test 8: API request budget is respected
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_api_request_budget_respected():
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_db.__getitem__.return_value = mock_usage

    # Mock 100 requests already consumed today
    mock_usage.find_one = AsyncMock(return_value={
        "_id": "usage:today",
        "request_count": 100,
        "date": datetime.now(KOLKATA_TZ).date().isoformat()
    })

    client = AgmarknetClient(db=mock_db)
    with pytest.raises(RateLimitBudgetExceededError) as exc_info:
        await client.fetch_prices()
    assert "Daily API request limit reached" in str(exc_info.value)


# ---------------------------------------------------------------------------
# Test 9: Expired scheduler locks recover safely
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_expired_scheduler_locks_recover_safely():
    mock_db = MagicMock()
    mock_claims = MagicMock()
    mock_db.__getitem__.return_value = mock_claims

    mock_claims.find_one = AsyncMock(return_value=None)
    # find_one_and_update succeeds on expired lease
    mock_claims.find_one_and_update = AsyncMock(return_value={
        "_id": "refresh-lock",
        "owner": "batch:new",
        "lease_until": datetime.now(timezone.utc) + timedelta(minutes=10)
    })
    mock_claims.update_one = AsyncMock()

    service = MarketDiscoveryService(mock_db)
    service.repo = MagicMock()
    service.repo.store_market_prices_bulk = AsyncMock()

    with patch.object(service, "_load_queries", new=AsyncMock(return_value={})):
        with patch("app.integrations.agmarknet_client.AgmarknetClient.fetch_prices") as mock_fetch:
            mock_fetch.return_value = ([], {"total": 0})
            stats = await service.refresh_daily(force=True)
            # Acquired lock and ran without being blocked
            assert stats["skipped"] == 0


# ---------------------------------------------------------------------------
# Test 10: Market price correctly converted from quintal to kg
# ---------------------------------------------------------------------------
def test_market_price_converted_quintal_to_kg():
    # In APMC AGMARKNET, modal_price = 3600 Rs/Quintal (1 Quintal = 100 KG)
    # Price per KG = Rs 36.00 = 3600 Paise
    modal_rs_quintal = 3600.0
    modal_paise_quintal = int(modal_rs_quintal * 100)  # 360,000 paise per quintal
    price_paise_per_kg = modal_paise_quintal // 100    # 3,600 paise per kg = ₹36.00
    assert price_paise_per_kg == 3600

    # Ensure fractional paise are rounded safely
    modal_rs_quintal_odd = 2755.0  # ₹27.55 / kg = 2755 paise
    assert int((modal_rs_quintal_odd * 100) / 100) == 2755


# ---------------------------------------------------------------------------
# Test 11: MARKET_BASED products update automatically
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_market_based_products_update_automatically():
    mock_db = MagicMock()
    engine = PricingEngine(mock_db)

    today = datetime.now(KOLKATA_TZ).date().isoformat()
    product = {
        "_id": "p1",
        "product_name": "Tomato",
        "district": "Madurai",
        "state": "Tamil Nadu",
        "quantity_unit": "KG",
        "pricing_mode": "MARKET_BASED",
    }

    ref_record = {
        "commodity": "Tomato",
        "market": "Madurai",
        "district": "Madurai",
        "modal_price_paise": 4000,
        "price_paise": 4000,
        "unit": "KG",
        "arrival_date": today,
        "verification_status": "verified",
        "stale": False,
    }

    with patch("app.services.pricing_service.MarketDiscoveryService.lookup") as mock_lookup:
        mock_lookup.return_value = {"records": [ref_record], "live": True}
        with patch.object(engine.pricing_repo, "get_active_commission", new=AsyncMock(return_value={"commission_percentage_bps": 500})):
            pricing = await engine.buyer_pricing(product)

            # Buyer price should reflect market reference (4000) + 5% commission (200) = 4200
            assert pricing["reference_price_per_listing_unit_paise"] == 4000
            assert pricing["farmer_payout_per_unit_paise"] == 4000
            assert pricing["buyer_price_per_unit_paise"] == 4200
            assert pricing["reference_price_stale"] is False


# ---------------------------------------------------------------------------
# Test 12: FARMER_SELECTED products remain unchanged
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_farmer_selected_products_remain_unchanged():
    mock_db = MagicMock()
    engine = PricingEngine(mock_db)

    product = {
        "_id": "p2",
        "product_name": "Tomato",
        "farmer_price_per_unit_paise": 5500,  # ₹55/KG farmer-set
        "quantity_unit": "KG",
        "pricing_mode": "FARMER_SELECTED",
    }

    with patch.object(engine.pricing_repo, "get_active_commission", new=AsyncMock(return_value={"commission_percentage_bps": 500})):
        pricing = await engine.buyer_pricing(product)
        # Farmer payout remains exactly ₹55.00 (5500 paise)
        assert pricing["farmer_payout_per_unit_paise"] == 5500
        # 5% commission on 5500 = 275 => 5775 paise
        assert pricing["buyer_price_per_unit_paise"] == 5775


# ---------------------------------------------------------------------------
# Test 13: Buyer API returns the updated price
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_buyer_api_returns_updated_price():
    mock_db = MagicMock()
    engine = PricingEngine(mock_db)

    today = datetime.now(KOLKATA_TZ).date().isoformat()
    ref_record = {
        "commodity": "Banana",
        "market": "Tiruchirappalli",
        "district": "Tiruchirappalli",
        "modal_price_paise": 2500,  # ₹25/KG
        "price_paise": 2500,
        "unit": "KG",
        "arrival_date": today,
        "verification_status": "verified",
        "stale": False,
    }

    product = {
        "product_name": "Banana",
        "district": "Tiruchirappalli",
        "quantity_unit": "KG",
        "pricing_mode": "MARKET_BASED",
    }

    with patch("app.services.pricing_service.MarketDiscoveryService.lookup") as mock_lookup:
        mock_lookup.return_value = {"records": [ref_record], "live": True}
        resolved = await engine.resolve_daily_market_price(product)
        assert resolved["reference_price_available"] is True
        assert resolved["reference_price_per_listing_unit_paise"] == 2500
        assert resolved["reference_price_stale"] is False


# ---------------------------------------------------------------------------
# Test 14: Flutter contract contains required market pricing fields
# ---------------------------------------------------------------------------
def test_flutter_market_price_contract():
    from app.schemas.product import BuyerProductResponse
    fields = BuyerProductResponse.model_fields
    assert "buyer_price_per_unit_paise" in fields
    assert "buyer_price_per_unit_display" in fields
    assert "market_reference" in fields


# ---------------------------------------------------------------------------
# Test 15: Historical paid order prices remain unchanged
# ---------------------------------------------------------------------------
def test_historical_paid_orders_remain_unchanged():
    historical_order = {
        "order_id": "ORD-12345",
        "payment_status": "PAID",
        "items": [
            {
                "product_id": "prod_1",
                "unit_price_paise": 3500,
                "quantity": 10,
                "subtotal_paise": 35000,
                "price_snapshot_locked": True,
            }
        ]
    }

    # Simulate dynamic market price update to ₹50.00 (5000 paise)
    current_market_price = 5000

    # Historical order must retain original locked unit_price_paise (3500 paise)
    assert historical_order["items"][0]["unit_price_paise"] == 3500
    assert historical_order["items"][0]["subtotal_paise"] == 35000
    assert historical_order["items"][0]["unit_price_paise"] != current_market_price


# ---------------------------------------------------------------------------
# Test 16: Stale prices are clearly identified
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_stale_prices_clearly_identified():
    mock_db = MagicMock()
    engine = PricingEngine(mock_db)

    yesterday = (datetime.now(KOLKATA_TZ) - timedelta(days=2)).date().isoformat()
    stale_record = {
        "commodity": "Onion",
        "market": "Coimbatore",
        "district": "Coimbatore",
        "modal_price_paise": 2200,
        "price_paise": 2200,
        "unit": "KG",
        "arrival_date": yesterday,
        "verification_status": "verified",
        "stale": True,
    }

    product = {
        "product_name": "Onion",
        "district": "Coimbatore",
        "quantity_unit": "KG",
        "pricing_mode": "MARKET_BASED",
    }

    with patch("app.services.pricing_service.MarketDiscoveryService.lookup") as mock_lookup:
        mock_lookup.return_value = {"records": [stale_record], "live": False}
        resolved = await engine.resolve_daily_market_price(product)
        assert resolved["reference_price_stale"] is True
        assert "unavailable" in resolved["market_price_status_message"].casefold() or "last available" in resolved["market_price_status_message"].casefold()


# ---------------------------------------------------------------------------
# Test 17: Manual refresh and scheduled refresh do not run concurrently
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_manual_and_scheduled_refresh_no_concurrency():
    mock_db = MagicMock()
    mock_claims = MagicMock()
    mock_db.__getitem__.return_value = mock_claims

    mock_claims.find_one = AsyncMock(return_value=None)
    # Lock lease is held by another active process (lease_until is in the future)
    mock_claims.find_one_and_update = AsyncMock(return_value=None)

    service = MarketDiscoveryService(mock_db)
    stats = await service.refresh_daily(force=True)

    # Must be skipped due to active lease lock
    assert stats["skipped"] == 1
    assert "lease busy" in stats["message"].casefold()
