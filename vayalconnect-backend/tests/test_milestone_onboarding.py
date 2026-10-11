from tests.conftest import complete_farmer
"""Focused contracts and provenance checks. Provider responses are synthetic fixtures."""
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, MagicMock, patch
import pytest
from pydantic import ValidationError as SchemaError
from app.schemas.farmer import FarmerApplicationRequest
from app.schemas.order import CreateOrderRequest
from app.schemas.product import CreateProductRequest
from app.services.pricing_service import PricingEngine
from app.services.onboarding_service import OnboardingService
from app.core.exceptions import MarketPriceUnavailableError, ValidationError, ConflictError
from app.integrations.government_market import GovernmentMarketPriceProvider


def reference(**changes):
    return {"commodity": "Paddy", "market": "Madurai", "modal_price_paise": 300000,
            "modal_price_verified": True, "unit": "Quintal", "arrival_date": datetime.now(timezone.utc).date().isoformat(),
            "source": "data.gov.in AGMARKNET", "retrieved_at": datetime.now(timezone.utc), **changes}


@pytest.mark.asyncio
@pytest.mark.parametrize("unit,converted", [("KG", 3000), ("QUINTAL", 300000), ("TON", 3000000)])
async def test_selected_price_is_never_replaced_by_unit_aware_reference(unit, converted):
    engine = PricingEngine(MagicMock())
    engine.pricing_repo.store_market_price = AsyncMock()
    engine.pricing_repo.get_active_commission = AsyncMock(return_value={"id": "configuration", "version": 2, "commission_percentage_bps": 1500})
    with patch("app.services.pricing_service.market_price_provider.get_market_price", AsyncMock(return_value=reference())):
        snapshot = await engine.calculate_pricing("Paddy", "Grains", 3, unit, "A", "Madurai", "Madurai", "farmer", selling_price_per_unit_paise=4321)
    assert snapshot["farmer_payout_per_unit_paise"] == 4321
    assert snapshot["reference_price_per_listing_unit_paise"] == converted
    assert snapshot["commission_per_unit_paise"] == 648
    assert snapshot["buyer_price_per_unit_paise"] == 4969
    assert snapshot["buyer_total_paise"] == snapshot["farmer_total_payout_paise"] + snapshot["commission_total_paise"]


@pytest.mark.asyncio
@pytest.mark.parametrize("changes", [{"commodity": "Other"}, {"market": "Other"}, {"source": "unverified"}, {"arrival_date": None}, {"arrival_date": "2999-01-01"}, {"modal_price_paise": 0}, {"modal_price_verified": False}])
async def test_unverifiable_reference_fails_closed(changes):
    engine = PricingEngine(MagicMock())
    engine.pricing_repo.get_latest_market_price = AsyncMock(return_value=None)
    with patch("app.services.pricing_service.market_price_provider.get_market_price", AsyncMock(return_value=reference(**changes))):
        with pytest.raises(MarketPriceUnavailableError): await engine.get_verified_reference("Paddy", "Madurai", "KG")


@pytest.mark.asyncio
async def test_cached_historical_reference_is_explicit_and_count_units_cannot_use_weight_prices():
    engine = PricingEngine(MagicMock())
    engine.pricing_repo.get_latest_market_price = AsyncMock(return_value=reference(arrival_date=(datetime.now(timezone.utc).date() - timedelta(days=7)).isoformat()))
    with patch("app.services.pricing_service.market_price_provider.get_market_price", AsyncMock(return_value=None)):
        result = await engine.get_verified_reference("Paddy", "Madurai", "KG")
        assert result["reference_price_cached"] and result["reference_price_stale"]
        with pytest.raises(ValidationError): await engine.get_verified_reference("Paddy", "Madurai", "PIECE")


def test_missing_modal_is_not_invented():
    result = GovernmentMarketPriceProvider()._normalize_record({"commodity": "Paddy", "market": "Madurai", "min_price": "2000", "max_price": "4000"})
    assert result["modal_price_paise"] == 0 and not result["modal_price_verified"]


@pytest.mark.parametrize("price", [0, -1, True, 1.2, "1200", 100000001])
def test_price_validation_rejects_coercion_and_limits(price):
    with pytest.raises(SchemaError):
        CreateProductRequest(product_name="Paddy", category="Grains", quantity=2, quantity_unit="KG", quality_grade="A", location="Madurai", market="Madurai", harvest_date="2026-10-10", selling_price_per_unit_paise=price)


def test_application_is_complete_and_cannot_self_approve():
    application = dict(farm_name="Test farm", farm_address="10 Test farm road", pickup_address="10 Pickup farm road", crops="Paddy")
    assert FarmerApplicationRequest(**application).application_revision == 0
    for invalid in ({"farm_name": "  "}, complete_farmer(), {"delivery_available": "true"}):
        with pytest.raises(SchemaError): FarmerApplicationRequest(**(application | invalid))


@pytest.mark.parametrize("payload", [
    {"fulfillment_method": "DELIVERY"}, {"fulfillment_method": "UNKNOWN"},
    {"fulfillment_method": "PICKUP", "delivery_address": {"recipient_name": "Test", "phone": "9876543210", "address": "10 Test buyer road", "postal_code": "625001"}},
    {"fulfillment_method": "PICKUP", "buyer_total_paise": 1},
])
def test_fulfillment_and_client_money_are_validated(payload):
    with pytest.raises(SchemaError): CreateOrderRequest(product_id="product", quantity=1, **payload)


@pytest.mark.asyncio
async def test_approval_requires_submitted_verified_application_and_current_revision():
    service = OnboardingService(MagicMock())
    service.farmers.find_by_user_id = AsyncMock(return_value={"approval_status": "PENDING"})
    service.users.find_by_id = AsyncMock(return_value={"role": "FARMER", "is_active": True, "email_verified": True})
    service.farmers.decide_application = AsyncMock(return_value=False)
    with pytest.raises(ValidationError): await service.decide("farmer", 0, "admin", True)
    service.farmers.decide_application.assert_not_awaited()
    service.farmers.find_by_user_id = AsyncMock(return_value=complete_farmer(submitted_at=datetime.now(timezone.utc)))
    with pytest.raises(ConflictError): await service.decide("farmer", 1, "admin", True)


@pytest.mark.asyncio
async def test_post_insert_audit_failure_never_restores_reserved_inventory(monkeypatch):
    monkeypatch.setattr("app.repositories.pricing.PricingRepository.get_active_commission", AsyncMock(return_value=None))
    from app.services.order_service import OrderService
    service = OrderService(MagicMock())
    product = {"farmer_id": "farmer", "product_name": "Paddy", "quantity_available": 3, "location": "Madurai", "buyer_price_per_unit_paise": 120, "farmer_payout_per_unit_paise": 100, "commission_per_unit_paise": 20, "commission_percentage": 2000}
    service.product_repo.find_active_by_id = AsyncMock(return_value=product)
    service.product_repo.atomic_reserve_quantity = AsyncMock(return_value=product)
    service.product_repo.restore_quantity = AsyncMock()
    service.user_repo.find_by_id = AsyncMock(return_value={"name": "Test"})
    service.order_repo.generate_order_number = AsyncMock(return_value="TEST-1")
    service.order_repo.create = AsyncMock(return_value="order")
    service.audit_service.log = AsyncMock(side_effect=RuntimeError("synthetic audit failure"))
    with patch("app.repositories.farmers.FarmerRepository.find_by_user_id", AsyncMock(return_value=complete_farmer())):
        with pytest.raises(RuntimeError): await service.create_order("buyer", "product", 1)
    service.order_repo.create.assert_awaited_once()
    service.product_repo.restore_quantity.assert_not_awaited()


def test_bank_account_must_be_digits_and_verification_is_not_client_controlled():
    from app.schemas.farmer import FarmerBankDetailsRequest
    data = dict(account_holder_name="Test Farmer", bank_name="Test Bank", account_number="123456789012", ifsc="TEST0123456")
    assert FarmerBankDetailsRequest(**data).account_number == "123456789012"
    for changes in ({"account_number": "ABCDEFGH"}, {"bank_details_verified": True}):
        with pytest.raises(SchemaError): FarmerBankDetailsRequest(**(data | changes))
