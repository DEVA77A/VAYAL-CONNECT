"""Farmer applications: allowlisted fields and atomic review of a submitted revision."""
from app.core.transactions import transactional
from app.repositories.farmers import FarmerRepository
from app.repositories.users import UserRepository
from app.schemas.farmer import FarmerApplicationRequest
from app.core.exceptions import NotFoundError, ForbiddenError, ValidationError, ConflictError
from app.services.audit_service import AuditService


def application_view(profile):
    return {key: profile.get(key) for key in ("application", "submitted_at", "rejection_reason")} | {"application_revision": profile.get("application_revision", 0)}


class OnboardingService:
    def __init__(self, db):
        self.db = db
        self.farmers = FarmerRepository(db)
        self.users = UserRepository(db)
        self.audit = AuditService(db)

    @transactional
    async def submit(self, user, data: FarmerApplicationRequest):
        if not user.get("email_verified"):
            raise ForbiddenError("Verify your email before submitting an application.")
        profile = await self.farmers.find_by_user_id(user["id"])
        if not profile:
            if data.application_revision != 0:
                raise ConflictError("APPLICATION_CHANGED", "Application is missing. Reload before submitting.")
            await self.farmers.ensure_pending_profile(user["id"])
        if not await self.farmers.submit_application(user["id"], data.model_dump(exclude={"application_revision"}), data.application_revision):
            raise ConflictError("APPLICATION_CHANGED", "Application changed or is already approved. Reload before submitting.")
        await self.users.update(user["id"], {"is_approved": False})
        await self.audit.log(actor_id=user["id"], actor_role="FARMER", action="FARMER_APPLICATION_SUBMITTED", entity_type="farmer_profile", entity_id=user["id"])
        return {"approval_status": "PENDING", "application_revision": data.application_revision + 1,
                "rejection_reason": None, "profile_present": True}

    @transactional
    async def decide(self, user_id, revision, actor, approved, reason=None):
        profile = await self.farmers.find_by_user_id(user_id)
        user = await self.users.find_by_id(user_id)
        if not profile or not user or user.get("role") != "FARMER":
            raise NotFoundError("Farmer profile")
        if approved:
            if not user.get("is_active") or not user.get("email_verified"):
                raise ValidationError("Approval requires an active farmer with verified email.")
            if not profile.get("submitted_at") or not profile.get("application"):
                raise ValidationError("Farmer must submit a complete application before approval.")
            from pydantic import ValidationError as SchemaError
            try:
                FarmerApplicationRequest.model_validate(profile["application"])
            except SchemaError:
                raise ValidationError("Farmer must correct and resubmit the application before approval.") from None
            from app.services.profile_completeness import missing_farmer_fields
            if missing_farmer_fields(profile):
                raise ValidationError("Approval requires farm coordinates and complete bank payout details.")
        if not await self.farmers.decide_application(user_id, revision, "APPROVED" if approved else "REJECTED", actor, reason):
            raise ConflictError("APPLICATION_CHANGED", "Application changed or was already reviewed. Reload before deciding.")
        await self.users.update(user_id, {"is_approved": approved})
        await self.audit.log(actor_id=actor, actor_role="ADMIN", action="FARMER_APPROVED" if approved else "FARMER_REJECTED", entity_type="farmer_profile", entity_id=user_id, details={"application_revision": revision, "reason": reason})
