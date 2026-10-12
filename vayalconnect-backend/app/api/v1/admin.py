"""
VayalConnect Backend — Admin Router

Dashboard, user management, farmer approval, product management.
"""

from fastapi import APIRouter, Depends, Request, Query
from motor.motor_asyncio import AsyncIOMotorDatabase

from app.core.database import get_database
from app.api.deps import get_current_admin, get_request_id
from app.repositories.users import UserRepository
from app.repositories.farmers import FarmerRepository
from app.services.report_service import ReportService
from app.services.pricing_service import CommissionService
from app.services.audit_service import AuditService
from app.schemas.admin import (
    AdminDashboardResponse, AdminUserListItem,
    FarmerApproveRequest, FarmerRejectRequest,
)
from app.schemas.pricing import UpdateCommissionRequest, CommissionUpdateResponse
from app.schemas.common import APIResponse
from app.core.exceptions import NotFoundError
from app.utils.money import format_rupees, percentage_bps_to_display

from app.services.onboarding_service import OnboardingService, application_view

router = APIRouter(prefix="/admin", tags=["Admin"])


@router.get("/dashboard", response_model=APIResponse)
async def get_dashboard(
    request: Request,
    period: str = Query(None, pattern="^(today|week|month|year)$"),
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Admin dashboard with aggregate metrics."""
    report_service = ReportService(db)
    metrics = await report_service.get_dashboard_metrics(period=period)
    return APIResponse(
        success=True,
        data=AdminDashboardResponse(**metrics).model_dump(),
        request_id=get_request_id(request),
    )


@router.get("/users", response_model=APIResponse)
async def list_users(
    request: Request,
    role: str = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=100),
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """List all users."""
    user_repo = UserRepository(db)
    users, total = await user_repo.list_users(role=role, page=page, limit=limit)

    items = [
        AdminUserListItem(
            id=u["id"],
            name=u["name"],
            email=u["email"],
            phone=u["phone"],
            role=u.get("role"),
            is_active=u.get("is_active", False),
            email_verified=u.get("email_verified", False),
            created_at=u.get("created_at"),
        ).model_dump()
        for u in users
    ]

    return APIResponse(
        success=True,
        data={"items": items, "total": total, "page": page, "limit": limit},
        request_id=get_request_id(request),
    )


@router.get("/farmers", response_model=APIResponse)
async def list_farmers(
    request: Request,
    status: str = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=100),
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """List farmer profiles with approval status."""
    farmer_repo = FarmerRepository(db)
    user_repo = UserRepository(db)

    farmers, total = await farmer_repo.list_by_status(status, page, limit)

    items = []
    for f in farmers:
        user = await user_repo.find_by_id(f.get("user_id", ""))
        if user:
            items.append({
                "user_id": f.get("user_id", ""),
                "name": user.get("name", ""),
                "area_location": user.get("area_location", ""),
                "email": user.get("email", ""),
                "phone": user.get("phone", ""),
                "approval_status": f.get("approval_status", ""),
                "profile_present": f.get("profile_present", True),
                "address": user.get("address", ""),
                "email_verified": user.get("email_verified", False),
                "is_active": user.get("is_active", False),
                **application_view(f),
                "bank_details_present": bool(f.get("bank_account_number")),
                "created_at": f.get("created_at"),
            })

    return APIResponse(
        success=True,
        data={"items": items, "total": total, "page": page, "limit": limit},
        request_id=get_request_id(request),
    )


@router.put("/farmers/{user_id}/approve", response_model=APIResponse)
async def approve_farmer(
    user_id: str,
    data: FarmerApproveRequest,
    request: Request,
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Approve a farmer account."""
    await OnboardingService(db).decide(user_id, data.application_revision, current_user["id"], True)

    return APIResponse(
        success=True,
        data={"message": "Farmer approved successfully."},
        request_id=get_request_id(request),
    )


@router.put("/farmers/{user_id}/reject", response_model=APIResponse)
async def reject_farmer(
    user_id: str,
    data: FarmerRejectRequest,
    request: Request,
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Reject a farmer account."""
    await OnboardingService(db).decide(user_id, data.application_revision, current_user["id"], False, data.reason)

    return APIResponse(
        success=True,
        data={"message": "Farmer rejected."},
        request_id=get_request_id(request),
    )


@router.get("/commission", response_model=APIResponse)
async def get_commission(
    request: Request,
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Get active commission configuration."""
    commission_service = CommissionService(db)
    config = await commission_service.get_active_commission()
    return APIResponse(
        success=True,
        data=config or {"commission_percentage_bps": 2000, "version": 0, "is_default": True, "message": "Using the server default 20% commission."},
        request_id=get_request_id(request),
    )


@router.put("/commission", response_model=APIResponse)
async def update_commission(
    data: UpdateCommissionRequest,
    request: Request,
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Update commission percentage. Applies only to new transactions."""
    commission_service = CommissionService(db)
    audit = AuditService(db)

    result = await commission_service.update_commission(
        data.commission_percentage_bps, current_user["id"]
    )

    await audit.log(
        actor_id=current_user["id"],
        actor_role="ADMIN",
        action="COMMISSION_UPDATED",
        entity_type="commission_config",
        entity_id=result.get("config_id", ""),
        details={
            "previous_bps": result["previous_percentage_bps"],
            "new_bps": result["new_percentage_bps"],
        },
    )

    return APIResponse(
        success=True,
        data=CommissionUpdateResponse(
            previous_percentage_bps=result["previous_percentage_bps"],
            new_percentage_bps=result["new_percentage_bps"],
            previous_display=result["previous_display"],
            new_display=result["new_display"],
            effective_from=result.get("effective_from"),
        ).model_dump(),
        request_id=get_request_id(request),
    )


@router.get("/commission/history", response_model=APIResponse)
async def get_commission_history(
    request: Request,
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Commission change history."""
    commission_service = CommissionService(db)
    history = await commission_service.get_commission_history()
    return APIResponse(
        success=True,
        data={"items": history},
        request_id=get_request_id(request),
    )


@router.get("/users/{user_id}/activity", response_model=APIResponse)
async def user_activity(user_id: str, request: Request, current_user=Depends(get_current_admin), db=Depends(get_database)):
    from app.repositories.orders import OrderRepository
    from app.repositories.products import ProductRepository
    user = await UserRepository(db).find_by_id(user_id)
    if not user: raise NotFoundError("User")
    if user.get("role") == "FARMER":
        orders, total = await OrderRepository(db).list_by_farmer(user_id, 1, 100)
        products, product_total = await ProductRepository(db).list_by_farmer(user_id, 1, 100)
    else:
        orders, total = await OrderRepository(db).list_by_buyer(user_id, 1, 100)
        products, product_total = [], 0
    return APIResponse(data={"orders": orders, "total_orders": total, "products": products, "total_products": product_total}, request_id=get_request_id(request))


@router.get("/farmers/{user_id}", response_model=APIResponse)
async def farmer_review_detail(user_id: str, request: Request, current_user=Depends(get_current_admin), db=Depends(get_database)):
    user = await UserRepository(db).find_by_id(user_id)
    profile = await FarmerRepository(db).find_by_user_id(user_id)
    if not user or user.get("role") != "FARMER":
        raise NotFoundError("Farmer")
    profile_present = profile is not None
    profile = profile or {"approval_status": "PENDING"}
    return APIResponse(data={"user_id": user_id, **{k: user.get(k) for k in ("name", "email", "phone", "address", "area_location", "is_active", "email_verified")},
        "profile_present": profile_present,
        "approval_status": profile.get("approval_status"), **application_view(profile), "bank_details_present": bool(profile.get("bank_account_number"))}, request_id=get_request_id(request))
