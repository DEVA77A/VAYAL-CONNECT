"""
VayalConnect Backend — Payments Router
"""

from fastapi import APIRouter, Depends, Request
from motor.motor_asyncio import AsyncIOMotorDatabase

from app.core.database import get_database
from app.api.deps import get_current_buyer, get_current_user, get_request_id
from app.services.payment_service import PaymentService
from app.schemas.payment import PaymentVerifyRequest, PaymentVerifyResponse, PaymentStatusResponse
from app.schemas.common import APIResponse
from app.core.exceptions import NotFoundError, ForbiddenError
from app.utils.money import format_rupees

router = APIRouter(prefix="/payments", tags=["Payments"])


@router.post("/verify", response_model=APIResponse)
async def verify_payment(
    data: PaymentVerifyRequest,
    request: Request,
    current_user: dict = Depends(get_current_buyer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Verify Razorpay payment signature. Server-side verification."""
    service = PaymentService(db)
    result = await service.verify_payment(
        order_id=data.order_id,
        razorpay_order_id=data.razorpay_order_id,
        razorpay_payment_id=data.razorpay_payment_id,
        razorpay_signature=data.razorpay_signature,
        buyer_id=current_user["id"],
    )
    return APIResponse(
        success=True,
        data=PaymentVerifyResponse(**result).model_dump(),
        request_id=get_request_id(request),
    )


@router.get("/{order_id}", response_model=APIResponse)
async def get_payment_status(
    order_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Get payment status for an order."""
    service = PaymentService(db)
    payment = await service.get_payment_status(order_id)
    if not payment:
        raise NotFoundError("Payment")

    # Ownership check
    role = current_user.get("role", "")
    if role == "BUYER" and payment.get("buyer_id") != current_user["id"]:
        raise NotFoundError("Payment")

    return APIResponse(
        success=True,
        data=PaymentStatusResponse(
            payment_id=payment["id"],
            order_id=payment.get("order_id", ""),
            razorpay_order_id=payment.get("razorpay_order_id"),
            razorpay_payment_id=payment.get("razorpay_payment_id"),
            amount_paise=payment.get("amount_paise", 0),
            amount_display=format_rupees(payment.get("amount_paise", 0)),
            payment_status=payment.get("payment_status", ""),
            created_at=payment.get("created_at"),
            updated_at=payment.get("updated_at"),
        ).model_dump(),
        request_id=get_request_id(request),
    )
