"""
Integration tests for Agricultural Pricing Intelligence & Admin Cost Configuration:
- Separation of Wholesale, Retail, and Farmer Direct price categories
- GET /api/v1/products/price-reference with cost breakdown & recommendations
- Admin cost config GET/PUT/AUDIT endpoints
- Protected role access
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from fastapi.testclient import TestClient
from app.main import app
from app.core.security import create_access_token


@pytest.fixture
def mock_db():
    db = MagicMock()
    # Mock collections
    def col_mock(name):
        c = MagicMock()
        c.find_one = AsyncMock(return_value=None)
        c.find = MagicMock(return_value=MagicMock(
            sort=MagicMock(return_value=MagicMock(
                limit=MagicMock(return_value=MagicMock(
                    to_list=AsyncMock(return_value=[])
                ))
            ))
        ))
        c.update_one = AsyncMock(return_value=MagicMock(modified_count=1))
        c.insert_one = AsyncMock(return_value=MagicMock(inserted_id="doc_id_123"))
        return c

    db.__getitem__.side_effect = col_mock
    return db


@pytest.mark.asyncio
async def test_price_reference_returns_cost_model_and_categories(mock_db, monkeypatch):
    app.state.database_ready = True
    from app.core.database import get_database
    app.dependency_overrides[get_database] = lambda: mock_db

    farmer_id = "672000000000000000000002"
    from app.repositories.users import UserRepository
    from app.services.pricing_service import PricingEngine

    mock_user = {"id": farmer_id, "role": "FARMER", "is_active": True}

    fake_ref = {
        "reference_price_available": True,
        "government_reference_price_paise": 360000,
        "reference_price_per_listing_unit_paise": 3600,
        "reference_price_unit": "QUINTAL",
        "reference_listing_unit": "KG",
        "reference_price_date": "2026-11-03",
        "reference_price_source": "AGMARKNET (data.gov.in)",
        "reference_price_cached": True,
        "reference_price_stale": False,
        "reference_commodity": "Tomato",
        "reference_market": "Madurai",
        "reference_district": "Madurai",
        "reference_state": "Tamil Nadu",
        "reference_source_url": "https://api.data.gov.in",
        "reference_records": [],
        "reference_price_message": "Verified market price available",
    }

    with patch.object(UserRepository, "find_by_id", new=AsyncMock(return_value=mock_user)), \
         patch.object(PricingEngine, "get_verified_reference", new=AsyncMock(return_value=dict(fake_ref))):

        client = TestClient(app, raise_server_exceptions=True)
        token = create_access_token({"sub": farmer_id, "role": "FARMER"})
        res = client.get(
            "/api/v1/products/price-reference?commodity=Tomato&unit=KG&district=Madurai",
            headers={"Authorization": f"Bearer {token}"},
        )

        assert res.status_code == 200
        data = res.json()["data"]

        # 1. Cost model breakdown
        assert "cost_breakdown" in data
        assert data["cost_breakdown"]["harvesting_cost_paise"] > 0
        assert data["cost_breakdown"]["total_operating_cost_paise"] > 0
        assert data["minimum_sustainable_price_paise"] > 3600 # Greater than wholesale
        assert data["recommended_farmer_price_paise"] > data["minimum_sustainable_price_paise"]

        # 2. Three separated categories
        assert data["wholesale_reference"]["category"] == "WHOLESALE"
        assert data["wholesale_reference"]["price_per_kg_paise"] == 3600
        assert data["retail_reference"]["category"] == "RETAIL"
        assert data["farmer_direct_reference"]["category"] == "FARMER_DIRECT"
        assert data["farmer_direct_reference"]["minimum_sustainable_price_paise"] == data["minimum_sustainable_price_paise"]


@pytest.mark.asyncio
async def test_admin_cost_config_endpoints(mock_db):
    app.state.database_ready = True
    from app.core.database import get_database
    app.dependency_overrides[get_database] = lambda: mock_db

    admin_id = "672000000000000000000003"
    from app.repositories.users import UserRepository
    from app.services.farmer_cost_service import FarmerCostService

    mock_admin = {"id": admin_id, "role": "ADMIN", "is_active": True}

    with patch.object(UserRepository, "find_by_id", new=AsyncMock(return_value=mock_admin)):
        client = TestClient(app, raise_server_exceptions=True)
        token = create_access_token({"sub": admin_id, "role": "ADMIN"})

        # GET config
        res_get = client.get(
            "/api/v1/admin/pricing-cost-config",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert res_get.status_code == 200
        assert "harvesting_cost_paise" in res_get.json()["data"]

        # PUT config
        res_put = client.put(
            "/api/v1/admin/pricing-cost-config",
            json={"harvesting_cost_paise": 275, "default_farmer_margin_bps": 1800},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert res_put.status_code == 200

        # GET audit
        res_audit = client.get(
            "/api/v1/admin/pricing-cost-config/audit",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert res_audit.status_code == 200
        assert "items" in res_audit.json()["data"]

