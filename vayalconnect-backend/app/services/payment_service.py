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

        expiry = order.get("reservation_expires_at")
        if isinstance(expiry, datetime):
            expiry = expiry.replace(tzinfo=timezone.utc) if expiry.tzinfo is None else expiry
            if expiry <= datetime.now(timezone.utc):
                from app.services.order_service import OrderService
                from app.core.exceptions import ConflictError
                await OrderService(self.db).cancel_order(order_id, "reservation-sweeper", "ADMIN", "Unpaid stock reservation expired.")
                raise ConflictError("ORDER_RESERVATION_EXPIRED", "Stock reservation expired. Select the crop again.")

        # Check for existing payment
        existing = await self.payment_repo.find_by_order_id(order_id)
        if existing and existing.get("payment_status") == PaymentStatus.CAPTURED.value:
            raise PaymentAlreadyVerifiedError()

        # Amount from stored order — NEVER from client
        if existing and existing.get("razorpay_order_id"):
            return {
                "payment_id": existing["id"], "razorpay_order_id": existing["razorpay_order_id"],
                "amount_paise": existing["amount_paise"], "currency": existing.get("currency", "INR"),
                "order_number": order.get("order_number", ""),
            }

        amount_paise = order["buyer_total_paise"]
        claimed = await self.payment_repo.claim_creation(order_id, buyer_id, amount_paise)
        if not claimed:
            from app.core.exceptions import ConflictError
            raise ConflictError("PAYMENT_CREATING", "A payment request is in progress. Reload in one minute before retrying.")
        if claimed.get("razorpay_order_id"):
            rz_order_id = claimed["razorpay_order_id"]
        else:
            rz = await razorpay_payment.create_order(amount_paise, "INR", order.get("order_number", order_id),
                notes={"order_id": order_id, "buyer_id": buyer_id})
            rz_order_id = rz["razorpay_order_id"]
        await self.payment_repo.complete_creation(claimed["id"], claimed["creation_owner"], rz_order_id)
        await self.order_repo.update_payment_status(order_id, PaymentStatus.CREATED.value)
        return {"payment_id": claimed["id"], "razorpay_order_id": rz_order_id, "amount_paise": amount_paise,
            "currency": "INR", "order_number": order.get("order_number", "")}

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

        if payment.get("order_id") != order_id:
            raise ForbiddenError("Payment does not match this order.")

        if payment.get("signature_verified"):
            if payment.get("razorpay_payment_id") != razorpay_payment_id:
                raise PaymentVerificationFailedError()
            order = await self.order_repo.find_by_id(order_id)
            return {"payment_verified": True, "order_status": order["order_status"], "message": "Test payment already verified."}
        # Verify signature with Razorpay
        is_valid = await razorpay_payment.verify_payment_signature(
            razorpay_order_id, razorpay_payment_id, razorpay_signature
        )

        if not is_valid:
            # Invalid callbacks cannot overwrite legitimate payment state.
            raise PaymentVerificationFailedError()

        # A signature authenticates checkout data, not capture status or amount.
        try:
            gateway_payment = await razorpay_payment.fetch_payment(razorpay_payment_id)
        except Exception:
            raise PaymentVerificationFailedError() from None
        if (gateway_payment.get("id") != razorpay_payment_id
                or gateway_payment.get("order_id") != payment["razorpay_order_id"]
                or gateway_payment.get("amount") != payment.get("amount_paise")
                or gateway_payment.get("currency") != payment.get("currency", "INR")
                or gateway_payment.get("status") != "captured"):
            raise PaymentVerificationFailedError()

        from app.services.payment_settlement import PaymentSettlement
        from app.core.config import settings
        res = await PaymentSettlement(self.db).captured(payment, gateway_payment, "CHECKOUT_SIGNATURE_AND_GATEWAY_FETCH")
        if settings.AUTO_PAYOUT_ENABLED and res.get("payment_verified") and res.get("order_status") != "CANCELLED":
            try:
                from app.services.payout_service import PayoutService
                await PayoutService(self.db).auto_process_payout(order_id)
            except Exception as e:
                logger.error("Auto payout execution error after payment verification: %s", type(e).__name__)
        return res

    async def get_payment_status(self, order_id: str) -> Optional[Dict[str, Any]]:
        return await self.payment_repo.find_by_order_id(order_id)

    async def handle_webhook(self, event_type: str, payload: Dict[str, Any]):
        """Handle Razorpay webhook events. Must be idempotent."""
        logger.info(f"Processing webhook event: {event_type}")

        entity = payload.get("payload", {}).get("payment", {}).get("entity", {})
        if event_type == "payment.captured":
            payment = await self.payment_repo.find_by_razorpay_order_id(entity.get("order_id", ""))
            if not payment:
                raise NotFoundError("Payment")
            gateway = await razorpay_payment.fetch_payment(entity.get("id", ""))
            if (gateway.get("id") != entity.get("id") or gateway.get("order_id") != payment["razorpay_order_id"]
                    or gateway.get("amount") != payment["amount_paise"] or gateway.get("currency") != "INR"
                    or gateway.get("status") != "captured"):
                raise PaymentVerificationFailedError()
            from app.services.payment_settlement import PaymentSettlement
            from app.core.config import settings
            res = await PaymentSettlement(self.db).captured(payment, gateway, "SIGNED_WEBHOOK_AND_GATEWAY_FETCH")
            if settings.AUTO_PAYOUT_ENABLED and res.get("payment_verified") and res.get("order_status") != "CANCELLED":
                try:
                    from app.services.payout_service import PayoutService
                    await PayoutService(self.db).auto_process_payout(str(payment.get("order_id")))
                except Exception as e:
                    logger.error("Auto payout webhook execution error: %s", type(e).__name__)
        elif event_type == "payment.failed":
            await self.audit_service.log(actor_id="razorpay", actor_role="GATEWAY", action="PAYMENT_ATTEMPT_FAILED",
                entity_type="payment", entity_id=entity.get("id", "unknown"))
        elif event_type in ("transfer.processed", "transfer.settled"):
            entity = payload.get("payload", {}).get("transfer", {}).get("entity", {})
            transfer_id = entity.get("id")
            notes = entity.get("notes", {})
            payout_id = notes.get("payout_id")
            order_id = notes.get("order_id")
            from app.services.payout_service import PayoutService
            payout_service = PayoutService(self.db)
            if payout_id:
                await payout_service.confirm_payout(payout_id, transfer_id or "", provider="razorpay_route")
            elif order_id:
                payout = await self.payout_repo.find_by_order_id(order_id)
                if payout:
                    await payout_service.confirm_payout(payout["id"], transfer_id or "", provider="razorpay_route")
            elif transfer_id:
                payout = await self.payout_repo.find_by_provider_reference(transfer_id)
                if payout:
                    await payout_service.confirm_payout(payout["id"], transfer_id, provider="razorpay_route")
        elif event_type == "transfer.failed":
            entity = payload.get("payload", {}).get("transfer", {}).get("entity", {})
            transfer_id = entity.get("id")
            notes = entity.get("notes", {})
            payout_id = notes.get("payout_id")
            order_id = notes.get("order_id")
            reason = entity.get("error_description") or "Transfer failed at gateway."
            from app.services.payout_service import PayoutService
            payout_service = PayoutService(self.db)
            if payout_id:
                await payout_service.fail_payout(payout_id, failure_reason=reason)
            elif order_id:
                payout = await self.payout_repo.find_by_order_id(order_id)
                if payout:
                    await payout_service.fail_payout(payout["id"], failure_reason=reason)
