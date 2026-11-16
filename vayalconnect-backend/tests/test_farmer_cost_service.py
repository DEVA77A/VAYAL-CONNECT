"""
Unit tests for FarmerCostService:
- Production & operating cost breakdown
- Minimum sustainable farmer price
- Recommended farmer price (cost + margin)
- Crop-specific & district-specific adjustments
- Local retail sanity benchmark (Uzhavar Sandhai)
- Admin configuration & audit history
"""

import pytest
from unittest.mock import AsyncMock, MagicMock
from app.services.farmer_cost_service import (
    FarmerCostService,
    DEFAULT_HARVESTING_COST_PAISE,
    DEFAULT_SORTING_COST_PAISE,
    DEFAULT_PACKAGING_COST_PAISE,
    DEFAULT_TRANSPORT_COST_PAISE,
    DEFAULT_HANDLING_COST_PAISE,
)


@pytest.fixture
def mock_db():
    db = MagicMock()
    # Mock configs collection
    configs_col = MagicMock()
    configs_col.find_one = AsyncMock(return_value=None)
    configs_col.update_one = AsyncMock(return_value=MagicMock(modified_count=1))
    configs_col.insert_one = AsyncMock(return_value=MagicMock(inserted_id="active_cost_config"))

    # Mock audit collection
    audit_col = MagicMock()
    audit_col.insert_one = AsyncMock(return_value=MagicMock(inserted_id="audit_123"))

    def get_collection(name):
        if name == "pricing_cost_configs":
            return configs_col
        if name == "pricing_cost_audit":
            return audit_col
        col = MagicMock()
        col.find_one = AsyncMock(return_value=None)
        return col

    db.__getitem__.side_effect = get_collection
    return db


@pytest.mark.asyncio
async def test_farmer_cost_calculation_default(mock_db):
    service = FarmerCostService(mock_db)

    # Wholesale price: ₹36.00 / KG (3600 paise)
    result = await service.calculate_farmer_pricing(
        commodity="GenericCrop",
        unit="KG",
        wholesale_price_per_kg_paise=3600,
    )

    cost = result["cost_breakdown"]
    assert cost["harvesting_cost_paise"] == DEFAULT_HARVESTING_COST_PAISE # 200
    assert cost["sorting_cost_paise"] == DEFAULT_SORTING_COST_PAISE       # 150
    assert cost["packaging_cost_paise"] == DEFAULT_PACKAGING_COST_PAISE   # 150
    assert cost["transport_cost_paise"] == DEFAULT_TRANSPORT_COST_PAISE   # 200
    assert cost["handling_cost_paise"] == DEFAULT_HANDLING_COST_PAISE     # 100
    # Wastage: 5% of 3600 = 180 paise
    assert cost["wastage_allowance_paise"] == 180

    total_op = 200 + 150 + 150 + 200 + 100 + 180 # 980 paise (₹9.80)
    assert cost["total_operating_cost_paise"] == total_op

    # Minimum sustainable = 3600 + 980 = 4580 paise (₹45.80)
    min_sustainable = 3600 + total_op
    assert result["minimum_sustainable_price_paise"] == min_sustainable
    assert result["minimum_sustainable_price_display"] == "₹45.80"

    # Farmer margin: 15% of 4580 = 687 paise
    margin = int(round(4580 * 0.15))
    assert cost["farmer_margin_paise"] == margin

    # Recommended price = 4580 + 687 = 5267 paise (₹52.67)
    assert result["recommended_farmer_price_paise"] == min_sustainable + margin
    assert result["suggested_above_retail"] is False


@pytest.mark.asyncio
async def test_farmer_cost_crop_specific_adjustments(mock_db):
    service = FarmerCostService(mock_db)

    # Tomato has higher wastage (8%) and harvesting (₹2.50)
    result = await service.calculate_farmer_pricing(
        commodity="Tomato",
        unit="KG",
        wholesale_price_per_kg_paise=3000, # ₹30.00
    )

    cost = result["cost_breakdown"]
    assert cost["harvesting_cost_paise"] == 250
    # Wastage: 8% of 3000 = 240 paise
    assert cost["wastage_allowance_paise"] == 240


@pytest.mark.asyncio
async def test_farmer_cost_district_adjustments(mock_db):
    service = FarmerCostService(mock_db)

    # Nilgiris has higher transit cost (₹3.50 / KG)
    result = await service.calculate_farmer_pricing(
        commodity="Carrot",
        district="The Nilgiris",
        unit="KG",
        wholesale_price_per_kg_paise=4000,
    )

    cost = result["cost_breakdown"]
    assert cost["transport_cost_paise"] == 350


@pytest.mark.asyncio
async def test_farmer_cost_retail_benchmark_flag(mock_db):
    service = FarmerCostService(mock_db)

    # If wholesale is high (e.g. ₹60.00) leading to recommended price ₹75.00
    # but local Uzhavar Sandhai retail is ₹45.00, it must be flagged for review!
    result = await service.calculate_farmer_pricing(
        commodity="Tomato",
        unit="KG",
        wholesale_price_per_kg_paise=6000,
        retail_price_per_kg_paise=4500,
        retail_source="Uzhavar Sandhai Madurai",
    )

    assert result["suggested_above_retail"] is True
    assert "exceeds local retail benchmark" in result["review_notes"]


@pytest.mark.asyncio
async def test_admin_config_update_and_audit(mock_db):
    service = FarmerCostService(mock_db)

    updates = {
        "harvesting_cost_paise": 280,
        "default_farmer_margin_bps": 2000,
    }
    updated = await service.update_config(admin_id="admin_user_1", updates=updates)

    # Verify audit collection was called
    audit_col = mock_db["pricing_cost_audit"]
    assert audit_col.insert_one.called
    call_args = audit_col.insert_one.call_args[0][0]
    assert call_args["changed_by"] == "admin_user_1"
    assert call_args["new_values"]["harvesting_cost_paise"] == 280

