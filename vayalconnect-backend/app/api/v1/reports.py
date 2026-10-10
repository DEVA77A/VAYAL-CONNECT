"""
VayalConnect Backend — Reports Router
"""

from fastapi import APIRouter, Depends, Request, Query
from typing import Optional
from datetime import date
from motor.motor_asyncio import AsyncIOMotorDatabase

from app.core.database import get_database
from app.api.deps import get_current_admin, get_request_id
from app.services.report_service import ReportService
from app.schemas.common import APIResponse

router = APIRouter(prefix="/reports", tags=["Reports"])


@router.get("/orders", response_model=APIResponse)
async def order_report(
    request: Request,
    period: Optional[str] = Query(None, description="today|yesterday|week|month"),
    date_from: Optional[date] = Query(None),
    date_to: Optional[date] = Query(None),
    product_id: Optional[str] = Query(None),
    farmer_id: Optional[str] = Query(None),
    buyer_id: Optional[str] = Query(None),
    order_status: Optional[str] = Query(None),
    payout_status: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    current_user: dict = Depends(get_current_admin),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Admin order report with filters and aggregated summary."""
    report_service = ReportService(db)
    result = await report_service.get_order_report(
        period=period,
        date_from=date_from,
        date_to=date_to,
        product_id=product_id,
        farmer_id=farmer_id,
        buyer_id=buyer_id,
        order_status=order_status,
        payout_status=payout_status,
        page=page,
        limit=limit,
    )
    return APIResponse(
        success=True,
        data=result,
        request_id=get_request_id(request),
    )
