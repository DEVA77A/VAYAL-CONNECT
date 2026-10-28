"""
VayalConnect Backend — Payout Service

Admin-approved farmer payout workflow.
Payout is NOT automatic — requires admin approval.
Uses provider abstraction for actual bank transfers.
"""

from typing import Optional, Dict, Any, List
from datetime import datetime, timezone
from motor.motor_asyncio import AsyncIOMotorDatabase
import logging

from app.repositories.payouts import PayoutRepository
from app.core.transactions import transactional
from app.repositories.orders import OrderRepository
from app.repositories.farmers import FarmerRepository
from app.repositories.users import UserRepository
from app.repositories.payments import PaymentRepository
from app.services.audit_service import AuditService
from app.integrations.razorpay import payout_provider, razorpay_payment
from app.core.config import settings
from app.core.security import decrypt_value
from app.core.exceptions import (
    NotFoundError, PayoutNotEligibleError, InvalidStateTransitionError,
    ForbiddenError,
)
from app.schemas.common import PayoutStatus, VALID_PAYOUT_TRANSITIONS

logger = logging.getLogger(__name__)


class PayoutService:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.db = db
        self.payout_repo = PayoutRepository(db)
        self.order_repo = OrderRepository(db)
        self.farmer_repo = FarmerRepository(db)
        self.user_repo = UserRepository(db)
        self.payment_repo = PaymentRepository(db)
        self.audit_service = AuditService(db)

    async def list_payouts(
        self, status: Optional[str] = None, page: int = 1, limit: int = 50
    ) -> tuple[List[Dict[str, Any]], int]:
        return await self.payout_repo.list_all(status, page, limit)

    async def list_farmer_payouts(
        self, farmer_id: str, page: int = 1, limit: int = 50
    ) -> tuple[List[Dict[str, Any]], int]:
        return await self.payout_repo.list_by_farmer(farmer_id, page, limit)

    async def get_payout(self, payout_id: str) -> Optional[Dict[str, Any]]:
        return await self.payout_repo.find_by_id(payout_id)

    @transactional
    async def approve_payout(self, payout_id: str, admin_id: str) -> Dict[str, Any]:
        """Admin approves a payout for processing."""
        payout = await self.payout_repo.find_by_id(payout_id)
        if not payout:
            raise NotFoundError("Payout")

        order = await self.order_repo.find_by_id(payout["order_id"])
        if not order or order.get("order_status") != "COMPLETED" or order.get("payment_status") != "CAPTURED" or order.get("farmer_total_payout_paise") != payout["amount_paise"]:
            raise PayoutNotEligibleError("Payout review requires a completed, captured order with matching farmer earnings.")

        if payout["status"] != PayoutStatus.PENDING_APPROVAL.value:
            raise InvalidStateTransitionError(
                payout["status"], PayoutStatus.APPROVED.value
            )

        await self.payout_repo.update_status(
            payout_id,
            PayoutStatus.APPROVED.value,
            approved_by=admin_id,
            approved_at=datetime.now(timezone.utc),
        )

        # Update order payout status
        await self.order_repo.update_payout_status(
            payout["order_id"], PayoutStatus.APPROVED.value
        )

        await self.audit_service.log(
            actor_id=admin_id,
            actor_role="ADMIN",
            action="PAYOUT_APPROVED",
            entity_type="payout",
            entity_id=payout_id,
            details={"farmer_id": payout["farmer_id"], "amount": payout["amount_paise"]},
        )

        return await self.payout_repo.find_by_id(payout_id)

    @transactional
    async def reject_payout(
        self, payout_id: str, admin_id: str, reason: str
    ) -> Dict[str, Any]:
        """Admin rejects a payout."""
        payout = await self.payout_repo.find_by_id(payout_id)
        if not payout:
            raise NotFoundError("Payout")

        if payout["status"] != PayoutStatus.PENDING_APPROVAL.value:
            raise InvalidStateTransitionError(
                payout["status"], PayoutStatus.REJECTED.value
            )

        await self.payout_repo.update_status(
            payout_id,
            PayoutStatus.REJECTED.value,
            rejection_reason=reason,
        )

        await self.order_repo.update_payout_status(
            payout["order_id"], PayoutStatus.REJECTED.value
        )

        await self.audit_service.log(
            actor_id=admin_id,
            actor_role="ADMIN",
            action="PAYOUT_REJECTED",
            entity_type="payout",
            entity_id=payout_id,
            details={"reason": reason},
        )

        return await self.payout_repo.find_by_id(payout_id)

    async def process_payout(self, payout_id: str, admin_id: str) -> Dict[str, Any]:
        """
        Initiate actual transfer via Razorpay Route or provider.
        """
        payout = await self.payout_repo.find_by_id(payout_id)
        if not payout:
            raise NotFoundError("Payout")

        if payout["status"] not in (PayoutStatus.APPROVED.value, PayoutStatus.PENDING_APPROVAL.value, PayoutStatus.FAILED.value):
            raise PayoutNotEligibleError(f"Payout in status {payout['status']} cannot be processed.")

        order = await self.order_repo.find_by_id(payout["order_id"])
        if not order or order.get("payment_status") != "CAPTURED":
            raise PayoutNotEligibleError("Verified captured payment is required before processing payout.")

        farmer_profile = await self.farmer_repo.find_by_user_id(payout["farmer_id"])
        if not farmer_profile:
            raise PayoutNotEligibleError("Farmer profile not found.")

        # 1. Attempt Razorpay Route transfer if account is linked
        route_account_id = farmer_profile.get("razorpay_account_id")
        payment = await self.payment_repo.find_by_order_id(payout["order_id"])
        payment_gateway_id = payment.get("razorpay_payment_id") if payment else payout.get("razorpay_payment_id")

        if route_account_id and payment_gateway_id and settings.RAZORPAY_ROUTE_ENABLED:
            res = await razorpay_payment.create_transfer(
                payment_id=payment_gateway_id,
                account_id=route_account_id,
                amount_paise=payout["amount_paise"],
                notes={"order_id": payout["order_id"], "payout_id": payout_id},
            )
            if res.get("success"):
                status = res.get("status", "processed")
                now = datetime.now(timezone.utc)
                if status == "processed":
                    return await self.confirm_payout(payout_id, res.get("transfer_id", ""), provider="razorpay_route")
                else:
                    await self.payout_repo.update_status(
                        payout_id,
                        PayoutStatus.PROCESSING.value,
                        provider="razorpay_route",
                        provider_reference_id=res.get("transfer_id"),
                        provider_status=status,
                        processed_at=now,
                    )
                    await self.order_repo.update_payout_status(payout["order_id"], PayoutStatus.PROCESSING.value)
                    return await self.payout_repo.find_by_id(payout_id)

        # 2. In non-production or test demonstration / sandbox:
        if settings.APP_ENV != "production" or settings.SANDBOX_PAYOUTS_ENABLED:
            ref_id = f"trf_test_{payout.get('payout_number', payout_id)}"
            return await self.confirm_payout(payout_id, ref_id, provider="razorpay_route_test")

        # 3. Production bank transfer
        if not getattr(payout_provider, "supports_bank_transfers", False):
            raise PayoutNotEligibleError("Bank transfers require Razorpay Route or RazorpayX activation.")

        if not farmer_profile.get("bank_account_number"):
            raise PayoutNotEligibleError("Farmer bank details not configured.")

        try:
            account_number = decrypt_value(farmer_profile["bank_account_number"])
            ifsc = decrypt_value(farmer_profile["bank_ifsc"])
            account_name = decrypt_value(farmer_profile["bank_account_holder_name"])
        except Exception as e:
            logger.error("Failed to decrypt payout bank details category=%s", type(e).__name__)
            raise PayoutNotEligibleError("Unable to process bank details.")

        await self.payout_repo.update_status(
            payout_id,
            PayoutStatus.PROCESSING.value,
            processed_at=datetime.now(timezone.utc),
        )
        await self.order_repo.update_payout_status(
            payout["order_id"], PayoutStatus.PROCESSING.value
        )

        try:
            result = await payout_provider.initiate_payout(
                amount_paise=payout["amount_paise"],
                bank_account_number=account_number,
                ifsc=ifsc,
                account_holder_name=account_name,
                reference_id=payout.get("payout_number", payout_id),
            )
            if result.get("status") == "PAID":
                return await self.confirm_payout(payout_id, result.get("reference_id", ""), provider=result.get("provider", "razorpay"))
            else:
                await self.payout_repo.update_status(
                    payout_id,
                    PayoutStatus.PROCESSING.value,
                    provider=result.get("provider", ""),
                    provider_reference_id=result.get("reference_id", ""),
                    provider_status=result.get("status", ""),
                )
                return await self.payout_repo.find_by_id(payout_id)
        except Exception as e:
            logger.error("Payout initiation failed category=%s", type(e).__name__)
            await self.fail_payout(payout_id, f"Provider transfer failed: {str(e)}")
            raise PayoutNotEligibleError("Payout processing could not be confirmed.") from None

    @transactional
    async def confirm_payout(
        self,
        payout_id: str,
        reference_id: str,
        provider: str = "razorpay_route",
    ) -> Dict[str, Any]:
        """Confirm a payout as transferred and paid."""
        payout = await self.payout_repo.find_by_id(payout_id)
        if not payout:
            raise NotFoundError("Payout")

        if payout.get("status") == PayoutStatus.PAID.value:
            return payout

        now = datetime.now(timezone.utc)
        await self.payout_repo.update_status(
            payout_id,
            PayoutStatus.PAID.value,
            provider=provider,
            provider_reference_id=reference_id,
            provider_status="PROCESSED",
            paid_at=now,
        )
        await self.order_repo.update_payout_status(
            payout["order_id"], PayoutStatus.PAID.value
        )
        await self.audit_service.log(
            actor_id="system",
            actor_role="GATEWAY",
            action="PAYOUT_PAID",
            entity_type="payout",
            entity_id=payout_id,
            details={
                "provider": provider,
                "reference_id": reference_id,
                "amount_paise": payout["amount_paise"],
                "farmer_id": payout["farmer_id"],
                "order_id": payout["order_id"],
            },
        )
        return await self.payout_repo.find_by_id(payout_id)

    @transactional
    async def fail_payout(
        self,
        payout_id: str,
        failure_reason: str,
        provider: str = "razorpay_route",
    ) -> Dict[str, Any]:
        """Record transfer failure."""
        payout = await self.payout_repo.find_by_id(payout_id)
        if not payout:
            raise NotFoundError("Payout")

        if payout.get("status") == PayoutStatus.PAID.value:
            return payout

        await self.payout_repo.update_status(
            payout_id,
            PayoutStatus.FAILED.value,
            provider=provider,
            failure_reason=failure_reason,
            provider_status="FAILED",
        )
        await self.order_repo.update_payout_status(
            payout["order_id"], PayoutStatus.FAILED.value
        )
        await self.audit_service.log(
            actor_id="system",
            actor_role="GATEWAY",
            action="PAYOUT_FAILED",
            entity_type="payout",
            entity_id=payout_id,
            details={"reason": failure_reason},
        )
        return await self.payout_repo.find_by_id(payout_id)

    async def auto_process_payout(self, order_id: str) -> Optional[Dict[str, Any]]:
        """
        Automatically execute transfer for an eligible payout upon verified payment capture.
        """
        payout = await self.payout_repo.find_by_order_id(order_id)
        if not payout:
            logger.warning("Auto payout skipped: no payout found for order %s", order_id)
            return None

        if payout.get("status") in ("PAID", "PROCESSING"):
            logger.info("Auto payout skipped: payout %s is already %s", payout["id"], payout.get("status"))
            return payout

        order = await self.order_repo.find_by_id(order_id)
        if not order or order.get("payment_status") != "CAPTURED":
            logger.warning("Auto payout skipped: order %s payment is not CAPTURED", order_id)
            return payout

        payment = await self.payment_repo.find_by_order_id(order_id)
        payment_gateway_id = payment.get("razorpay_payment_id") if payment else payout.get("razorpay_payment_id")

        farmer_profile = await self.farmer_repo.find_by_user_id(payout["farmer_id"])
        route_account_id = farmer_profile.get("razorpay_account_id") if farmer_profile else None

        if route_account_id and payment_gateway_id and settings.RAZORPAY_ROUTE_ENABLED:
            logger.info("Initiating Razorpay Route transfer for payout %s to account %s", payout["id"], route_account_id)
            result = await razorpay_payment.create_transfer(
                payment_id=payment_gateway_id,
                account_id=route_account_id,
                amount_paise=payout["amount_paise"],
                notes={
                    "order_id": str(order_id),
                    "payout_id": payout["id"],
                    "farmer_id": payout["farmer_id"],
                },
            )
            if result.get("success"):
                status = result.get("status", "processed")
                now = datetime.now(timezone.utc)
                if status == "processed":
                    return await self.confirm_payout(
                        payout["id"],
                        reference_id=result.get("transfer_id", ""),
                        provider="razorpay_route",
                    )
                else:
                    await self.payout_repo.update_status(
                        payout["id"],
                        PayoutStatus.PROCESSING.value,
                        provider="razorpay_route",
                        provider_reference_id=result.get("transfer_id"),
                        provider_status=status,
                        processed_at=now,
                    )
                    await self.order_repo.update_payout_status(order_id, PayoutStatus.PROCESSING.value)
                return await self.payout_repo.find_by_id(payout["id"])
            else:
                logger.warning("Razorpay Route transfer failed for payout %s: %s", payout["id"], result.get("message"))
                await self.payout_repo.update_status(
                    payout["id"],
                    PayoutStatus.PENDING_APPROVAL.value,
                    provider="razorpay_route",
                    provider_status=result.get("error_code", "ROUTE_ERROR"),
                    failure_reason=result.get("message"),
                )
                return await self.payout_repo.find_by_id(payout["id"])

        if settings.APP_ENV != "production" or settings.SANDBOX_PAYOUTS_ENABLED:
            ref_id = f"trf_test_{payout.get('payout_number', payout['id'])}"
            res = await self.confirm_payout(
                payout["id"],
                reference_id=ref_id,
                provider="razorpay_route_test",
            )
            logger.info("Test demonstration: auto-payout confirmed for order %s payout %s", order_id, payout["id"])
            return res

        await self.payout_repo.update_status(
            payout["id"],
            PayoutStatus.PENDING_APPROVAL.value,
            provider="razorpay_route",
            provider_status="AWAITING_LINKED_ACCOUNT",
            failure_reason="Farmer Razorpay Route linked account not configured.",
        )
        return await self.payout_repo.find_by_id(payout["id"])

    async def get_farmer_payout_summary(self, farmer_id: str) -> Dict[str, Any]:
        """Aggregate payout data for farmer dashboard."""
        return await self.payout_repo.aggregate_farmer_payouts(farmer_id)
