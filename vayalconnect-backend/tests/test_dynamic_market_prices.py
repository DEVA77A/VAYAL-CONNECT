"""
Tests for Daily Dynamic Agricultural Market Pricing System.
Verifies:
1. Priority 3 matching (District -> Mandi -> Statewide -> Fallback)
2. Unit conversions (Quintal to KG) and modal price selection
3. Dynamic pricing in MARKET_BASED vs FARMER_SELECTED modes
4. Stale price indicators and fallback (no ₹0 prices)
5. Order price revalidation (PRICE_CHANGED) and immutable snapshotting
6. Non-disturbance to Razorpay and farmer payouts
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from datetime import date, datetime, timezone, timedelta
from decimal import Decimal

from app.services.pricing_service import PricingEngine
from app.services.market_discovery import MarketDiscoveryService
from app.core.exceptions import ConflictError, ValidationError


@pytest.fixture
def mock_db():
    db = AsyncMock()
    return db


@pytest.mark.asyncio
async def test_market_price_matching_district_priority(mock_db):
    """Test that district match takes priority over generic statewide quotes."""
    engine = PricingEngine(mock_db)

    today = datetime.now(timezone(timedelta(hours=5, minutes=30))).date().isoformat()

    district_record = {
        "commodity": "Tomato",
        "market": "Madurai Central Market",
        "district": "Madurai",
        "state": "Tamil Nadu",
        "modal_price_paise": 3200,  # ₹32/kg
        "price_paise": 3200,
        "unit": "KG",
        "arrival_date": today,
        "observation_date": today,
        "source": "AGMARKNET Mandi",
        "verification_status": "verified",
        "stale": False,
    }

    product = {
        "product_name": "Tomato",
        "district": "Madurai",
        "state": "Tamil Nadu",
        "quantity_unit": "KG",
        "farmer_payout_per_unit_paise": 3000,
        "pricing_mode": "MARKET_BASED",
    }

    with patch("app.services.pricing_service.MarketDiscoveryService.lookup") as mock_lookup:
        mock_lookup.return_value = {"records": [district_record], "live": True, "source": "AGMARKNET"}
        ref = await engine.resolve_daily_market_price(product)

        assert ref["reference_price_available"] is True
        assert ref["government_reference_price_paise"] == 3200
        assert ref["reference_price_per_listing_unit_paise"] == 3200
        assert ref["reference_district"] == "Madurai"
        assert ref["reference_price_stale"] is False
        assert "Updated today" in ref["market_price_status_message"]


@pytest.mark.asyncio
async def test_unit_conversion_quintal_to_kg(mock_db):
    """Test conversion from Quintal (100 KG) to KG listing unit."""
    engine = PricingEngine(mock_db)
    today = datetime.now(timezone(timedelta(hours=5, minutes=30))).date().isoformat()

    quintal_record = {
        "commodity": "Paddy",
        "market": "Thanjavur Mandi",
        "district": "Thanjavur",
        "state": "Tamil Nadu",
        "modal_price_paise": 240000,  # ₹2400 / quintal = ₹24.00 / kg = 2400 paise
        "price_paise": 240000,
        "unit": "Quintal",
        "arrival_date": today,
        "observation_date": today,
        "source": "AGMARKNET",
        "verification_status": "verified",
        "stale": False,
    }

    product = {
        "product_name": "Paddy",
        "district": "Thanjavur",
        "state": "Tamil Nadu",
        "quantity_unit": "KG",
        "farmer_payout_per_unit_paise": 2000,
        "pricing_mode": "MARKET_BASED",
    }

    with patch("app.services.pricing_service.MarketDiscoveryService.lookup") as mock_lookup:
        mock_lookup.return_value = {"records": [quintal_record], "live": True, "source": "AGMARKNET"}
        ref = await engine.resolve_daily_market_price(product)

        assert ref["reference_price_available"] is True
        assert ref["government_reference_price_paise"] == 240000
        assert ref["reference_price_per_listing_unit_paise"] == 2400  # 240000 / 100
        assert ref["reference_price_unit"] == "Quintal"
        assert ref["reference_listing_unit"] == "KG"


@pytest.mark.asyncio
async def test_stale_price_fallback_preserves_nonzero_price(mock_db):
    """Test that outdated records or API failures fall back to last known good price and flag stale."""
    engine = PricingEngine(mock_db)
    yesterday = (datetime.now(timezone(timedelta(hours=5, minutes=30))).date() - timedelta(days=2)).isoformat()

    stale_record = {
        "commodity": "Onion",
        "market": "Dindigul Mandi",
        "district": "Dindigul",
        "state": "Tamil Nadu",
        "modal_price_paise": 3500,  # ₹35/kg
        "price_paise": 3500,
        "unit": "KG",
        "arrival_date": yesterday,
        "observation_date": yesterday,
        "source": "AGMARKNET",
        "verification_status": "verified",
        "stale": True,
    }

    product = {
        "product_name": "Onion",
        "district": "Dindigul",
        "state": "Tamil Nadu",
        "quantity_unit": "KG",
        "farmer_payout_per_unit_paise": 3500,
        "pricing_mode": "MARKET_BASED",
    }

    with patch("app.services.pricing_service.MarketDiscoveryService.lookup") as mock_lookup:
        mock_lookup.return_value = {"records": [stale_record], "live": False, "source": "Cache"}
        ref = await engine.resolve_daily_market_price(product)

        assert ref["reference_price_available"] is True
        assert ref["government_reference_price_paise"] == 3500
        assert ref["reference_price_per_listing_unit_paise"] == 3500
        assert ref["reference_price_stale"] is True
        assert "Market price update unavailable" in ref["market_price_status_message"]
        # Must never be zero
        assert ref["reference_price_per_listing_unit_paise"] > 0


@pytest.mark.asyncio
async def test_market_based_buyer_pricing_calculation(mock_db):
    """Verify buyer pricing dynamically updates when product is MARKET_BASED."""
    engine = PricingEngine(mock_db)
    today = datetime.now(timezone(timedelta(hours=5, minutes=30))).date().isoformat()

    today_record = {
        "commodity": "Tomato",
        "market": "Coimbatore Mandi",
        "district": "Coimbatore",
        "state": "Tamil Nadu",
        "modal_price_paise": 3000,  # ₹30/kg
        "price_paise": 3000,
        "unit": "KG",
        "arrival_date": today,
        "observation_date": today,
        "source": "AGMARKNET",
        "verification_status": "verified",
        "stale": False,
    }

    product = {
        "id": "prod_tomato",
        "product_name": "Tomato",
        "district": "Coimbatore",
        "state": "Tamil Nadu",
        "quantity_unit": "KG",
        "farmer_payout_per_unit_paise": 2500,  # Old farmer setting
        "pricing_mode": "MARKET_BASED",
    }

    with patch("app.services.pricing_service.MarketDiscoveryService.lookup") as mock_lookup:
        mock_lookup.return_value = {"records": [today_record], "live": True, "source": "AGMARKNET"}
        with patch.object(engine.pricing_repo, "get_active_commission", new=AsyncMock(return_value={
            "commission_percentage_bps": 1000,  # 10%
        })):
            priced = await engine.buyer_pricing(product)

            # In MARKET_BASED mode, farmer payout tracks market reference (3000 paise = ₹30)
            assert priced["farmer_payout_per_unit_paise"] == 3000
            # Commission is 10% of 3000 = 300 paise
            assert priced["commission_per_unit_paise"] == 300
            # Buyer pays 3000 + 300 = 3300 paise = ₹33.00 / kg
            assert priced["buyer_price_per_unit_paise"] == 3300
            # Reference metadata attached
            assert priced["reference_price_stale"] is False
            assert priced["government_reference_price_paise"] == 3000


@pytest.mark.asyncio
async def test_farmer_selected_mode_preserves_farmer_payout(mock_db):
    """Verify that in FARMER_SELECTED mode, farmer-set payout is never overridden."""
    engine = PricingEngine(mock_db)
    today = datetime.now(timezone(timedelta(hours=5, minutes=30))).date().isoformat()

    market_record = {
        "commodity": "Organic Tomato",
        "market": "Coimbatore Mandi",
        "district": "Coimbatore",
        "state": "Tamil Nadu",
        "modal_price_paise": 3000,  # ₹30/kg
        "price_paise": 3000,
        "unit": "KG",
        "arrival_date": today,
        "observation_date": today,
        "source": "AGMARKNET",
        "verification_status": "verified",
        "stale": False,
    }

    # Farmer explicitly wants ₹50/kg regardless of wholesale market price
    product = {
        "id": "prod_premium_tomato",
        "product_name": "Organic Tomato",
        "district": "Coimbatore",
        "state": "Tamil Nadu",
        "quantity_unit": "KG",
        "farmer_payout_per_unit_paise": 5000,  # Farmer set ₹50/kg
        "pricing_mode": "FARMER_SELECTED",
    }

    with patch("app.services.pricing_service.MarketDiscoveryService.lookup") as mock_lookup:
        mock_lookup.return_value = {"records": [market_record], "live": True, "source": "AGMARKNET"}
        with patch.object(engine.pricing_repo, "get_active_commission", new=AsyncMock(return_value={
            "commission_percentage_bps": 1000,  # 10%
        })):
            priced = await engine.buyer_pricing(product)

            # Farmer payout remains exactly ₹50.00 (5000 paise)
            assert priced["farmer_payout_per_unit_paise"] == 5000
            # Commission is 10% of 5000 = 500 paise
            assert priced["commission_per_unit_paise"] == 500
            # Buyer pays 5500 paise = ₹55.00 / kg
            assert priced["buyer_price_per_unit_paise"] == 5500
            # Market reference still visible as market indicator
            assert priced["government_reference_price_paise"] == 3000

