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

def fulfillment_view(order):
    return {k: order.get(k) for k in ("fulfillment_method", "delivery_address", "pickup_address", "delivery_fee_paise", "delivery_estimate", "cancellation_reason", "reservation_expires_at")}


def pricing_view(order):
    return {"farmer_base_total_paise": order.get("farmer_total_payout_paise"),
        "commission_total_paise": order.get("commission_total_paise"),
        "commission_percentage_bps": order.get("commission_percentage_bps")}


router = APIRouter(prefix="/orders", tags=["Orders"])


@router.post("/", response_model=APIResponse, status_code=201)
async def create_order(
    data: CreateOrderRequest,
    request: Request,
    current_user: dict = Depends(get_current_buyer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """
    Buyer supplies product, quantity and validated fulfillment.
    Backend calculates everything from stored pricing.
    """
    order_service = OrderService(db)
    payment_service = PaymentService(db)

    order = await order_service.create_order(
        buyer_id=current_user["id"],
        product_id=data.product_id,
        quantity=data.quantity,
        idempotency_key=data.idempotency_key,
        fulfillment_method=data.fulfillment_method,
        expected_unit_price_paise=data.expected_unit_price_paise,
        delivery_address=data.delivery_address.model_dump() if data.delivery_address else None,
    )

    return APIResponse(
        success=True,
        data=BuyerOrderResponse(
            **pricing_view(order),
            order_id=order["id"],
            **fulfillment_view(order),
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
            razorpay_order_id=None,
        ).model_dump(),
        request_id=get_request_id(request),
    )


@router.get("/", response_model=APIResponse)
async def list_orders(
    request: Request,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    status: str = Query(None, pattern="^(PENDING_PAYMENT|PAID|CONFIRMED|PROCESSING|SHIPPED|COMPLETED|CANCELLED|REFUNDED)$"),
    period: str = Query(None, pattern="^(today|month|year)$"),
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """List orders — scoped by role."""
    order_service = OrderService(db)
    role = current_user.get("role", "")
    from app.services.report_service import ReportService
    filters = {"order_status": status} if status else {}
    dates = ReportService(db)._build_date_filter(period, None, None)
    if dates: filters["created_at"] = dates

    if role == "BUYER":
        orders, total = await order_service.list_buyer_orders(current_user["id"], page, limit, filters)
    elif role == "FARMER":
        orders, total = await order_service.list_farmer_orders(current_user["id"], page, limit, filters)
    elif role == "ADMIN":
        orders, total = await order_service.list_all_orders(status, page, limit, filters)
    else:
        orders, total = [], 0

    items = []
    for o in orders:
        if role == "BUYER":
            items.append(BuyerOrderResponse(
                **pricing_view(o),
                order_id=o["id"],
                **fulfillment_view(o),
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
                **pricing_view(o),
                payment_status=o.get("payment_status", "PENDING"),
                order_id=o["id"],
                **fulfillment_view(o),
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
                **fulfillment_view(o),
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


from pydantic import BaseModel, ConfigDict
from typing import Optional, Literal
from app.schemas.location import Coordinates

class EstimateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    product_id: str
    fulfillment_method: Literal["PICKUP", "DELIVERY"]
    destination: Optional[Coordinates] = None

@router.post("/estimate", response_model=APIResponse)
async def estimate_order(data: EstimateRequest, request: Request, current_user=Depends(get_current_buyer), db=Depends(get_database)):
    from app.repositories.products import ProductRepository
    from app.repositories.farmers import FarmerRepository
    from app.services.delivery_service import estimate_delivery
    product = await ProductRepository(db).find_active_by_id(data.product_id)
    if not product: raise NotFoundError("Product")
    farm = await FarmerRepository(db).find_by_user_id(product["farmer_id"])
    result = estimate_delivery((farm.get("application") or {}).get("coordinates"), data.destination.model_dump() if data.destination else None,
        product.get("harvest_date"), data.fulfillment_method)
    return APIResponse(data=result, request_id=get_request_id(request))


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
            **pricing_view(order),
            order_id=order["id"],
            **fulfillment_view(order),
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
            **pricing_view(order),
            payment_status=order.get("payment_status", "PENDING"),
            order_id=order["id"],
            **fulfillment_view(order),
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


from app.schemas.order import OrderStatusUpdateRequest
@router.put("/{order_id}/status", response_model=APIResponse)
async def fulfill_order(order_id: str, data: OrderStatusUpdateRequest, request: Request,
                        current_user=Depends(get_current_user), db=Depends(get_database)):
    await OrderService(db).update_order_status(order_id, data.order_status, current_user["id"], current_user.get("role"))
    return APIResponse(data={"updated": True}, request_id=get_request_id(request))
