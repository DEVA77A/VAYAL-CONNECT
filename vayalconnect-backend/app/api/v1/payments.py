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
    if role == "FARMER":
        from app.repositories.orders import OrderRepository
        order = await OrderRepository(db).find_by_id(order_id)
        if not order or order.get("farmer_id") != current_user["id"]:
            raise NotFoundError("Payment")
    if role not in ("ADMIN", "BUYER", "FARMER"):
        raise NotFoundError("Payment")
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


@router.post("/{order_id}/checkout", response_model=APIResponse)
async def create_checkout(order_id: str, request: Request, current_user=Depends(get_current_buyer), db=Depends(get_database)):
    from app.integrations.razorpay import razorpay_payment
    from app.core.exceptions import ValidationError
    if not razorpay_payment._configured or not razorpay_payment.key_id.startswith("rzp_test_"):
        raise ValidationError("Razorpay TEST mode is not configured. Payment remains pending.")
    result = await PaymentService(db).create_payment(order_id, current_user["id"])
    result.update({"key_id": razorpay_payment.key_id, "test_mode": True})
    return APIResponse(data=result, request_id=get_request_id(request))
