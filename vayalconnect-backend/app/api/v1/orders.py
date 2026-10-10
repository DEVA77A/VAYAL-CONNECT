"""
VayalConnect Backend — Orders Router
"""

from fastapi import APIRouter, Depends, Request, Query
from motor.motor_asyncio import AsyncIOMotorDatabase

from app.core.database import get_database
from app.api.deps import get_current_user, get_current_buyer, get_current_admin, get_request_id
from app.services.order_service import OrderService
from app.services.payment_service import PaymentService
from app.schemas.order import (
    CreateOrderRequest, BuyerOrderResponse, FarmerOrderResponse,
    AdminOrderResponse, CancelOrderRequest,
)
from app.schemas.common import APIResponse
from app.core.exceptions import ForbiddenError, NotFoundError
from app.utils.money import format_rupees, percentage_bps_to_display

router = APIRouter(prefix="/orders", tags=["Orders"])


@router.post("/", response_model=APIResponse, status_code=201)
async def create_order(
    data: CreateOrderRequest,
    request: Request,
    current_user: dict = Depends(get_current_buyer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """
    Buyer creates an order. Only product_id and quantity are sent.
    Backend calculates everything from stored pricing.
    """
    order_service = OrderService(db)
    payment_service = PaymentService(db)

    order = await order_service.create_order(
        buyer_id=current_user["id"],
        product_id=data.product_id,
        quantity=data.quantity,
        idempotency_key=data.idempotency_key,
    )

    # Auto-create Razorpay payment
    payment = await payment_service.create_payment(order["id"], current_user["id"])

    return APIResponse(
        success=True,
        data=BuyerOrderResponse(
            order_id=order["id"],
            order_number=order.get("order_number", ""),
            product_name=order.get("product_name", ""),
            quantity=order.get("quantity", 0),
            unit=order.get("quantity_unit", ""),
            buyer_unit_price_paise=order.get("buyer_unit_price_paise", 0),
            buyer_unit_price_display=format_rupees(order.get("buyer_unit_price_paise", 0)),
            buyer_total_paise=order.get("buyer_total_paise", 0),
            buyer_total_display=format_rupees(order.get("buyer_total_paise", 0)),
            order_status=order.get("order_status", ""),
            payment_status=order.get("payment_status", ""),
            razorpay_order_id=payment.get("razorpay_order_id"),
        ).model_dump(),
        request_id=get_request_id(request),
    )


@router.get("/", response_model=APIResponse)
async def list_orders(
    request: Request,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    status: str = Query(None),
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """List orders — scoped by role."""
    order_service = OrderService(db)
    role = current_user.get("role", "")

    if role == "BUYER":
        orders, total = await order_service.list_buyer_orders(current_user["id"], page, limit)
    elif role == "FARMER":
        orders, total = await order_service.list_farmer_orders(current_user["id"], page, limit)
    elif role == "ADMIN":
        orders, total = await order_service.list_all_orders(status, page, limit)
    else:
        orders, total = [], 0

    items = []
    for o in orders:
        if role == "BUYER":
            items.append(BuyerOrderResponse(
                order_id=o["id"],
                order_number=o.get("order_number", ""),
                product_name=o.get("product_name", ""),
                quantity=o.get("quantity", 0),
                unit=o.get("quantity_unit", ""),
                buyer_unit_price_paise=o.get("buyer_unit_price_paise", 0),
                buyer_unit_price_display=format_rupees(o.get("buyer_unit_price_paise", 0)),
                buyer_total_paise=o.get("buyer_total_paise", 0),
                buyer_total_display=format_rupees(o.get("buyer_total_paise", 0)),
                order_status=o.get("order_status", ""),
                payment_status=o.get("payment_status", ""),
                created_at=o.get("created_at"),
                updated_at=o.get("updated_at"),
            ).model_dump())
        elif role == "FARMER":
            items.append(FarmerOrderResponse(
                order_id=o["id"],
                order_number=o.get("order_number", ""),
                product_name=o.get("product_name", ""),
                quantity=o.get("quantity", 0),
                unit=o.get("quantity_unit", ""),
                farmer_unit_payout_paise=o.get("farmer_unit_payout_paise", 0),
                farmer_unit_payout_display=format_rupees(o.get("farmer_unit_payout_paise", 0)),
                farmer_total_payout_paise=o.get("farmer_total_payout_paise", 0),
                farmer_total_payout_display=format_rupees(o.get("farmer_total_payout_paise", 0)),
                order_status=o.get("order_status", ""),
                payout_status=o.get("payout_status", ""),
                buyer_name=o.get("buyer_name"),
                created_at=o.get("created_at"),
            ).model_dump())
        elif role == "ADMIN":
            items.append(AdminOrderResponse(
                order_id=o["id"],
                order_number=o.get("order_number", ""),
                buyer_id=o.get("buyer_id", ""),
                buyer_name=o.get("buyer_name", ""),
                farmer_id=o.get("farmer_id", ""),
                farmer_name=o.get("farmer_name", ""),
                product_id=o.get("product_id", ""),
                product_name=o.get("product_name", ""),
                quantity=o.get("quantity", 0),
                unit=o.get("quantity_unit", ""),
                buyer_unit_price_paise=o.get("buyer_unit_price_paise", 0),
                buyer_total_paise=o.get("buyer_total_paise", 0),
                farmer_unit_payout_paise=o.get("farmer_unit_payout_paise", 0),
                farmer_total_payout_paise=o.get("farmer_total_payout_paise", 0),
                commission_percentage_bps=o.get("commission_percentage_bps", 0),
                commission_percentage_display=percentage_bps_to_display(o.get("commission_percentage_bps", 0)),
                commission_unit_amount_paise=o.get("commission_unit_amount_paise", 0),
                commission_total_paise=o.get("commission_total_paise", 0),
                commission_total_display=format_rupees(o.get("commission_total_paise", 0)),
                government_reference_price_paise=o.get("government_reference_price_paise", 0),
                order_status=o.get("order_status", ""),
                payment_status=o.get("payment_status", ""),
                payout_status=o.get("payout_status", ""),
                created_at=o.get("created_at"),
                updated_at=o.get("updated_at"),
            ).model_dump())

    return APIResponse(
        success=True,
        data={"items": items, "total": total, "page": page, "limit": limit},
        request_id=get_request_id(request),
    )


@router.get("/{order_id}", response_model=APIResponse)
async def get_order(
    order_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Get order detail — scoped by role and ownership."""
    order_service = OrderService(db)
    order = await order_service.get_order(order_id)
    if not order:
        raise NotFoundError("Order")

    role = current_user.get("role", "")
    # Ownership check
    if role == "BUYER" and order["buyer_id"] != current_user["id"]:
        raise NotFoundError("Order")  # 404 instead of 403 to avoid info leak
    if role == "FARMER" and order["farmer_id"] != current_user["id"]:
        raise NotFoundError("Order")

    if role == "BUYER":
        data = BuyerOrderResponse(
            order_id=order["id"],
            order_number=order.get("order_number", ""),
            product_name=order.get("product_name", ""),
            quantity=order.get("quantity", 0),
            unit=order.get("quantity_unit", ""),
            buyer_unit_price_paise=order.get("buyer_unit_price_paise", 0),
            buyer_unit_price_display=format_rupees(order.get("buyer_unit_price_paise", 0)),
            buyer_total_paise=order.get("buyer_total_paise", 0),
            buyer_total_display=format_rupees(order.get("buyer_total_paise", 0)),
            order_status=order.get("order_status", ""),
            payment_status=order.get("payment_status", ""),
            created_at=order.get("created_at"),
            updated_at=order.get("updated_at"),
        ).model_dump()
    elif role == "FARMER":
        data = FarmerOrderResponse(
            order_id=order["id"],
            order_number=order.get("order_number", ""),
            product_name=order.get("product_name", ""),
            quantity=order.get("quantity", 0),
            unit=order.get("quantity_unit", ""),
            farmer_unit_payout_paise=order.get("farmer_unit_payout_paise", 0),
            farmer_unit_payout_display=format_rupees(order.get("farmer_unit_payout_paise", 0)),
            farmer_total_payout_paise=order.get("farmer_total_payout_paise", 0),
            farmer_total_payout_display=format_rupees(order.get("farmer_total_payout_paise", 0)),
            order_status=order.get("order_status", ""),
            payout_status=order.get("payout_status", ""),
            created_at=order.get("created_at"),
        ).model_dump()
    else:
        data = order  # Admin gets full data

    return APIResponse(success=True, data=data, request_id=get_request_id(request))


@router.put("/{order_id}/cancel", response_model=APIResponse)
async def cancel_order(
    order_id: str,
    data: CancelOrderRequest,
    request: Request,
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Cancel an order."""
    order_service = OrderService(db)
    await order_service.cancel_order(
        order_id, current_user["id"], current_user.get("role", ""), data.reason
    )
    return APIResponse(
        success=True,
        data={"message": "Order cancelled."},
        request_id=get_request_id(request),
    )
