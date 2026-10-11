"""
Unit tests for the Pricing Engine and Pricing Service.
Tests government market price integration, policy application,
financial consistency, and role-filtered pricing projections.
"""

import pytest
from unittest.mock import AsyncMock, patch
from app.services.pricing_service import PricingEngine
from app.core.exceptions import FinancialInconsistencyError, MarketPriceUnavailableError


@pytest.fixture
def mock_db():
    db = AsyncMock()
    return db


@pytest.mark.asyncio
async def test_pricing_engine_calculation_success(mock_db):
    engine = PricingEngine(mock_db)

    # Mock market price provider to return ₹30/kg = 3000 paise/kg (300000 paise per quintal)
    mock_market_price = {
        "commodity": "Paddy",
        "market": "Madurai",
        "modal_price_verified": True,
        "min_price_paise": 290000, "max_price_paise": 310000,
        "modal_price_paise": 300000,  # 3000 per quintal (100 kg) -> 3000 paise/kg = ₹30/kg
        "unit": "Quintal",
        "arrival_date": "2026-10-09",
        "source": "data.gov.in AGMARKNET",
        "retrieved_at": "2026-10-09T00:00:00Z",
    }

    with patch("app.services.pricing_service.market_price_provider.get_market_price",
               new=AsyncMock(return_value=mock_market_price)):
        with patch.object(engine.pricing_repo, "store_market_price", new=AsyncMock()):
            with patch.object(engine.pricing_repo, "get_active_policy", new=AsyncMock(return_value={
                "id": "policy_123",
                "version": 1,
                "farmer_payout_percentage_bps": 7000,  # 70%
                "buyer_price_percentage_bps": 9000,    # 90%
            })):
                with patch.object(engine.pricing_repo, "get_active_commission", new=AsyncMock(return_value={
                    "id": "comm_123",
                    "version": 1,
                    "commission_percentage_bps": 2000,  # 20%
                })):
                    snapshot = await engine.calculate_pricing(
                        product_name="Paddy",
                        category="Grains",
                        quantity=100,  # 100 kg
                        unit="KG",
                        quality_grade="A",
                        location="Madurai",
                        market="Madurai",
                        farmer_id="farmer_abc",
                    )

                    # Assertions
                    assert snapshot["government_per_kg_paise"] == 3000  # 300000 / 100
                    # Farmer payout per kg = 70% of 3000 = 2100 paise (₹21.00)
                    assert snapshot["farmer_payout_per_unit_paise"] == 2100
                    # Buyer price per kg = 90% of 3000 = 2700 paise (₹27.00)
                    assert snapshot["buyer_price_per_unit_paise"] == 2700
                    # Commission per kg = 2700 - 2100 = 600 paise (20% of 3000 = 600 paise)
                    assert snapshot["commission_per_unit_paise"] == 600

                    # Total checks for 100 kg
                    assert snapshot["farmer_total_payout_paise"] == 210000  # ₹2,100.00
                    assert snapshot["buyer_total_paise"] == 270000          # ₹2,700.00
                    assert snapshot["commission_total_paise"] == 60000      # ₹600.00

                    # Invariant: buyer_total == farmer_total + commission
                    assert snapshot["buyer_total_paise"] == (
                        snapshot["farmer_total_payout_paise"] + snapshot["commission_total_paise"]
                    )


@pytest.mark.asyncio
async def test_pricing_engine_unavailable_market_price_raises_error(mock_db):
    engine = PricingEngine(mock_db)

    with patch("app.services.pricing_service.market_price_provider.get_market_price",
               new=AsyncMock(return_value=None)):
        with patch.object(engine.pricing_repo, "get_latest_market_price", new=AsyncMock(return_value=None)):
            with pytest.raises(MarketPriceUnavailableError):
                await engine.calculate_pricing(
                    product_name="UnknownCrop",
                    category="Grains",
                    quantity=50,
                    unit="KG",
                    quality_grade="A",
                    location="Salem",
                    market="Salem",
                    farmer_id="farmer_xyz",
                )


@pytest.mark.asyncio
async def test_pricing_engine_rejects_negative_commission(mock_db):
    engine = PricingEngine(mock_db)

    mock_market_price = {
        "commodity": "Paddy",
        "market": "Madurai",
        "modal_price_verified": True,
        "min_price_paise": 290000, "max_price_paise": 310000,
        "modal_price_paise": 300000,
        "unit": "Quintal",
        "arrival_date": "2026-10-09",
        "source": "data.gov.in AGMARKNET",
        "retrieved_at": "2026-10-09T00:00:00Z",
    }

    with patch("app.services.pricing_service.market_price_provider.get_market_price",
               new=AsyncMock(return_value=mock_market_price)):
        with patch.object(engine.pricing_repo, "store_market_price", new=AsyncMock()):
            # Farmer payout higher than buyer price -> negative commission!
            with patch.object(engine.pricing_repo, "get_active_policy", new=AsyncMock(return_value={
                "id": "policy_bad",
                "version": 1,
                "farmer_payout_percentage_bps": 9500,  # 95%
                "buyer_price_percentage_bps": 9000,    # 90%
            })):
                with patch.object(engine.pricing_repo, "get_active_commission", new=AsyncMock(return_value={
                    "id": "comm_bad",
                    "version": 1,
                    "commission_percentage_bps": 2000,
                })):
                    with pytest.raises(FinancialInconsistencyError):
                        await engine.calculate_pricing(
                            product_name="Paddy",
                            category="Grains",
                            quantity=10,
                            unit="KG",
                            quality_grade="A",
                            location="Madurai",
                            market="Madurai",
                            farmer_id="farmer_abc",
                        )
