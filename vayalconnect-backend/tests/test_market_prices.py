"""
Automated tests for Government Market Price Integration and API Endpoints.
Tests:
- Government API record normalization & field parsing (including XML-escaped fields)
- Unit conversions (Rupees/Quintal to Paise and Rupees/kg)
- Upstream live success, timeout, and connection error handling
- FastAPI endpoint /api/v1/market-prices (live success, cache fallback, empty state)
- Filter options endpoint
- No secret exposure
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from datetime import date
import httpx
from fastapi.testclient import TestClient

from app.integrations.government_market import GovernmentMarketPriceProvider, market_price_provider
from app.main import app
from app.core.database import get_database


@pytest.fixture
def test_client():
    mock_db = AsyncMock()
    app.dependency_overrides[get_database] = lambda: mock_db
    client = TestClient(app)
    yield client, mock_db
    app.dependency_overrides.clear()


def test_normalize_record_standard_fields():
    provider = GovernmentMarketPriceProvider()
    raw = {
        "commodity": "Paddy",
        "market": "Madurai",
        "district": "Madurai",
        "state": "Tamil Nadu",
        "variety": "Ponni",
        "grade": "FAQ",
        "arrival_date": "09/10/2026",
        "min_price": "2200",
        "max_price": "2600",
        "modal_price": "2400",
    }
    normalized = provider._normalize_record(raw)

    assert normalized["commodity"] == "Paddy"
    assert normalized["market"] == "Madurai"
    assert normalized["district"] == "Madurai"
    assert normalized["state"] == "Tamil Nadu"
    assert normalized["variety"] == "Ponni"
    assert normalized["min_price_paise"] == 220000
    assert normalized["max_price_paise"] == 260000
    assert normalized["modal_price_paise"] == 240000
    assert normalized["price_per_kg_paise"] == 2400  # ₹24.00 / kg = 2400 paise
    assert "₹24.00 / kg" in normalized["price_per_kg_display"]
    assert normalized["unit"] == "Quintal"
    assert normalized["arrival_date"] == date(2026, 10, 9)
    assert normalized["source"] == "data.gov.in AGMARKNET"


def test_normalize_record_xml_escaped_fields():
    provider = GovernmentMarketPriceProvider()
    raw = {
        "Commodity": "Tomato",
        "Market": "Ottanchatram",
        "District": "Dindigul",
        "State": "Tamil Nadu",
        "Variety": "Local",
        "Grade": "FAQ",
        "Arrival_Date": "08/10/2026",
        "Min_x0020_Price": "1500",
        "Max_x0020_Price": "1800",
        "Modal_x0020_Price": "1650",
    }
    normalized = provider._normalize_record(raw)

    assert normalized["commodity"] == "Tomato"
    assert normalized["market"] == "Ottanchatram"
    assert normalized["district"] == "Dindigul"
    assert normalized["modal_price_paise"] == 165000
    assert normalized["price_per_kg_paise"] == 1650  # ₹16.50 / kg = 1650 paise
    assert normalized["arrival_date"] == date(2026, 10, 8)


@pytest.mark.asyncio
async def test_search_prices_live_success():
    provider = GovernmentMarketPriceProvider()
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "status": "ok",
        "total": 1,
        "count": 1,
        "records": [
            {
                "state": "Tamil Nadu",
                "district": "Madurai",
                "market": "Madurai",
                "commodity": "Paddy",
                "variety": "Common",
                "grade": "FAQ",
                "arrival_date": "09/10/2026",
                "min_price": "2000",
                "max_price": "2400",
                "modal_price": "2200",
            }
        ],
    }

    with patch("httpx.AsyncClient.get", new=AsyncMock(return_value=mock_response)):
        res = await provider.search_prices(commodity="Paddy", district="Madurai")
        assert res["live"] is True
        assert res["count"] == 1
        assert len(res["records"]) == 1
        assert res["records"][0]["commodity"] == "Paddy"
        assert res["records"][0]["modal_price_paise"] == 220000


@pytest.mark.asyncio
async def test_search_prices_timeout_handling():
    provider = GovernmentMarketPriceProvider()
    with patch("httpx.AsyncClient.get", side_effect=httpx.TimeoutException("Read timed out")):
        res = await provider.search_prices(commodity="Paddy")
        assert res["live"] is False
        assert res["count"] == 0
        assert "timed out" in res["message"].lower()


@pytest.mark.asyncio
async def test_search_prices_connection_refused_handling():
    provider = GovernmentMarketPriceProvider()
    with patch("httpx.AsyncClient.get", side_effect=httpx.ConnectError("Connection refused")):
        res = await provider.search_prices(commodity="Paddy")
        assert res["live"] is False
        assert res["count"] == 0
        assert "unreachable" in res["message"].lower()


def test_api_endpoint_market_prices_cached_fallback(test_client):
    client, mock_db = test_client

    # Upstream fails (live=False)
    mock_live_fail = {
        "records": [],
        "count": 0,
        "total": 0,
        "live": False,
        "message": "Government market API server is currently unreachable.",
    }

    # DB has cached records
    cached_record = {
        "id": "6705db85e123456789abcdef",
        "commodity": "Paddy",
        "market": "Madurai",
        "state": "Tamil Nadu",
        "district": "Madurai",
        "variety": "Common",
        "grade": "FAQ",
        "min_price_paise": 200000,
        "max_price_paise": 240000,
        "modal_price_paise": 220000,
        "modal_price_verified": True,
        "min_price_display": "₹2,000.00",
        "max_price_display": "₹2,400.00",
        "modal_price_display": "₹2,200.00",
        "price_per_kg_paise": 2200,
        "price_per_kg_display": "₹22.00 / kg",
        "unit": "Quintal",
        "arrival_date": "2026-10-09",
        "source": "data.gov.in AGMARKNET",
        "retrieved_at": "2026-10-09T06:00:00Z",
    }

    with patch("app.api.v1.market_prices.market_price_provider.search_prices",
               new=AsyncMock(return_value=mock_live_fail)):
        with patch("app.repositories.pricing.PricingRepository.list_market_prices",
                   new=AsyncMock(return_value=[cached_record])):
            response = client.get("/api/v1/market-prices?commodity=Paddy&district=Madurai")
            assert response.status_code == 200
            data = response.json()
            assert data["success"] is True
            assert data["data"]["live"] is False
            assert data["data"]["count"] == 1
            assert "cached" in data["data"]["source"].lower()
            assert data["data"]["records"][0]["commodity"] == "Paddy"
            assert data["data"]["records"][0]["price_per_kg_display"] == "₹22.00 / kg"


def test_api_endpoint_market_prices_empty_state(test_client):
    client, mock_db = test_client

    mock_live_fail = {
        "records": [],
        "count": 0,
        "total": 0,
        "live": False,
        "message": "Government market API server is currently unreachable.",
    }

    with patch("app.api.v1.market_prices.market_price_provider.search_prices",
               new=AsyncMock(return_value=mock_live_fail)):
        with patch("app.repositories.pricing.PricingRepository.list_market_prices",
                   new=AsyncMock(return_value=[])):
            response = client.get("/api/v1/market-prices?commodity=UnknownCrop")
            assert response.status_code == 503
            data = response.json()
            assert data["success"] is False
            assert data["error"]["code"] == "MARKET_SOURCE_UNAVAILABLE"
            assert data["data"]["live"] is False
            assert data["data"]["count"] == 0
            assert data["data"]["records"] == []
            assert "unreachable" in data["data"]["message"].lower()


def test_api_endpoint_filter_options(test_client):
    client, _ = test_client
    response = client.get("/api/v1/market-prices/filter-options")
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert "Paddy" in data["data"]["commodities"]
    assert "Madurai" in data["data"]["districts"]
    assert data["data"]["default_state"] == "Tamil Nadu"


def test_api_credentials_never_exposed(test_client):
    client, _ = test_client
    response = client.get("/api/v1/market-prices")
    content = response.text
    # Ensure key prefix or full key is never in content
    assert "579b464" not in content
    assert "api-key" not in content.lower()


def test_api_excludes_unverified_legacy_cache(test_client):
    client, _ = test_client
    legacy = {"commodity": "Paddy", "market": "Madurai", "modal_price_paise": 220000, "source": "data.gov.in AGMARKNET", "unit": "Quintal", "arrival_date": "2026-10-09"}
    with patch("app.api.v1.market_prices.market_price_provider.search_prices", AsyncMock(return_value={"live": False, "records": []})), patch("app.repositories.pricing.PricingRepository.list_market_prices", AsyncMock(return_value=[legacy])):
        result = client.get("/api/v1/market-prices").json()["data"]
        assert result["count"] == 0 and result["records"] == []
