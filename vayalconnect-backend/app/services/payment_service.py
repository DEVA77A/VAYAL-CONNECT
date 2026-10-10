"""
VayalConnect Backend — Payment Service

Handles Razorpay order creation, payment verification, and webhook processing.
All payment amounts calculated server-side. Never trusts client values.
"""

from typing import Optional, Dict, Any
from datetime import datetime, timezone
from motor.motor_asyncio import AsyncIOMotorDatabase
import logging

from app.repositories.payments import PaymentRepository
from app.repositories.orders import OrderRepository
from app.repositories.payouts import PayoutRepository
from app.services.audit_service import AuditService
from app.integrations.razorpay import razorpay_payment
from app.core.exceptions import (
    NotFoundError, PaymentVerificationFailedError,
    PaymentAlreadyVerifiedError, ValidationError, ForbiddenError,
)
from app.schemas.common import OrderStatus, PaymentStatus, PayoutStatus

logger = logging.getLogger(__name__)


class PaymentService:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.db = db
        self.payment_repo = PaymentRepository(db)
        self.order_repo = OrderRepository(db)
        self.payout_repo = PayoutRepository(db)
        self.audit_service = AuditService(db)

    async def create_payment(self, order_id: str, buyer_id: str) -> Dict[str, Any]:
        """
        Create a Razorpay order for payment.
        Amount is taken from the stored order — NEVER from the client.
        """
        order = await self.order_repo.find_by_id(order_id)
        if not order:
            raise NotFoundError("Order")

        if order["buyer_id"] != buyer_id:
            raise ForbiddenError("You can only pay for your own orders.")

        if order["order_status"] != OrderStatus.PENDING_PAYMENT.value:
            raise ValidationError("This order is not in a payable state.")

        # Check for existing payment
        existing = await self.payment_repo.find_by_order_id(order_id)
        if existing and existing.get("payment_status") == PaymentStatus.CAPTURED.value:
            raise PaymentAlreadyVerifiedError()

        # Amount from stored order — NEVER from client
        amount_paise = order["buyer_total_paise"]

        # Create Razorpay order
        rz_order = await razorpay_payment.create_order(
            amount_paise=amount_paise,
            currency="INR",
            receipt=order.get("order_number", order_id),
            notes={
                "order_id": order_id,
                "buyer_id": buyer_id,
                "product": order.get("product_name", ""),
            },
        )

        # Store payment record
        payment_doc = {
            "order_id": order_id,
            "buyer_id": buyer_id,
            "razorpay_order_id": rz_order["razorpay_order_id"],
            "razorpay_payment_id": None,
            "razorpay_signature": None,
            "signature_verified": False,
            "amount_paise": amount_paise,
            "currency": "INR",
            "payment_status": PaymentStatus.CREATED.value,
            "failure_reason": None,
            "idempotency_key": f"pay_{order_id}",
        }

        payment_id = await self.payment_repo.create(payment_doc)

        # Update order payment status
        await self.order_repo.update_payment_status(
            order_id, PaymentStatus.CREATED.value
        )

        return {
            "payment_id": payment_id,
            "razorpay_order_id": rz_order["razorpay_order_id"],
            "amount_paise": amount_paise,
            "currency": "INR",
            "order_number": order.get("order_number", ""),
        }

    async def verify_payment(
        self,
        order_id: str,
        razorpay_order_id: str,
        razorpay_payment_id: str,
        razorpay_signature: str,
        buyer_id: str,
    ) -> Dict[str, Any]:
        """
        Verify Razorpay payment signature.
        Only marks order as PAID after successful server-side verification.
        """
        # Get payment record
        payment = await self.payment_repo.find_by_razorpay_order_id(razorpay_order_id)
        if not payment:
            raise NotFoundError("Payment")

        # Verify ownership
        if payment["buyer_id"] != buyer_id:
            raise ForbiddenError("Payment does not belong to you.")

        # Check idempotency — already verified?
        if payment.get("signature_verified"):
            return {
                "payment_verified": True,
                "order_status": OrderStatus.PAID.value,
                "message": "Payment already verified.",
            }

        # Prevent duplicate payment_id processing
        existing_pid = await self.payment_repo.find_by_razorpay_payment_id(razorpay_payment_id)
        if existing_pid:
            raise PaymentAlreadyVerifiedError()

        # Verify signature with Razorpay
        is_valid = await razorpay_payment.verify_payment_signature(
            razorpay_order_id, razorpay_payment_id, razorpay_signature
        )

        if not is_valid:
            # Update payment as failed
            await self.payment_repo.update(payment["id"], {
                "razorpay_payment_id": razorpay_payment_id,
                "payment_status": PaymentStatus.FAILED.value,
                "failure_reason": "Signature verification failed",
            })
            await self.order_repo.update_payment_status(
                order_id, PaymentStatus.FAILED.value
            )
            raise PaymentVerificationFailedError()

        # Mark payment as captured
        await self.payment_repo.update(payment["id"], {
            "razorpay_payment_id": razorpay_payment_id,
            "razorpay_signature": razorpay_signature,
            "signature_verified": True,
            "payment_status": PaymentStatus.CAPTURED.value,
        })

        # Update order to PAID
        await self.order_repo.update_status(order_id, OrderStatus.PAID.value)
        await self.order_repo.update_payment_status(
            order_id, PaymentStatus.CAPTURED.value
        )

        # Create payout record (PENDING_APPROVAL)
        order = await self.order_repo.find_by_id(order_id)
        if order:
            payout_number = await self.payout_repo.generate_payout_number()
            await self.payout_repo.create({
                "payout_number": payout_number,
                "order_id": order_id,
                "farmer_id": order["farmer_id"],
                "amount_paise": order["farmer_total_payout_paise"],
                "currency": "INR",
                "status": PayoutStatus.PENDING_APPROVAL.value,
                "provider": "pending",
                "idempotency_key": f"payout_{order_id}",
            })
            await self.order_repo.update_payout_status(
                order_id, PayoutStatus.PENDING_APPROVAL.value
            )

        await self.audit_service.log(
            actor_id=buyer_id,
            actor_role="BUYER",
            action="PAYMENT_VERIFIED",
            entity_type="payment",
            entity_id=payment["id"],
            details={
                "order_id": order_id,
                "razorpay_payment_id": razorpay_payment_id,
                "amount_paise": payment.get("amount_paise", 0),
            },
        )

        return {
            "payment_verified": True,
            "order_status": OrderStatus.PAID.value,
            "message": "Payment verified successfully.",
        }

    async def get_payment_status(self, order_id: str) -> Optional[Dict[str, Any]]:
        return await self.payment_repo.find_by_order_id(order_id)

    async def handle_webhook(self, event_type: str, payload: Dict[str, Any]):
        """Handle Razorpay webhook events. Must be idempotent."""
        logger.info(f"Processing webhook event: {event_type}")

        if event_type == "payment.captured":
            rz_payment_id = payload.get("payload", {}).get("payment", {}).get("entity", {}).get("id")
            rz_order_id = payload.get("payload", {}).get("payment", {}).get("entity", {}).get("order_id")

            if rz_payment_id and rz_order_id:
                payment = await self.payment_repo.find_by_razorpay_order_id(rz_order_id)
                if payment and not payment.get("signature_verified"):
                    logger.info(f"Webhook: confirming payment {rz_payment_id}")
                    await self.payment_repo.update_by_razorpay_order_id(rz_order_id, {
                        "razorpay_payment_id": rz_payment_id,
                        "payment_status": PaymentStatus.CAPTURED.value,
                        "signature_verified": True,
                    })

        elif event_type == "payment.failed":
            rz_order_id = payload.get("payload", {}).get("payment", {}).get("entity", {}).get("order_id")
            if rz_order_id:
                await self.payment_repo.update_by_razorpay_order_id(rz_order_id, {
                    "payment_status": PaymentStatus.FAILED.value,
                    "failure_reason": "Payment failed (webhook)",
                })
