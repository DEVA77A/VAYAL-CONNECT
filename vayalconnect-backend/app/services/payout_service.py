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
from app.services.audit_service import AuditService
from app.integrations.razorpay import payout_provider
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
        Initiate actual bank transfer via payout provider.
        Requires farmer bank details.
        """
        payout = await self.payout_repo.find_by_id(payout_id)
        if not payout:
            raise NotFoundError("Payout")

        if payout["status"] != PayoutStatus.APPROVED.value:
            raise PayoutNotEligibleError("Payout must be approved before processing.")

        if not getattr(payout_provider, "supports_bank_transfers", False):
            raise PayoutNotEligibleError("Bank transfers are disabled for this Razorpay TEST demonstration. A verified payout provider is required.")

        # Get farmer bank details
        farmer_profile = await self.farmer_repo.find_by_user_id(payout["farmer_id"])
        if not farmer_profile:
            raise PayoutNotEligibleError("Farmer profile not found.")

        if not farmer_profile.get("bank_account_number"):
            raise PayoutNotEligibleError("Farmer bank details not configured.")

        # Decrypt bank details for payout
        try:
            account_number = decrypt_value(farmer_profile["bank_account_number"])
            ifsc = decrypt_value(farmer_profile["bank_ifsc"])
            account_name = decrypt_value(farmer_profile["bank_account_holder_name"])
        except Exception as e:
            logger.error("Failed to decrypt payout bank details category=%s", type(e).__name__)
            raise PayoutNotEligibleError("Unable to process bank details.")

        # Update to PROCESSING
        await self.payout_repo.update_status(
            payout_id,
            PayoutStatus.PROCESSING.value,
            processed_at=datetime.now(timezone.utc),
        )
        await self.order_repo.update_payout_status(
            payout["order_id"], PayoutStatus.PROCESSING.value
        )

        # Initiate transfer via provider
        try:
            result = await payout_provider.initiate_payout(
                amount_paise=payout["amount_paise"],
                bank_account_number=account_number,
                ifsc=ifsc,
                account_holder_name=account_name,
                reference_id=payout.get("payout_number", payout_id),
            )

            await self.payout_repo.update_status(
                payout_id,
                PayoutStatus.PROCESSING.value,
                provider=result.get("provider", ""),
                provider_reference_id=result.get("reference_id", ""),
                provider_status=result.get("status", ""),
            )

            await self.audit_service.log(
                actor_id=admin_id,
                actor_role="ADMIN",
                action="PAYOUT_INITIATED",
                entity_type="payout",
                entity_id=payout_id,
                details={
                    "provider": result.get("provider"),
                    "reference_id": result.get("reference_id"),
                },
            )

            return result

        except Exception as e:
            logger.error("Payout initiation failed category=%s", type(e).__name__)
            await self.payout_repo.update_status(
                payout_id,
                PayoutStatus.FAILED.value,
                failure_reason="Provider transfer could not be confirmed.",
            )
            await self.order_repo.update_payout_status(
                payout["order_id"], PayoutStatus.FAILED.value
            )
            raise PayoutNotEligibleError("Payout processing could not be confirmed.") from None

    async def get_farmer_payout_summary(self, farmer_id: str) -> Dict[str, Any]:
        """Aggregate payout data for farmer dashboard."""
        return await self.payout_repo.aggregate_farmer_payouts(farmer_id)
