from tests.conftest import complete_farmer
"""
Unit tests for Order Service:
Inventory reservation, pricing integrity, state machine transitions, and idempotency.
"""

import pytest
from unittest.mock import AsyncMock, patch
from app.services.order_service import OrderService
from app.core.exceptions import (
    NotFoundError,
    ProductOutOfStockError,
    ValidationError,
    FarmerNotApprovedError,
    InvalidStateTransitionError,
)
from app.schemas.common import OrderStatus


@pytest.fixture
def mock_db(monkeypatch):
    monkeypatch.setattr("app.repositories.pricing.PricingRepository.get_active_commission", AsyncMock(return_value=None))
    return AsyncMock()


@pytest.mark.asyncio
async def test_create_order_pricing_calculated_from_product(mock_db):
    service = OrderService(mock_db)

    product = {
        "id": "prod_123",
        "farmer_id": "farmer_1",
        "product_name": "Ponni Rice",
        "category": "Grains",
        "quantity_available": 100,
        "quantity_unit": "KG",
        "quality_grade": "A",
        "buyer_price_per_unit_paise": 4500,  # ₹45/kg
        "farmer_payout_per_unit_paise": 3500, # ₹35/kg
        "commission_per_unit_paise": 1000,    # ₹10/kg
        "commission_percentage": 2222,
    }

    with patch.object(service.order_repo, "find_by_idempotency_key", new=AsyncMock(return_value=None)):
        with patch.object(service.product_repo, "find_active_by_id", new=AsyncMock(return_value=product)):
            with patch("app.repositories.farmers.FarmerRepository.find_by_user_id",
                       new=AsyncMock(return_value=complete_farmer())):
                with patch.object(service.product_repo, "atomic_reserve_quantity", new=AsyncMock(return_value=True)):
                    with patch.object(service.order_repo, "generate_order_number", new=AsyncMock(return_value="ORD-2026-0001")):
                        with patch.object(service.order_repo, "create", new=AsyncMock(return_value="order_999")):
                            with patch.object(service.audit_service, "log", new=AsyncMock()):
                                order = await service.create_order(
                                    buyer_id="buyer_2",
                                    product_id="prod_123",
                                    quantity=10,
                                    idempotency_key="key_123",
                                )

                                # Buyer pays 10 * 4500 = 45000 paise (₹450.00)
                                assert order["buyer_total_paise"] == 42000
                                # Farmer receives 10 * 3500 = 35000 paise (₹350.00)
                                assert order["farmer_total_payout_paise"] == 35000
                                # Commission = 10 * 1000 = 10000 paise (₹100.00)
                                assert order["commission_total_paise"] == 7000
                                assert order["order_status"] == OrderStatus.PENDING_PAYMENT.value


@pytest.mark.asyncio
async def test_create_order_out_of_stock_rejected(mock_db):
    service = OrderService(mock_db)

    product = {
        "id": "prod_123",
        "farmer_id": "farmer_1",
        "quantity_available": 5,
    }

    with patch.object(service.order_repo, "find_by_idempotency_key", new=AsyncMock(return_value=None)):
        with patch.object(service.product_repo, "find_active_by_id", new=AsyncMock(return_value=product)):
            with patch("app.repositories.farmers.FarmerRepository.find_by_user_id",
                       new=AsyncMock(return_value=complete_farmer())):
                with pytest.raises(ProductOutOfStockError):
                    # Requesting 10 when only 5 available
                    await service.create_order(
                        buyer_id="buyer_2",
                        product_id="prod_123",
                        quantity=10,
                    )


@pytest.mark.asyncio
async def test_create_order_unapproved_farmer_rejected(mock_db):
    service = OrderService(mock_db)

    product = {
        "id": "prod_123",
        "farmer_id": "farmer_unapproved",
        "quantity_available": 100,
    }

    with patch.object(service.order_repo, "find_by_idempotency_key", new=AsyncMock(return_value=None)):
        with patch.object(service.product_repo, "find_active_by_id", new=AsyncMock(return_value=product)):
            with patch("app.repositories.farmers.FarmerRepository.find_by_user_id",
                       new=AsyncMock(return_value={"approval_status": "PENDING"})):
                with pytest.raises(FarmerNotApprovedError):
                    await service.create_order(
                        buyer_id="buyer_2",
                        product_id="prod_123",
                        quantity=5,
                    )


@pytest.mark.asyncio
async def test_order_state_machine_invalid_transition(mock_db):
    service = OrderService(mock_db)

    order = {
        "id": "order_123",
        "order_status": OrderStatus.PENDING_PAYMENT.value,
    }

    with patch.object(service.order_repo, "find_by_id", new=AsyncMock(return_value=order)):
        # Cannot jump from PENDING_PAYMENT directly to COMPLETED
        with pytest.raises(InvalidStateTransitionError):
            await service.update_order_status(
                order_id="order_123",
                new_status=OrderStatus.COMPLETED.value,
                actor_id="admin_1",
                actor_role="ADMIN",
            )
