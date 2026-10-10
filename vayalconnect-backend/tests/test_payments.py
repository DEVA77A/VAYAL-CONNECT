"""
Unit tests for Payment & Payout services:
Razorpay order creation, signature validation, idempotent processing, and admin payout approval.
"""

import pytest
from unittest.mock import AsyncMock, patch
from app.services.payment_service import PaymentService
from app.services.payout_service import PayoutService
from app.core.exceptions import (
    NotFoundError,
    ForbiddenError,
    PaymentVerificationFailedError,
    PaymentAlreadyVerifiedError,
    InvalidStateTransitionError,
)
from app.schemas.common import OrderStatus, PaymentStatus, PayoutStatus


@pytest.fixture
def mock_db():
    return AsyncMock()


@pytest.mark.asyncio
async def test_create_payment_uses_server_order_amount(mock_db):
    service = PaymentService(mock_db)

    order = {
        "id": "order_123",
        "buyer_id": "buyer_1",
        "order_status": OrderStatus.PENDING_PAYMENT.value,
        "buyer_total_paise": 54000,  # ₹540.00
        "order_number": "ORD-2026-0001",
    }

    rzp_response = {"razorpay_order_id": "order_rzp_999"}

    with patch.object(service.order_repo, "find_by_id", new=AsyncMock(return_value=order)):
        with patch.object(service.payment_repo, "find_by_order_id", new=AsyncMock(return_value=None)):
            with patch("app.services.payment_service.razorpay_payment.create_order",
                       new=AsyncMock(return_value=rzp_response)):
                with patch.object(service.payment_repo, "create", new=AsyncMock(return_value="pay_doc_1")):
                    with patch.object(service.order_repo, "update_payment_status", new=AsyncMock()):
                        result = await service.create_payment(
                            order_id="order_123",
                            buyer_id="buyer_1",
                        )

                        # Must match server order total exactly
                        assert result["amount_paise"] == 54000
                        assert result["razorpay_order_id"] == "order_rzp_999"


@pytest.mark.asyncio
async def test_create_payment_rejects_unauthorized_buyer(mock_db):
    service = PaymentService(mock_db)

    order = {
        "id": "order_123",
        "buyer_id": "buyer_owner",
        "order_status": OrderStatus.PENDING_PAYMENT.value,
        "buyer_total_paise": 54000,
    }

    with patch.object(service.order_repo, "find_by_id", new=AsyncMock(return_value=order)):
        with pytest.raises(ForbiddenError):
            # Attacker attempting to pay for another buyer's order
            await service.create_payment(
                order_id="order_123",
                buyer_id="buyer_attacker",
            )


@pytest.mark.asyncio
async def test_verify_payment_success_transitions_order_to_paid(mock_db, monkeypatch):
    monkeypatch.setattr("app.services.payment_service.razorpay_payment.fetch_payment", AsyncMock(return_value={
        "id": "pay_rzp_001", "order_id": "order_rzp_999", "amount": 42000, "currency": "INR", "status": "captured",
    }))
    service = PaymentService(mock_db)

    payment = {
        "id": "pay_1",
        "order_id": "order_123",
        "buyer_id": "buyer_1",
        "razorpay_order_id": "order_rzp_999",
        "signature_verified": False,
        "amount_paise": 42000,
    }

    order = {
        "id": "order_123",
        "farmer_id": "farmer_1",
        "farmer_total_payout_paise": 42000,
    }

    with patch.object(service.payment_repo, "find_by_razorpay_order_id", new=AsyncMock(return_value=payment)):
        with patch.object(service.payment_repo, "find_by_razorpay_payment_id", new=AsyncMock(return_value=None)):
            with patch("app.services.payment_service.razorpay_payment.verify_payment_signature",
                       new=AsyncMock(return_value=True)):
                with patch.object(service.payment_repo, "update", new=AsyncMock()):
                    with patch.object(service.order_repo, "update_payment_status", new=AsyncMock()):
                        with patch.object(service.order_repo, "update_status", new=AsyncMock()):
                            with patch.object(service.order_repo, "update_payout_status", new=AsyncMock()):
                                with patch.object(service.order_repo, "find_by_id", new=AsyncMock(return_value=order)):
                                    with patch.object(service.payout_repo, "generate_payout_number", new=AsyncMock(return_value="PO-2026-0001")):
                                        with patch.object(service.payout_repo, "create", new=AsyncMock()):
                                            with patch.object(service.audit_service, "log", new=AsyncMock()):
                                                res = await service.verify_payment(
                                                    order_id="order_123",
                                                    razorpay_order_id="order_rzp_999",
                                                    razorpay_payment_id="pay_rzp_001",
                                                    razorpay_signature="sig_valid",
                                                    buyer_id="buyer_1",
                                                )

                                                assert res["payment_verified"] is True
                                                assert res["order_status"] == OrderStatus.PAID.value


@pytest.mark.asyncio
async def test_admin_approve_payout_success(mock_db):
    service = PayoutService(mock_db)

    payout = {
        "id": "payout_1",
        "order_id": "order_123",
        "farmer_id": "farmer_1",
        "amount_paise": 42000,
        "status": PayoutStatus.PENDING_APPROVAL.value,
    }

    approved_payout = dict(payout, status=PayoutStatus.APPROVED.value)

    with patch.object(service.payout_repo, "find_by_id", side_effect=[payout, approved_payout]):
        with patch.object(service.payout_repo, "update_status", new=AsyncMock()):
            with patch.object(service.order_repo, "update_payout_status", new=AsyncMock()):
                with patch.object(service.audit_service, "log", new=AsyncMock()):
                    res = await service.approve_payout(
                        payout_id="payout_1",
                        admin_id="admin_1",
                    )
                    assert res["status"] == PayoutStatus.APPROVED.value
