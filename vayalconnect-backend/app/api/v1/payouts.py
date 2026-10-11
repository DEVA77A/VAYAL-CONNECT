"""
VayalConnect Backend — Payouts Router
"""

from fastapi import APIRouter, Depends, Request, Query
from motor.motor_asyncio import AsyncIOMotorDatabase

from app.core.database import get_database
from app.api.deps import get_current_admin, get_request_id
from app.services.payout_service import PayoutService
from app.schemas.payout import PayoutApproveRequest, PayoutRejectRequest, AdminPayoutDetailResponse
from app.schemas.common import APIResponse
from app.core.exceptions import NotFoundError
from app.utils.money import format_rupees

router = APIRouter(prefix="/payouts", tags=["Payouts"])


@router.get("/", response_model=APIResponse)
async def list_payouts(
    request: Request,
    status: str = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Admin: List all payouts."""
    service = PayoutService(db)
    payouts, total = await service.list_payouts(status, page, limit)

    from app.repositories.orders import OrderRepository
    from bson import ObjectId
    order_ids = [ObjectId(p["order_id"]) for p in payouts]
    order_repo = OrderRepository(db)
    rows = await order_repo.collection.find({"_id": {"$in": order_ids}}).to_list(limit)
    order_map = {str(o["_id"]): o for o in rows}
    items = [
        AdminPayoutDetailResponse(
            payout_id=p["id"],
            payout_number=p.get("payout_number", ""),
            order_id=p.get("order_id", ""),
            order_number=order_map.get(p["order_id"], {}).get("order_number", ""),
            farmer_id=p.get("farmer_id", ""),
            farmer_name=order_map.get(p["order_id"], {}).get("farmer_name", ""),
            product_name=order_map.get(p["order_id"], {}).get("product_name", ""),
            amount_paise=p.get("amount_paise", 0),
            amount_display=format_rupees(p.get("amount_paise", 0)),
            commission_total_paise=order_map.get(p["order_id"], {}).get("commission_total_paise", 0),
            commission_display=format_rupees(order_map.get(p["order_id"], {}).get("commission_total_paise", 0)),
            buyer_total_paise=order_map.get(p["order_id"], {}).get("buyer_total_paise", 0),
            status=p.get("status", ""),
            provider=p.get("provider"),
            provider_reference_id=p.get("provider_reference_id"),
            approved_by=p.get("approved_by"),
            approved_at=p.get("approved_at"),
            rejection_reason=p.get("rejection_reason"),
            processed_at=p.get("processed_at"),
            paid_at=p.get("paid_at"),
            failure_reason=p.get("failure_reason"),
            created_at=p.get("created_at"),
            updated_at=p.get("updated_at"),
        ).model_dump()
        for p in payouts
    ]

    return APIResponse(
        success=True,
        data={"items": items, "total": total, "page": page, "limit": limit},
        request_id=get_request_id(request),
    )


@router.get("/{payout_id}", response_model=APIResponse)
async def get_payout(
    payout_id: str,
    request: Request,
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Admin: Get payout detail."""
    service = PayoutService(db)
    payout = await service.get_payout(payout_id)
    if not payout:
        raise NotFoundError("Payout")

    return APIResponse(
        success=True,
        data=payout,
        request_id=get_request_id(request),
    )


@router.put("/{payout_id}/approve", response_model=APIResponse)
async def approve_payout(
    payout_id: str,
    request: Request,
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Admin: Approve a payout."""
    service = PayoutService(db)
    result = await service.approve_payout(payout_id, current_user["id"])
    return APIResponse(
        success=True,
        data={"message": "Payout approved.", "payout": result},
        request_id=get_request_id(request),
    )


@router.put("/{payout_id}/reject", response_model=APIResponse)
async def reject_payout(
    payout_id: str,
    data: PayoutRejectRequest,
    request: Request,
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Admin: Reject a payout."""
    service = PayoutService(db)
    result = await service.reject_payout(payout_id, current_user["id"], data.rejection_reason)
    return APIResponse(
        success=True,
        data={"message": "Payout rejected.", "payout": result},
        request_id=get_request_id(request),
    )


@router.post("/{payout_id}/process", response_model=APIResponse)
async def process_payout(
    payout_id: str,
    request: Request,
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Admin: Initiate bank transfer for approved payout."""
    service = PayoutService(db)
    result = await service.process_payout(payout_id, current_user["id"])
    return APIResponse(
        success=True,
        data={"message": "Payout processing initiated.", "result": result},
        request_id=get_request_id(request),
    )
