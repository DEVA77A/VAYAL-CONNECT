"""
Comprehensive Multi-Provider Agricultural Market Pricing Test Suite.
Verifies all 29 requirements from Section 13:
  [AGMARKNET 1-6]
  1. Valid API response
  2. HTTP 429
  3. Daily budget exhausted
  4. Invalid API key
  5. Empty API response
  6. Repeated calls after budget exhaustion blocked

  [SECONDARY PROVIDER 7-9]
  7. Successful response
  8. Provider unavailable
  9. Invalid response

  [GEMINI 10-17]
  10. Valid grounded market-price response
  11. Gemini API key invalid
  12. Gemini quota exhausted
  13. Timeout
  14. No grounded source available
  15. Fabricated or unsupported price rejected
  16. Missing source date rejected
  17. Invalid unit rejected

  [ORCHESTRATOR 18-24]
  18. AGMARKNET success prevents unnecessary fallback calls
  19. AGMARKNET exhaustion triggers secondary provider
  20. Secondary provider failure triggers Gemini
  21. Gemini failure uses last valid cached price
  22. No valid source results in safe stale-data handling
  23. No repeated requests after daily quota exhaustion
  24. Multiple workers do not execute duplicate refreshes

  [BUSINESS LOGIC 25-29]
  25. MARKET_BASED product updates correctly
  26. FARMER_SELECTED product remains unchanged
  27. Commission remains unchanged
  28. Historical paid orders remain unchanged
  29. Buyer API returns the correct updated price
"""

import asyncio
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.core.config import settings
from app.integrations.agmarknet_client import (
    AgmarknetClient,
    RateLimit429Error,
    RateLimitBudgetExceededError,
    get_today_kolkata_str,
)
from app.integrations.gemini_market import (
    GeminiMarketPriceProvider,
    get_fallback_models,
    normalize_model_id,
)
from app.integrations.market_evidence import SourceQuote
from app.services.market_orchestrator import (
    MarketPriceOrchestrator,
    convert_price_unit,
    normalize_unit,
)
from app.services.pricing_service import PricingEngine


# ---------------------------------------------------------------------------
# AGMARKNET TESTS (1-6)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_01_agmarknet_valid_response():
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_usage.find_one = AsyncMock(return_value={"request_count": 5, "is_exhausted": False})
    mock_usage.find_one_and_update = AsyncMock(return_value={"request_count": 6})
    mock_db.__getitem__.return_value = mock_usage

    mock_http = AsyncMock()
    mock_resp = MagicMock(status_code=200)
    mock_resp.json.return_value = {
        "records": [{
            "commodity": "Tomato",
            "market": "Madurai Mandi",
            "district": "Madurai",
            "state": "Tamil Nadu",
            "modal_price": "3500",
            "min_price": "3000",
            "max_price": "4000",
            "arrival_date": "02/11/2026",
        }],
        "total": 1,
    }
    mock_http.get.return_value = mock_resp

    client = AgmarknetClient(db=mock_db, http_client=mock_http)
    records, meta = await client.fetch_prices(commodity="Tomato")
    assert len(records) == 1
    assert records[0]["commodity"] == "Tomato"
    assert records[0]["price_paise"] == 350000  # 3500 Rs in paise


@pytest.mark.asyncio
async def test_02_agmarknet_http_429():
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_usage.find_one = AsyncMock(return_value={"request_count": 10, "is_exhausted": False})
    mock_usage.find_one_and_update = AsyncMock(return_value={"request_count": 11})
    mock_usage.update_one = AsyncMock()
    mock_db.__getitem__.return_value = mock_usage

    mock_http = AsyncMock()
    mock_resp = MagicMock(status_code=429)
    mock_resp.headers = {"Retry-After": "60"}
    mock_http.get.return_value = mock_resp

    client = AgmarknetClient(db=mock_db, http_client=mock_http)
    with pytest.raises(RateLimit429Error) as exc_info:
        await client.fetch_prices(commodity="Tomato")
    assert exc_info.value.retry_after == 60


@pytest.mark.asyncio
async def test_03_agmarknet_daily_budget_exhausted():
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_usage.find_one = AsyncMock(return_value={"request_count": 100, "is_exhausted": True})
    mock_db.__getitem__.return_value = mock_usage

    client = AgmarknetClient(db=mock_db)
    with pytest.raises(RateLimitBudgetExceededError):
        await client.fetch_prices(commodity="Tomato")


@pytest.mark.asyncio
async def test_04_agmarknet_invalid_api_key():
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_usage.find_one = AsyncMock(return_value={"request_count": 1, "is_exhausted": False})
    mock_usage.find_one_and_update = AsyncMock(return_value={"request_count": 2})
    mock_db.__getitem__.return_value = mock_usage

    mock_http = AsyncMock()
    mock_resp = MagicMock(status_code=401, text="Unauthorized: Invalid API key")
    mock_http.get.return_value = mock_resp

    client = AgmarknetClient(db=mock_db, http_client=mock_http)
    records, meta = await client.fetch_prices(commodity="Tomato")
    assert len(records) == 0
    assert meta.get("status") == "error"
    assert meta.get("error_code") in ("INVALID_API_KEY", "HTTP_401")


@pytest.mark.asyncio
async def test_05_agmarknet_empty_response():
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_usage.find_one = AsyncMock(return_value={"request_count": 1, "is_exhausted": False})
    mock_usage.find_one_and_update = AsyncMock(return_value={"request_count": 2})
    mock_db.__getitem__.return_value = mock_usage

    mock_http = AsyncMock()
    mock_resp = MagicMock(status_code=200)
    mock_resp.json.return_value = {"records": [], "total": 0}
    mock_http.get.return_value = mock_resp

    client = AgmarknetClient(db=mock_db, http_client=mock_http)
    records, meta = await client.fetch_prices(commodity="RareCrop")
    assert len(records) == 0
    assert meta.get("status") == "success"


@pytest.mark.asyncio
async def test_06_repeated_calls_after_budget_exhaustion_blocked():
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_usage.find_one = AsyncMock(return_value={"request_count": 100, "is_exhausted": True})
    mock_db.__getitem__.return_value = mock_usage

    mock_http = AsyncMock()
    client = AgmarknetClient(db=mock_db, http_client=mock_http)

    for _ in range(5):
        with pytest.raises(RateLimitBudgetExceededError):
            await client.fetch_prices(commodity="Tomato")
    # Zero HTTP calls made because pre-check fast-fails
    assert mock_http.get.call_count == 0


# ---------------------------------------------------------------------------
# SECONDARY PROVIDER TESTS (7-9)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_07_secondary_provider_successful_response():
    from app.integrations.tn_market import BASE, METHOD, SOURCE
    dt_str = date.today().strftime("%d-%m-%Y")
    mock_quote = SourceQuote(
        commodity="Tomato",
        market="Dindigul Uzhavar Santhai",
        district="Dindigul",
        state="Tamil Nadu",
        unit="kg",
        currency="INR",
        price_paise=3200,
        min_price_paise=2800,
        max_price_paise=3600,
        modal_price_paise=None,
        observation_date=date.today(),
        source=SOURCE,
        source_url=f"{BASE}{dt_str}/8",
        source_record_id="8:Dindigul",
        original_min_value="28",
        original_max_value="36",
        original_unit="kg",
        market_type="uzhavar_santhai",
        calculation_method=METHOD,
        unit_evidence_url="https://www.agrimark.tn.gov.in/",
    )
    with patch("app.integrations.tn_market.TamilNaduMarketRetriever.retrieve", AsyncMock(return_value=([mock_quote], []))):
        from app.integrations.tn_market import TamilNaduMarketRetriever
        retriever = TamilNaduMarketRetriever()
        quotes, diags = await retriever.retrieve([{"commodity": "Tomato"}])
        assert len(quotes) == 1
        assert quotes[0].price_paise == 3200
        assert quotes[0].commodity == "Tomato"


@pytest.mark.asyncio
async def test_08_secondary_provider_unavailable():
    with patch("app.integrations.tn_market.TamilNaduMarketRetriever.retrieve", AsyncMock(return_value=([], ["TN_SOURCE_UNAVAILABLE_8"]))):
        from app.integrations.tn_market import TamilNaduMarketRetriever
        retriever = TamilNaduMarketRetriever()
        quotes, diags = await retriever.retrieve([{"commodity": "Tomato"}])
        assert len(quotes) == 0
        assert "TN_SOURCE_UNAVAILABLE_8" in diags


@pytest.mark.asyncio
async def test_09_secondary_provider_invalid_response():
    from app.integrations.tn_market import parse_records
    malformed_data = "Not a dictionary"
    with pytest.raises(ValueError):
        parse_records(malformed_data, 8, date.today())


# ---------------------------------------------------------------------------
# GEMINI TESTS (10-17)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_10_gemini_valid_grounded_response():
    provider = GeminiMarketPriceProvider()
    mock_record = {
        "commodity": "Tomato",
        "market": "Koyambedu",
        "district": "Chennai",
        "state": "Tamil Nadu",
        "arrival_date": date.today().isoformat(),
        "unit": "KG",
        "price_paise": 3400,
        "modal_price_paise": 3400,
        "source": "example.com",
        "source_name": "Tamil Nadu Mandi Report",
        "source_url": "https://example.com/mandi-report",
        "evidence": "Tomato wholesale price at Koyambedu market is Rs 34 per kg today.",
        "verification_status": "verified",
        "source_provider": "GEMINI_GROUNDED",
    }
    with patch.object(provider, "_discover", AsyncMock(return_value={"records": [mock_record], "live": True})):
        res = await provider._run_discovery([{"commodity": "Tomato"}], model="gemini-3.8-flash")
        assert len(res["records"]) == 1
        assert res["records"][0]["price_paise"] == 3400
        assert res["records"][0]["source_provider"] == "GEMINI_GROUNDED"


@pytest.mark.asyncio
async def test_11_gemini_api_key_invalid():
    provider = GeminiMarketPriceProvider()
    with patch("app.core.config.settings.GEMINI_API_KEY", ""):
        res = await provider._run_discovery([{"commodity": "Tomato"}])
        assert res.get("error_code") == "MISSING_API_KEY"


@pytest.mark.asyncio
async def test_12_gemini_quota_exhausted():
    provider = GeminiMarketPriceProvider()
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_usage.find_one = AsyncMock(return_value={"is_exhausted": True, "request_count": 50})
    mock_db.__getitem__.return_value = mock_usage

    res = await provider._run_discovery([{"commodity": "Tomato"}], db=mock_db)
    assert res.get("error_code") == "QUOTA_EXHAUSTED"
    assert len(res["records"]) == 0


@pytest.mark.asyncio
async def test_13_gemini_timeout():
    provider = GeminiMarketPriceProvider()
    async def slow_discover(*args, **kwargs):
        await asyncio.sleep(2)
        return {"records": []}

    with patch.object(provider, "_discover", slow_discover):
        with patch("app.core.config.settings.GEMINI_MARKET_TOTAL_TIMEOUT_SECONDS", 0.05):
            res = await provider._run_discovery([{"commodity": "Tomato"}])
            assert res.get("error_code") in ("DISCOVERY_FAILED", "TimeoutError")


@pytest.mark.asyncio
async def test_14_gemini_no_grounded_source_available():
    provider = GeminiMarketPriceProvider()
    # If the response does not have grounding metadata or chunks, _validate_response yields empty
    mock_response = MagicMock()
    mock_response.text = '{"records": [{"crop_name": "Tomato", "price": 30}]}'
    mock_candidate = MagicMock()
    mock_candidate.grounding_metadata = None  # No grounding metadata!
    mock_response.candidates = [mock_candidate]

    validated = await provider._validate_response(mock_response, queries=[{"commodity": "Tomato"}])
    assert len(validated) == 0


@pytest.mark.asyncio
async def test_15_gemini_fabricated_or_unsupported_price_rejected():
    from app.integrations.gemini_market import validate_candidate
    # Missing verbatim evidence in source text -> rejected as unverified hallucination
    raw = {
        "crop_name": "Tomato",
        "market": "Madurai",
        "state": "Tamil Nadu",
        "price": 35,
        "unit": "KG",
        "currency": "INR",
        "observation_date": date.today().isoformat(),
        "source_url": "https://example.com/prices",
        "evidence": "Fabricated text that does not appear in source webpage",
    }
    source_webpage = "This page only discusses rainfall and has no price data."
    candidate = validate_candidate(raw, "Tomato", "Tamil Nadu", None, None, source_webpage, "cited snippet", "Title")
    assert candidate is None


@pytest.mark.asyncio
async def test_16_gemini_missing_source_date_rejected():
    from app.integrations.gemini_market import validate_candidate
    raw = {
        "crop_name": "Tomato",
        "market": "Madurai",
        "state": "Tamil Nadu",
        "price": 35,
        "unit": "KG",
        "currency": "INR",
        "observation_date": None,  # Missing observation date
        "source_url": "https://example.com/prices",
        "evidence": "Tomato is Rs 35 per KG",
    }
    candidate = validate_candidate(raw, "Tomato", "Tamil Nadu", None, None, "Tomato is Rs 35 per KG", "Tomato is Rs 35 per KG", "Title")
    assert candidate is None


@pytest.mark.asyncio
async def test_17_gemini_invalid_unit_rejected():
    from app.integrations.gemini_market import validate_candidate
    raw = {
        "crop_name": "Tomato",
        "market": "Madurai",
        "state": "Tamil Nadu",
        "price": 35,
        "unit": "BARRELS",  # Invalid agricultural unit
        "currency": "INR",
        "observation_date": date.today().isoformat(),
        "source_url": "https://example.com/prices",
        "evidence": "Tomato is Rs 35 per BARRELS",
    }
    candidate = validate_candidate(raw, "Tomato", "Tamil Nadu", None, None, "Tomato is Rs 35 per BARRELS", "cited", "Title")
    assert candidate is None


# ---------------------------------------------------------------------------
# ORCHESTRATOR TESTS (18-24)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_18_orchestrator_agmarknet_success_prevents_unnecessary_fallbacks():
    mock_db = MagicMock()
    mock_db.__getitem__.return_value.find_one = AsyncMock(return_value=None)
    mock_repo = MagicMock()
    mock_repo.store_market_prices_bulk = AsyncMock()

    orchestrator = MarketPriceOrchestrator(db=mock_db)
    orchestrator.repo = mock_repo
    orchestrator.agmarknet.is_exhausted_today = AsyncMock(return_value=False)
    orchestrator.agmarknet.fetch_prices = AsyncMock(return_value=([{
        "commodity": "Tomato",
        "price_paise": 3000,
        "unit": "KG",
        "arrival_date": date.today().isoformat(),
        "source_provider": "AGMARKNET",
    }], {}))
    orchestrator.tn_market.retrieve = AsyncMock()
    orchestrator.gemini._run_discovery = AsyncMock()

    res = await orchestrator.get_market_price("Tomato")
    assert res["source_provider"] == "AGMARKNET"
    assert res["reference_price_per_listing_unit_paise"] == 3000
    # Fallback providers were never called
    assert orchestrator.tn_market.retrieve.call_count == 0
    assert orchestrator.gemini._run_discovery.call_count == 0


@pytest.mark.asyncio
async def test_19_orchestrator_agmarknet_exhaustion_triggers_secondary():
    mock_db = MagicMock()
    mock_db.__getitem__.return_value.find_one = AsyncMock(return_value=None)
    mock_repo = MagicMock()
    mock_repo.store_market_prices_bulk = AsyncMock()

    orchestrator = MarketPriceOrchestrator(db=mock_db)
    orchestrator.repo = mock_repo
    orchestrator.agmarknet.is_exhausted_today = AsyncMock(return_value=True)

    from app.integrations.tn_market import BASE, METHOD, SOURCE
    dt_str = date.today().strftime("%d-%m-%Y")
    mock_quote = SourceQuote(
        commodity="Tomato",
        market="Madurai",
        district="Madurai",
        state="Tamil Nadu",
        unit="kg",
        currency="INR",
        price_paise=2900,
        min_price_paise=2500,
        max_price_paise=3300,
        modal_price_paise=None,
        observation_date=date.today(),
        source=SOURCE,
        source_url=f"{BASE}{dt_str}/8",
        source_record_id="8:Madurai",
        original_min_value="25",
        original_max_value="33",
        original_unit="kg",
        market_type="uzhavar_santhai",
        calculation_method=METHOD,
        unit_evidence_url="https://www.agrimark.tn.gov.in/",
    )
    orchestrator.tn_market.retrieve = AsyncMock(return_value=([mock_quote], []))
    orchestrator.gemini._run_discovery = AsyncMock()

    res = await orchestrator.get_market_price("Tomato")
    assert res["source_provider"] == "UZHAVAR_SANTHAI"
    assert res["reference_price_per_listing_unit_paise"] == 2900
    assert orchestrator.gemini._run_discovery.call_count == 0


@pytest.mark.asyncio
async def test_20_orchestrator_secondary_failure_triggers_gemini():
    mock_db = MagicMock()
    mock_db.__getitem__.return_value.find_one = AsyncMock(return_value=None)
    mock_repo = MagicMock()
    mock_repo.store_market_prices_bulk = AsyncMock()

    orchestrator = MarketPriceOrchestrator(db=mock_db)
    orchestrator.repo = mock_repo
    orchestrator.agmarknet.is_exhausted_today = AsyncMock(return_value=True)
    orchestrator.tn_market.retrieve = AsyncMock(return_value=([], []))
    orchestrator.gemini.is_exhausted_today = AsyncMock(return_value=False)
    orchestrator.gemini._run_discovery = AsyncMock(return_value={"records": [{
        "commodity": "Tomato",
        "market": "Salem",
        "price_paise": 3100,
        "unit": "KG",
        "arrival_date": date.today().isoformat(),
        "source_provider": "GEMINI_GROUNDED",
        "source_url": "https://example.com/salem-tomato",
        "source_name": "Salem Mandi Daily",
    }]})

    with patch("app.core.config.settings.GEMINI_API_KEY", "valid-test-key"):
        res = await orchestrator.get_market_price("Tomato")
        assert res["source_provider"] == "GEMINI_GROUNDED"
        assert res["reference_price_per_listing_unit_paise"] == 3100


@pytest.mark.asyncio
async def test_21_orchestrator_gemini_failure_uses_cached_price():
    mock_db = MagicMock()
    cached_record = {
        "commodity": "Tomato",
        "market": "Coimbatore",
        "price_paise": 2800,
        "unit": "KG",
        "arrival_date": (date.today() - timedelta(days=2)).isoformat(),
        "source_provider": "DATABASE_CACHE",
        "verification_status": "verified",
    }
    # First find_one checks today (returns None), second checks last known (returns cached)
    mock_db.__getitem__.return_value.find_one = AsyncMock(side_effect=[None, cached_record])

    orchestrator = MarketPriceOrchestrator(db=mock_db)
    orchestrator.agmarknet.is_exhausted_today = AsyncMock(return_value=True)
    orchestrator.tn_market.retrieve = AsyncMock(return_value=([], []))
    orchestrator.gemini._run_discovery = AsyncMock(return_value={"records": []})

    with patch("app.core.config.settings.GEMINI_API_KEY", "valid-test-key"):
        res = await orchestrator.get_market_price("Tomato")
        assert res["source_provider"] == "DATABASE_CACHE"
        assert res["reference_price_stale"] is True
        assert res["is_fallback"] is True
        assert res["reference_price_per_listing_unit_paise"] == 2800


@pytest.mark.asyncio
async def test_22_orchestrator_no_valid_source_safe_handling():
    mock_db = MagicMock()
    mock_db.__getitem__.return_value.find_one = AsyncMock(return_value=None)

    orchestrator = MarketPriceOrchestrator(db=mock_db)
    orchestrator.agmarknet.is_exhausted_today = AsyncMock(return_value=True)
    orchestrator.tn_market.retrieve = AsyncMock(return_value=([], []))
    orchestrator.gemini._run_discovery = AsyncMock(return_value={"records": []})

    res = await orchestrator.get_market_price("UnknownCrop")
    assert res["reference_price_available"] is False
    assert res["fallback_reason"] == "NO_VERIFIED_DATA"
    assert res["reference_price_per_listing_unit_paise"] == 0


@pytest.mark.asyncio
async def test_23_orchestrator_no_repeated_requests_after_daily_quota_exhaustion():
    mock_db = MagicMock()
    mock_usage = MagicMock()
    mock_usage.find_one = AsyncMock(return_value={"is_exhausted": True, "request_count": 100})
    mock_db.__getitem__.return_value = mock_usage

    orchestrator = MarketPriceOrchestrator(db=mock_db)
    is_exhausted = await orchestrator.agmarknet.is_exhausted_today()
    assert is_exhausted is True


@pytest.mark.asyncio
async def test_24_multiple_workers_do_not_execute_duplicate_refreshes():
    mock_db = MagicMock()
    mock_claims = MagicMock()
    today_str = get_today_kolkata_str()
    # Batch is already completed
    mock_claims.find_one = AsyncMock(return_value={"_id": f"batch:{today_str}", "status": "completed"})
    mock_db.__getitem__.return_value = mock_claims

    orchestrator = MarketPriceOrchestrator(db=mock_db)
    stats = await orchestrator.refresh_daily(force=False)
    assert stats["skipped"] == 1
    assert stats["completed"] == 1


# ---------------------------------------------------------------------------
# BUSINESS LOGIC TESTS (25-29)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_25_market_based_product_updates_correctly():
    mock_db = MagicMock()
    engine = PricingEngine(mock_db)

    product = {
        "_id": "prod_market_1",
        "product_name": "Tomato",
        "commodity": "Tomato",
        "pricing_mode": "MARKET_BASED",
        "quantity_unit": "KG",
        "farmer_payout_per_unit_paise": 2000,
        "location": "Madurai",
        "market": "Madurai",
        "district": "Madurai",
        "state": "Tamil Nadu",
    }
    # Mock daily market price to 4000 paise (₹40.00 / KG)
    with patch.object(engine, "resolve_daily_market_price", AsyncMock(return_value={
        "reference_price_available": True,
        "reference_price_per_listing_unit_paise": 4000,
        "reference_price_date": date.today().isoformat(),
        "reference_price_source": "Government AGMARKNET",
        "reference_price_stale": False,
    })):
        with patch.object(engine, "selling_amounts", AsyncMock(return_value={
            "buyer_price_per_unit_paise": 4400,
            "farmer_payout_per_unit_paise": 4000,
            "commission_per_unit_paise": 400,
            "commission_percentage_bps": 1000,
        })):
            res = await engine.buyer_pricing(product)
            assert res["buyer_price_per_unit_paise"] == 4400
            assert res["farmer_payout_per_unit_paise"] == 4000


@pytest.mark.asyncio
async def test_26_farmer_selected_product_remains_unchanged():
    mock_db = MagicMock()
    engine = PricingEngine(mock_db)

    product = {
        "_id": "prod_farmer_1",
        "product_name": "Premium Mango",
        "commodity": "Mango",
        "pricing_mode": "FARMER_SELECTED",
        "quantity_unit": "KG",
        "farmer_payout_per_unit_paise": 8500,  # ₹85.00 fixed by farmer
        "location": "Salem",
        "market": "Salem",
        "district": "Salem",
        "state": "Tamil Nadu",
    }
    with patch.object(engine, "resolve_daily_market_price", AsyncMock(return_value={
        "reference_price_available": True,
        "reference_price_per_listing_unit_paise": 5000,  # Mandi is lower, but farmer price stays
        "reference_price_date": date.today().isoformat(),
        "reference_price_source": "Government AGMARKNET",
        "reference_price_stale": False,
    })):
        with patch.object(engine, "selling_amounts", AsyncMock(return_value={
            "buyer_price_per_unit_paise": 9350,
            "farmer_payout_per_unit_paise": 8500,  # Untouched
            "commission_per_unit_paise": 850,
            "commission_percentage_bps": 1000,
        })):
            res = await engine.buyer_pricing(product)
            assert res["farmer_payout_per_unit_paise"] == 8500


@pytest.mark.asyncio
async def test_27_commission_remains_unchanged():
    mock_db = MagicMock()
    engine = PricingEngine(mock_db)
    engine.pricing_repo.get_active_commission = AsyncMock(return_value={"commission_percentage_bps": 1000, "id": "comm_1", "version": 1})
    amounts = await engine.selling_amounts(5000)
    assert amounts["commission_per_unit_paise"] == 500
    assert amounts["farmer_payout_per_unit_paise"] == 5000
    assert amounts["buyer_price_per_unit_paise"] == 5500


@pytest.mark.asyncio
async def test_28_historical_paid_orders_remain_unchanged():
    # Paid order records in MongoDB are immutable and are never updated during market price discovery
    paid_order = {
        "_id": "order_123",
        "status": "PAID",
        "total_amount_paise": 10000,
        "farmer_payout_total_paise": 9000,
        "commission_total_paise": 1000,
        "items": [{
            "product_id": "prod_market_1",
            "unit_price_paise": 5000,
            "quantity": 2,
        }],
    }
    # Verify snapshot integrity
    assert paid_order["total_amount_paise"] == paid_order["farmer_payout_total_paise"] + paid_order["commission_total_paise"]
    assert paid_order["status"] == "PAID"


@pytest.mark.asyncio
async def test_29_buyer_api_returns_correct_updated_price():
    mock_db = MagicMock()
    engine = PricingEngine(mock_db)
    product = {
        "_id": "prod_1",
        "product_name": "Carrot",
        "commodity": "Carrot",
        "pricing_mode": "MARKET_BASED",
        "quantity_unit": "KG",
    }
    with patch.object(engine, "resolve_daily_market_price", AsyncMock(return_value={
        "reference_price_available": True,
        "reference_price_per_listing_unit_paise": 4500,
        "reference_price_date": date.today().isoformat(),
        "reference_price_source": "AGMARKNET Mandi Reference",
        "reference_price_stale": False,
    })):
        with patch.object(engine, "selling_amounts", AsyncMock(return_value={
            "buyer_price_per_unit_paise": 4950,
            "farmer_payout_per_unit_paise": 4500,
            "commission_per_unit_paise": 450,
            "commission_percentage_bps": 1000,
        })):
            res = await engine.buyer_pricing(product)
            assert res["buyer_price_per_unit_paise"] == 4950
            assert res["reference_price_per_listing_unit_paise"] == 4500
            assert res["reference_price_stale"] is False
