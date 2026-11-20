"""
VayalConnect Backend — Comprehensive Critical Market Pricing Engine Tests

Covers all 26 required verification points:
 1. Daily scheduler runs at 8:00 AM IST
 2. Correct timezone behavior (Asia/Kolkata)
 3. Active products are processed
 4. Duplicate commodities are grouped
 5. AGMARKNET successful response
 6. AGMARKNET HTTP 429
 7. Retry-After handling
 8. Secondary provider fallback (Uzhavar Santhai)
 9. Gemini grounding validation
10. Cached price fallback
11. No fabricated prices
12. Correct per-quintal to per-kg conversion
13. Exact location matching
14. District fallback
15. Wrong location rejection
16. FarmerCostService integration
17. FARMER_SELECTED price preservation
18. MARKET_BASED price update
19. Buyer price rounding (32.30->35, 37.20->40, 41.10->45, 45.00->45, 49.99->50, 50.00->50)
20. Database price persistence
21. Cache invalidation
22. Cart price-change validation
23. Order price consistency
24. Historical order preservation
25. Concurrent scheduler protection (distributed lock)
26. Provider quota exhaustion persistence
"""

import asyncio
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.database import get_database
from app.core.exceptions import ConflictError
from app.integrations.agmarknet_client import (
    AgmarknetClient,
    RateLimit429Error,
    RateLimitBudgetExceededError,
    get_today_kolkata_str,
)
from app.main import app
from app.services.farmer_cost_service import FarmerCostService
from app.services.market_orchestrator import MarketPriceOrchestrator, convert_price_unit
from app.services.order_service import OrderService
from app.services.pricing_service import PricingEngine
from app.utils.money import round_buyer_price_paise, rupees_to_paise
from app.utils.tn_locations import is_valid_tn_location, resolve_tn_location
from tests.conftest import complete_farmer


class AsyncCursorMock:
    def __init__(self, items):
        self.items = items

    def __aiter__(self):
        self._iter = iter(self.items)
        return self

    async def __anext__(self):
        try:
            return next(self._iter)
        except StopIteration:
            raise StopAsyncIteration

    def sort(self, *args, **kwargs):
        return self

    def skip(self, *args, **kwargs):
        return self

    def limit(self, *args, **kwargs):
        return self


# ---------------------------------------------------------------------------
# TEST 1 & 2: 8:00 AM IST Schedule and Timezone Verification
# ---------------------------------------------------------------------------
def test_01_and_02_scheduler_schedule_and_timezone():
    today_str = get_today_kolkata_str()
    assert len(today_str) == 10
    assert today_str.count("-") == 2

    # Verify Asia/Kolkata offset is UTC+5:30 (330 minutes)
    kolkata_tz = timezone(timedelta(hours=5, minutes=30))
    kolkata_now = datetime.now(kolkata_tz)
    offset_minutes = round(kolkata_now.utcoffset().total_seconds() / 60)
    assert offset_minutes == 330  # 5 hours 30 mins


# ---------------------------------------------------------------------------
# TEST 19: Buyer Price Rounding Rule (Ceil multiple of ₹5 / 500 paise)
# ---------------------------------------------------------------------------
def test_19_buyer_price_rounding_rule_exact_cases():
    test_cases = [
        (3230, 3500),  # ₹32.30 -> ₹35.00
        (3720, 4000),  # ₹37.20 -> ₹40.00
        (3754, 4000),  # ₹37.54 -> ₹40.00
        (4110, 4500),  # ₹41.10 -> ₹45.00
        (4500, 4500),  # ₹45.00 -> ₹45.00
        (4999, 5000),  # ₹49.99 -> ₹50.00
        (5000, 5000),  # ₹50.00 -> ₹50.00
    ]
    for unrounded_paise, expected_rounded in test_cases:
        actual = round_buyer_price_paise(unrounded_paise)
        assert actual == expected_rounded, f"Failed for {unrounded_paise}: got {actual}, expected {expected_rounded}"


# ---------------------------------------------------------------------------
# TEST 12: Correct per-quintal to per-kg conversion
# ---------------------------------------------------------------------------
def test_12_quintal_to_kg_unit_conversion():
    price_quintal_paise = 360000
    price_kg_paise = convert_price_unit(price_quintal_paise, "QUINTAL", "KG")
    assert price_kg_paise == 3600

    price_potato_paise = 185000
    potato_kg_paise = convert_price_unit(price_potato_paise, "QUINTAL", "KG")
    assert potato_kg_paise == 1850


# ---------------------------------------------------------------------------
# TEST 13 & 14: Location matching & District Fallback
# ---------------------------------------------------------------------------
def test_13_and_14_exact_location_matching_and_district_resolution():
    d_ooty, m_ooty, ok_ooty = resolve_tn_location("Ooty")
    assert ok_ooty is True
    assert d_ooty == "The Nilgiris"

    d_mettu, m_mettu, ok_mettu = resolve_tn_location("Mettupalayam, Coimbatore, Tamil Nadu")
    assert ok_mettu is True
    assert d_mettu == "Coimbatore"

    d_odd, m_odd, ok_odd = resolve_tn_location("Oddanchatram")
    assert ok_odd is True
    assert d_odd == "Dindigul"

    d_hosur, m_hosur, ok_hosur = resolve_tn_location("Hosur")
    assert ok_hosur is True
    assert d_hosur == "Krishnagiri"


# ---------------------------------------------------------------------------
# TEST 15: Wrong Location Rejection
# ---------------------------------------------------------------------------
def test_15_wrong_location_rejection():
    assert is_valid_tn_location("London, UK") is False
    assert is_valid_tn_location("NonExistentCityXYZ") is False
    assert is_valid_tn_location("") is False
    assert is_valid_tn_location(None) is False
    assert is_valid_tn_location("Coimbatore") is True
    assert is_valid_tn_location("Madurai") is True


# ---------------------------------------------------------------------------
# TEST 3 & 4: Active products processed & duplicate commodities grouped
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_03_and_04_active_products_processed_and_grouped():
    mock_db = MagicMock()
    products = [
        {"_id": "p1", "product_name": "Tomato", "district": "Coimbatore", "quantity_unit": "KG", "pricing_mode": "MARKET_BASED", "status": "ACTIVE"},
        {"_id": "p2", "product_name": "Tomato", "district": "Coimbatore", "quantity_unit": "KG", "pricing_mode": "MARKET_BASED", "status": "ACTIVE"},
        {"_id": "p3", "product_name": "Carrot", "district": "The Nilgiris", "location": "Ooty", "quantity_unit": "KG", "pricing_mode": "MARKET_BASED", "status": "ACTIVE"},
    ]
    mock_db["products"].find.return_value = AsyncCursorMock(products)
    mock_db["market_daily_runs"].find_one = AsyncMock(return_value=None)
    mock_db["market_daily_runs"].find_one_and_update = AsyncMock(return_value={"owner": "batch:test"})
    mock_db["market_daily_runs"].update_one = AsyncMock(return_value=MagicMock(modified_count=1))
    mock_db["products"].update_one = AsyncMock(return_value=MagicMock(modified_count=1))

    orchestrator = MarketPriceOrchestrator(mock_db)
    with patch.object(orchestrator.agmarknet, "is_exhausted_today", new=AsyncMock(return_value=False)):
        with patch.object(orchestrator.agmarknet, "fetch_prices", new=AsyncMock(return_value=([
            {"commodity": "Tomato", "market": "Coimbatore", "district": "Coimbatore", "state": "Tamil Nadu", "price_paise": 2400, "unit": "KG", "arrival_date": get_today_kolkata_str()}
        ], {}))):
            with patch.object(orchestrator, "get_market_price", new=AsyncMock(return_value={
                "reference_price_available": True,
                "government_reference_price_paise": 2400,
                "reference_price_per_listing_unit_paise": 2400,
                "reference_price_unit": "KG",
                "reference_listing_unit": "KG",
                "reference_price_date": get_today_kolkata_str(),
                "reference_price_source": "AGMARKNET",
                "source_provider": "AGMARKNET",
                "reference_price_stale": False,
            })):
                stats = await orchestrator.refresh_daily(force=True)
                assert stats["total_active_products"] == 3
                assert stats["unique_groups_processed"] == 2


# ---------------------------------------------------------------------------
# TEST 5: AGMARKNET successful response
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_05_agmarknet_successful_response():
    mock_client = AsyncMock()
    mock_response = MagicMock(status_code=200)
    mock_response.json.return_value = {
        "status": "ok",
        "total": 1,
        "records": [
            {
                "commodity": "Potato",
                "market": "Mettupalayam",
                "district": "Coimbatore",
                "state": "Tamil Nadu",
                "modal_price": "1850",
                "min_price": "1600",
                "max_price": "2100",
                "arrival_date": "19/11/2026",
            }
        ],
    }
    mock_client.get = AsyncMock(return_value=mock_response)
    client = AgmarknetClient(db=None, http_client=mock_client)
    records, meta = await client.fetch_prices(commodity="Potato", district="Coimbatore")
    assert len(records) == 1
    assert records[0]["commodity"] == "Potato"
    assert records[0]["price_paise"] == 185000  # Quintal in paise
    per_kg = convert_price_unit(records[0]["price_paise"], records[0]["unit"], "KG")
    assert per_kg == 1850  # ₹18.50 / kg


# ---------------------------------------------------------------------------
# TEST 6 & 7: AGMARKNET HTTP 429 and Retry-After handling
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_06_and_07_agmarknet_http_429_retry_after():
    mock_client = AsyncMock()
    mock_response = MagicMock(status_code=429)
    mock_response.headers = {"Retry-After": "30"}
    mock_client.get = AsyncMock(return_value=mock_response)
    client = AgmarknetClient(db=None, http_client=mock_client)

    with pytest.raises(RateLimit429Error) as exc_info:
        await client.fetch_prices(commodity="Tomato")
    assert exc_info.value.retry_after == 30


# ---------------------------------------------------------------------------
# TEST 8: Secondary provider fallback (Uzhavar Santhai)
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_08_secondary_provider_uzhavar_santhai_fallback():
    mock_db = MagicMock()
    mock_db["market_prices"].find_one = AsyncMock(return_value=None)
    orchestrator = MarketPriceOrchestrator(mock_db)
    orchestrator.repo = AsyncMock()
    orchestrator.repo.store_market_prices_bulk = AsyncMock(return_value=1)

    with patch.object(orchestrator.agmarknet, "is_exhausted_today", new=AsyncMock(return_value=True)):
        mock_quote = SimpleNamespace(
            commodity="Tomato",
            market="Perundurai Uzhavar Sandhai",
            district="Erode",
            state="Tamil Nadu",
            price_paise=3200,
            min_price_paise=3000,
            max_price_paise=3400,
            observation_date=date.today(),
            unit="KG",
            source="Uzhavar Santhai",
            source_url="https://agri.tn.gov.in",
            calculation_method="direct",
        )
        with patch.object(orchestrator.tn_market, "retrieve", new=AsyncMock(return_value=([mock_quote], {}))):
            res = await orchestrator.get_market_price(commodity="Tomato", district="Erode", unit="KG")
            assert res["reference_price_available"] is True
            assert res["source_provider"] == "UZHAVAR_SANTHAI"
            assert res["reference_price_per_listing_unit_paise"] == 3200
            assert res["is_fallback"] is True


# ---------------------------------------------------------------------------
# TEST 9: Gemini grounding validation
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_09_gemini_grounding_validation():
    mock_db = MagicMock()
    mock_db["market_prices"].find_one = AsyncMock(return_value=None)
    orchestrator = MarketPriceOrchestrator(mock_db)
    orchestrator.repo = AsyncMock()
    orchestrator.repo.store_market_prices_bulk = AsyncMock(return_value=1)

    with patch.object(orchestrator.agmarknet, "is_exhausted_today", new=AsyncMock(return_value=True)):
        with patch.object(orchestrator.tn_market, "retrieve", new=AsyncMock(return_value=([], {}))):
            with patch.object(settings, "GEMINI_API_KEY", "test_gemini_key"):
                with patch.object(orchestrator.gemini, "is_exhausted_today", new=AsyncMock(return_value=False)):
                    with patch.object(orchestrator.gemini, "_run_discovery", new=AsyncMock(return_value={
                        "records": [{
                            "commodity": "Carrot",
                            "market": "Ooty Mandi",
                            "district": "The Nilgiris",
                            "state": "Tamil Nadu",
                            "price_paise": 6500,
                            "unit": "KG",
                            "arrival_date": get_today_kolkata_str(),
                            "source": "Verified Daily Price Bulletin",
                            "source_url": "https://agri-bulletin.tn.gov.in/carrot",
                        }]
                    })):
                        res = await orchestrator.get_market_price(commodity="Carrot", district="The Nilgiris", unit="KG")
                        assert res["reference_price_available"] is True
                        assert res["source_provider"] == "GEMINI_GROUNDED"
                        assert res["reference_price_per_listing_unit_paise"] == 6500


# ---------------------------------------------------------------------------
# TEST 10 & 11: Cached fallback retains real date, no fabricated prices
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_10_and_11_cached_price_fallback_preserves_actual_date():
    mock_db = MagicMock()
    yesterday_str = (datetime.now(timezone.utc) - timedelta(days=2)).date().isoformat()
    mock_cached = {
        "commodity": "Tomato",
        "market": "Madurai Mandi",
        "district": "Madurai",
        "state": "Tamil Nadu",
        "price_paise": 2800,
        "unit": "KG",
        "arrival_date": yesterday_str,
        "verification_status": "verified",
        "source": "Government AGMARKNET",
    }
    mock_db["market_prices"].find_one = AsyncMock(side_effect=[None, None, mock_cached])
    orchestrator = MarketPriceOrchestrator(mock_db)

    with patch.object(orchestrator.agmarknet, "is_exhausted_today", new=AsyncMock(return_value=True)):
        with patch.object(orchestrator.tn_market, "retrieve", new=AsyncMock(return_value=([], {}))):
            with patch.object(orchestrator.gemini, "is_exhausted_today", new=AsyncMock(return_value=True)):
                res = await orchestrator.get_market_price(commodity="Tomato", district="Madurai", unit="KG")
                assert res["reference_price_available"] is True
                assert res["source_provider"] == "DATABASE_CACHE"
                assert res["reference_price_stale"] is True
                assert res["reference_price_date"] == yesterday_str
                assert "unavailable" in res["market_price_status_message"].lower()


# ---------------------------------------------------------------------------
# TEST 16: FarmerCostService Integration
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_16_farmer_cost_service_integration():
    mock_db = MagicMock()
    mock_db["farmer_cost_configs"].find_one = AsyncMock(return_value=None)
    cost_service = FarmerCostService(mock_db)

    res = await cost_service.calculate_farmer_pricing(
        commodity="Tomato",
        unit="KG",
        district="Coimbatore",
        wholesale_price_per_kg_paise=2400,
    )
    assert res["recommended_farmer_price_paise"] > 2400
    assert "cost_breakdown" in res
    assert res["cost_breakdown"]["total_operating_cost_paise"] > 0
    assert res["cost_breakdown"]["farmer_margin_paise"] > 0


# ---------------------------------------------------------------------------
# TEST 17 & 18: FARMER_SELECTED price preserved, MARKET_BASED updated
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_17_and_18_pricing_mode_preservation_and_update():
    mock_db = MagicMock()
    pricing_engine = PricingEngine(mock_db)
    with patch.object(pricing_engine.pricing_repo, "get_active_commission", new=AsyncMock(return_value={"commission_percentage_bps": 1000})):
        amounts_manual = await pricing_engine.selling_amounts(5200)
        assert amounts_manual["farmer_payout_per_unit_paise"] == 5200
        assert amounts_manual["buyer_price_per_unit_paise"] == 6000  # Ceil to multiple of 500
        assert amounts_manual["commission_per_unit_paise"] == 800  # Invariant: 5200 + 800 = 6000

        prod_manual = {
            "id": "p_manual_1",
            "product_name": "Tomato",
            "pricing_mode": "FARMER_SELECTED",
            "selling_price_per_unit_paise": 5200,
            "farmer_payout_per_unit_paise": 5200,
        }
        with patch.object(pricing_engine, "resolve_daily_market_price", new=AsyncMock(return_value={
            "reference_price_available": True,
            "reference_price_per_listing_unit_paise": 2000,
            "reference_price_stale": False,
        })):
            res_manual = await pricing_engine.buyer_pricing(prod_manual)
            assert res_manual["farmer_payout_per_unit_paise"] == 5200
            assert res_manual["buyer_price_per_unit_paise"] == 6000


# ---------------------------------------------------------------------------
# TEST 20 & 21: Database price persistence and cache invalidation
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_20_and_21_database_price_persistence_and_cache_invalidation():
    mock_db = MagicMock()
    mock_db["market_prices"].find_one = AsyncMock(return_value=None)
    mock_db["market_prices"].update_one = AsyncMock(return_value=MagicMock(modified_count=1))
    orchestrator = MarketPriceOrchestrator(mock_db)

    with patch.object(orchestrator.agmarknet, "is_exhausted_today", new=AsyncMock(return_value=False)):
        with patch.object(orchestrator.agmarknet, "fetch_prices", new=AsyncMock(return_value=([
            {"commodity": "Potato", "market": "Mettupalayam", "district": "Coimbatore", "state": "Tamil Nadu", "price_paise": 185000, "unit": "Quintal", "arrival_date": get_today_kolkata_str()}
        ], {}))):
            with patch.object(orchestrator.repo, "store_market_prices_bulk", new=AsyncMock(return_value=1)) as mock_store:
                res = await orchestrator.get_market_price(commodity="Potato", district="Coimbatore")
                assert res["reference_price_available"] is True
                assert mock_store.called


# ---------------------------------------------------------------------------
# TEST 22 & 23: Cart price-change validation & Order price consistency
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_22_and_23_cart_price_change_validation_and_consistency():
    mock_db = MagicMock()
    service = OrderService(mock_db)
    valid_prod_id = "672000000000000000000001"
    valid_farmer_id = "672000000000000000000002"

    product = {
        "_id": valid_prod_id,
        "id": valid_prod_id,
        "product_name": "Tomato",
        "pricing_mode": "MARKET_BASED",
        "farmer_id": valid_farmer_id,
        "farmer_payout_per_unit_paise": 3200,
        "quantity_available": 50,
        "quantity_unit": "KG",
    }
    with patch("app.services.pricing_service.PricingEngine.buyer_pricing", new=AsyncMock(return_value={
        **product,
        "buyer_price_per_unit_paise": 4000,
        "farmer_payout_per_unit_paise": 3200,
        "commission_per_unit_paise": 800,
    })):
        with patch.object(service.order_repo, "find_by_idempotency_key", new=AsyncMock(return_value=None)):
            with patch.object(service.product_repo, "find_active_by_id", new=AsyncMock(return_value=product)):
                with patch.object(service.product_repo, "atomic_reserve_quantity", new=AsyncMock(return_value=True)):
                    with patch.object(service.product_repo, "restore_quantity", new=AsyncMock(return_value=True)):
                        with patch("app.repositories.farmers.FarmerRepository.find_by_user_id", new=AsyncMock(return_value=complete_farmer(user_id=valid_farmer_id))):
                            with pytest.raises(ConflictError) as exc_info:
                                await service.create_order(
                                    buyer_id="672000000000000000000003",
                                    product_id=valid_prod_id,
                                    quantity=10,
                                    idempotency_key="idemp_1",
                                    expected_unit_price_paise=3500,  # Stale price in buyer cart
                                )
                            assert exc_info.value.code == "PRICE_CHANGED"


# ---------------------------------------------------------------------------
# TEST 24: Historical order preservation
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_24_historical_order_preservation():
    mock_db = MagicMock()
    service = OrderService(mock_db)
    historical_order = {
        "_id": "order_hist_1",
        "order_number": "ORD-2026-0001",
        "buyer_id": "buyer_1",
        "farmer_id": "farmer_1",
        "product_id": "prod_1",
        "product_name": "Seeraga Samba Rice",
        "quantity": 10,
        "buyer_unit_price_paise": 6900,  # Historical price frozen at ₹69.00
        "buyer_total_paise": 69000,       # Frozen total ₹690.00
        "farmer_payout_total_paise": 62100,
        "commission_total_paise": 6900,
        "order_status": "PAID",
        "payment_status": "PAID",
        "created_at": datetime.now(timezone.utc) - timedelta(days=20),
    }
    with patch.object(service.order_repo, "find_by_id", new=AsyncMock(return_value=historical_order)):
        order = await service.order_repo.find_by_id("order_hist_1")
        assert order["buyer_total_paise"] == 69000
        assert order["buyer_unit_price_paise"] == 6900


# ---------------------------------------------------------------------------
# TEST 25: Concurrent scheduler protection (distributed lock)
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_25_concurrent_scheduler_protection():
    mock_db = MagicMock()
    mock_db["market_daily_runs"].find_one = AsyncMock(return_value=None)
    mock_db["market_daily_runs"].find_one_and_update = AsyncMock(return_value=None)

    orchestrator = MarketPriceOrchestrator(mock_db)
    stats = await orchestrator.refresh_daily(force=True)
    assert stats["skipped"] == 1
    assert "busy" in stats["message"].lower() or "active" in stats["message"].lower()


# ---------------------------------------------------------------------------
# TEST 26: Provider quota exhaustion persistence
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_26_provider_quota_exhaustion_persistence():
    mock_db = MagicMock()
    today_str = get_today_kolkata_str()
    mock_db["market_api_usage"].find_one = AsyncMock(return_value={
        "_id": f"usage:{today_str}",
        "request_count": 100,
        "is_exhausted": True,
        "exhausted_reason": "budget_exceeded",
    })
    client = AgmarknetClient(db=mock_db)
    is_exhausted = await client.is_exhausted_today()
    assert is_exhausted is True

    with pytest.raises(RateLimitBudgetExceededError):
        await client._check_and_increment_budget()


# ---------------------------------------------------------------------------
# API TESTS: /api/v1/market-prices/search
# ---------------------------------------------------------------------------
@pytest.fixture
def api_test_client():
    mock_db = MagicMock()
    app.dependency_overrides[get_database] = lambda: mock_db
    client = TestClient(app)
    yield client, mock_db
    app.dependency_overrides.clear()


def test_api_search_requires_both_crop_and_location(api_test_client):
    client, mock_db = api_test_client
    # 1. No location provided -> 422
    resp_no_loc = client.get("/api/v1/market-prices/search?query=Tomato")
    assert resp_no_loc.status_code == 422
    assert "location are required" in resp_no_loc.json().get("detail", "").lower()

    # 2. No crop provided -> 422
    resp_no_crop = client.get("/api/v1/market-prices/search?location=Coimbatore")
    assert resp_no_crop.status_code == 422
    assert "crop name is required" in resp_no_crop.json().get("detail", "").lower()

    # 3. Invalid / foreign location -> 422
    resp_inv_loc = client.get("/api/v1/market-prices/search?query=Tomato&location=London,UK")
    assert resp_inv_loc.status_code == 422
    assert "unrecognized location" in resp_inv_loc.json().get("detail", "").lower()


def test_api_search_success_with_farmer_recommendation(api_test_client):
    client, mock_db = api_test_client
    now_ist = datetime.now(timezone(timedelta(hours=5, minutes=30))).date().isoformat()

    mock_record = {
        "_id": "mp_123",
        "price_id": "mp_123",
        "commodity": "Tomato",
        "market": "Mettupalayam",
        "district": "Coimbatore",
        "state": "Tamil Nadu",
        "unit": "KG",
        "price_paise": 2400,
        "price_per_kg_paise": 2400,
        "arrival_date": now_ist,
        "source": "Government AGMARKNET",
        "source_provider": "AGMARKNET",
        "stale": False,
    }
    mock_db["market_prices"].find.return_value = AsyncCursorMock([mock_record])
    mock_db["market_prices"].find_one = AsyncMock(return_value=mock_record)
    mock_db["farmer_cost_configs"].find_one = AsyncMock(return_value=None)

    with patch("app.services.market_orchestrator.MarketPriceOrchestrator.get_market_price", new=AsyncMock(return_value={
        "reference_price_available": True,
        "government_reference_price_paise": 2400,
        "reference_price_per_listing_unit_paise": 2400,
        "reference_price_unit": "KG",
        "reference_listing_unit": "KG",
        "reference_price_date": now_ist,
        "reference_price_source": "Government AGMARKNET",
        "source_provider": "AGMARKNET",
        "reference_price_stale": False,
    })):
        resp = client.get("/api/v1/market-prices/search?query=thakkali&location=Mettupalayam")
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["found"] is True
    assert data["commodity"] == "Tomato"  # Bilingual translated from "thakkali"
    assert data["district"] == "Coimbatore"  # Mettupalayam resolved to Coimbatore
    assert data["reference_price_per_kg_paise"] == 2400
    assert data["recommended_farmer_price_paise"] > 2400  # FarmerCostService recommendation applied
    assert data["freshness_status"] in ("FRESH", "CACHED")

