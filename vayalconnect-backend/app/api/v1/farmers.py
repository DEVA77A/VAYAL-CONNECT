"""
VayalConnect Backend — Farmers Router

Farmer profile, bank details (encrypted), dashboard, payouts, transactions.
Bank details are NEVER exposed to buyers or other farmers.
"""

from fastapi import APIRouter, Depends, Request, Query
from motor.motor_asyncio import AsyncIOMotorDatabase

from app.core.database import get_database
from app.core.security import encrypt_value, decrypt_value, mask_value
from app.api.deps import get_current_farmer, get_request_id
from app.repositories.farmers import FarmerRepository
from app.repositories.products import ProductRepository
from app.repositories.orders import OrderRepository
from app.services.payout_service import PayoutService
from app.services.audit_service import AuditService
from app.schemas.farmer import (
    FarmerApplicationRequest, FarmerBankDetailsRequest, FarmerBankDetailsResponse,
    FarmerProfileResponse, FarmerDashboardResponse,
    FarmerPayoutResponse, FarmerTransactionResponse,
)
from app.schemas.common import APIResponse
from app.utils.money import format_rupees

from app.services.onboarding_service import OnboardingService, application_view

router = APIRouter(prefix="/farmers", tags=["Farmer"])


@router.get("/me/profile", response_model=APIResponse)
async def get_farmer_profile(
    request: Request,
    current_user: dict = Depends(get_current_farmer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Get farmer profile."""
    farmer_repo = FarmerRepository(db)
    profile = await farmer_repo.find_by_user_id(current_user["id"])
    from app.services.profile_completeness import missing_farmer_fields
    missing = missing_farmer_fields(profile or {})
    has_bank = bool(
        profile and profile.get("bank_account_number")
    ) if profile else False

    return APIResponse(
        success=True,
        data=FarmerProfileResponse(
            user_id=current_user["id"],
            name=current_user["name"],
            email=current_user["email"],
            phone=current_user["phone"],
            address=current_user.get("address", ""),
            area_location=current_user.get("area_location", ""),
            gender=current_user.get("gender", ""),
            age=current_user.get("age", 0),
            approval_status=profile.get("approval_status", "PENDING") if profile else "PENDING",
            bank_details_present=has_bank,
            profile_complete=not missing, missing_fields=missing,
            can_publish=bool(profile and profile.get("approval_status") == "APPROVED" and not missing),
            **application_view(profile or {}),
            created_at=current_user.get("created_at"),
        ).model_dump(),
        request_id=get_request_id(request),
    )


@router.put("/me/application", response_model=APIResponse)
async def submit_application(data: FarmerApplicationRequest, request: Request,
                             current_user: dict = Depends(get_current_farmer),
                             db: AsyncIOMotorDatabase = Depends(get_database)):
    result = await OnboardingService(db).submit(current_user, data)
    return APIResponse(success=True, data=result, request_id=get_request_id(request))


@router.get("/me/bank", response_model=APIResponse)
async def get_bank_details(
    request: Request,
    current_user: dict = Depends(get_current_farmer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Get own bank details (masked). Only accessible by the owning farmer."""
    farmer_repo = FarmerRepository(db)
    profile = await farmer_repo.find_by_user_id(current_user["id"])

    if not profile or not profile.get("bank_account_number"):
        return APIResponse(
            success=True,
            data={"message": "Bank details not configured."},
            request_id=get_request_id(request),
        )

    # Decrypt and mask for display
    try:
        acct = decrypt_value(profile["bank_account_number"])
        bank_name = decrypt_value(profile.get("bank_name", ""))
        ifsc = decrypt_value(profile.get("bank_ifsc", ""))
        upi = decrypt_value(profile.get("upi_id", "")) if profile.get("upi_id") else None
    except Exception:
        acct = ""
        bank_name = ""
        ifsc = ""
        upi = None

    return APIResponse(
        success=True,
        data=FarmerBankDetailsResponse(
            bank_name=bank_name,
            account_number_masked=mask_value(acct),
            ifsc=ifsc,
            upi_id_masked=mask_value(upi) if upi else None,
            bank_details_verified=profile.get("bank_details_verified", False),
        ).model_dump(),
        request_id=get_request_id(request),
    )


@router.put("/me/bank", response_model=APIResponse)
async def update_bank_details(
    data: FarmerBankDetailsRequest,
    request: Request,
    current_user: dict = Depends(get_current_farmer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Update bank details. Encrypted before storage."""
    farmer_repo = FarmerRepository(db)
    audit = AuditService(db)

    # Encrypt sensitive bank details
    encrypted_data = {
        "bank_account_holder_name": encrypt_value(data.account_holder_name),
        "bank_name": encrypt_value(data.bank_name),
        "bank_account_number": encrypt_value(data.account_number),
        "bank_ifsc": encrypt_value(data.ifsc),
        "bank_details_verified": False,  # Needs re-verification
        "upi_id": encrypt_value(data.upi_id) if data.upi_id else None,
    }

    profile = await farmer_repo.find_by_user_id(current_user["id"])
    if not profile:
        from app.core.exceptions import NotFoundError
        raise NotFoundError("Farmer profile")
    await farmer_repo.update_bank_details(current_user["id"], encrypted_data)

    await audit.log(
        actor_id=current_user["id"],
        actor_role="FARMER",
        action="BANK_DETAILS_UPDATED",
        entity_type="farmer_profile",
        entity_id=current_user["id"],
    )

    return APIResponse(
        success=True,
        data=FarmerBankDetailsResponse(
            bank_name=data.bank_name,
            account_number_masked=mask_value(data.account_number),
            ifsc=data.ifsc,
            upi_id_masked=mask_value(data.upi_id) if data.upi_id else None,
        ).model_dump(),
        request_id=get_request_id(request),
    )


@router.get("/me/dashboard", response_model=APIResponse)
async def get_farmer_dashboard(
    request: Request,
    current_user: dict = Depends(get_current_farmer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Farmer dashboard summary."""
    product_repo = ProductRepository(db)
    order_repo = OrderRepository(db)
    payout_service = PayoutService(db)

    total_products = await product_repo.count_by_farmer(current_user["id"])
    active_products = await product_repo.count_by_farmer(current_user["id"], active_only=True)
    total_orders = await order_repo.count_by_farmer(current_user["id"])
    pending_orders = await order_repo.count_by_farmer(current_user["id"], status="PENDING_PAYMENT")
    completed_orders = await order_repo.count_by_farmer(current_user["id"], status="COMPLETED")

    payout_summary = await payout_service.get_farmer_payout_summary(current_user["id"])

    return APIResponse(
        success=True,
        data=FarmerDashboardResponse(
            total_products=total_products,
            active_products=active_products,
            total_orders=total_orders,
            pending_orders=pending_orders,
            completed_orders=completed_orders,
            total_payout_paise=payout_summary.get("total_paid", 0),
            total_payout_display=format_rupees(payout_summary.get("total_paid", 0)),
            pending_payout_paise=payout_summary.get("total_pending", 0),
            pending_payout_display=format_rupees(payout_summary.get("total_pending", 0)),
        ).model_dump(),
        request_id=get_request_id(request),
    )


@router.get("/me/payouts", response_model=APIResponse)
async def list_farmer_payouts(
    request: Request,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    current_user: dict = Depends(get_current_farmer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """List farmer's own payouts. No commission info shown."""
    payout_service = PayoutService(db)
    payouts, total = await payout_service.list_farmer_payouts(
        current_user["id"], page, limit
    )

    items = [
        FarmerPayoutResponse(
            payout_id=p["id"],
            order_id=p.get("order_id", ""),
            amount_paise=p.get("amount_paise", 0),
            amount_display=format_rupees(p.get("amount_paise", 0)),
            status=p.get("status", ""),
            created_at=p.get("created_at"),
            paid_at=p.get("paid_at"),
        ).model_dump()
        for p in payouts
    ]

    return APIResponse(
        success=True,
        data={"items": items, "total": total, "page": page, "limit": limit},
        request_id=get_request_id(request),
    )


@router.get("/me/transactions", response_model=APIResponse)
async def list_farmer_transactions(
    request: Request,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    current_user: dict = Depends(get_current_farmer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Farmer transaction history — shows ONLY farmer payout, NOT buyer price or commission."""
    from app.services.order_service import OrderService
    order_service = OrderService(db)
    orders, total = await order_service.list_farmer_orders(
        current_user["id"], page, limit
    )

    items = [
        FarmerTransactionResponse(
            order_id=o["id"],
            order_number=o.get("order_number", ""),
            product_name=o.get("product_name", ""),
            quantity=o.get("quantity", 0),
            unit=o.get("quantity_unit", ""),
            farmer_payout_per_unit_paise=o.get("farmer_unit_payout_paise", 0),
            farmer_total_payout_paise=o.get("farmer_total_payout_paise", 0),
            farmer_total_payout_display=format_rupees(o.get("farmer_total_payout_paise", 0)),
            payout_status=o.get("payout_status", ""),
            order_status=o.get("order_status", ""),
            created_at=o.get("created_at"),
        ).model_dump()
        for o in orders
    ]

    return APIResponse(
        success=True,
        data={"items": items, "total": total, "page": page, "limit": limit},
        request_id=get_request_id(request),
    )


@router.get("/me/sales", response_model=APIResponse)
async def farmer_sales(request: Request, period: str = Query(None, pattern="^(today|month|year)$"), current_user=Depends(get_current_farmer), db=Depends(get_database)):
    from bson import ObjectId
    from app.services.report_service import ReportService
    match = {"farmer_id": ObjectId(current_user["id"]), "order_status": "COMPLETED", "payment_status": "CAPTURED"}
    window = ReportService(db)._build_date_filter(period, None, None)
    if window: match["created_at"] = window
    rows = await db.orders.aggregate([{"$match": match}, {"$group": {"_id": {"crop": "$product_name", "unit": "$quantity_unit"},
        "orders": {"$sum": 1}, "quantity": {"$sum": "$quantity"}, "farmer_amount_paise": {"$sum": "$farmer_total_payout_paise"},
        "commission_paise": {"$sum": "$commission_total_paise"}, "buyer_amount_paise": {"$sum": "$buyer_total_paise"}}}]).to_list(500)
    stock = await db.products.aggregate([{"$match": {"farmer_id": ObjectId(current_user["id"]), "is_active": True}},
        {"$group": {"_id": "$quantity_unit", "quantity": {"$sum": "$quantity_available"}}}]).to_list(10)
    return APIResponse(data={"items": rows, "stock": stock, "period": period or "all", "timezone": "UTC",
        "farmer_earnings_paise": sum(r["farmer_amount_paise"] for r in rows), "commission_paise": sum(r["commission_paise"] for r in rows),
        "formula": "Farmer receives their full selected base price. Commission is added to the buyer price, not deducted from the selected farmer price. Delivery is included."}, request_id=get_request_id(request))
