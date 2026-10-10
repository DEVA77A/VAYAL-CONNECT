"""
VayalConnect Backend — Order Schemas

Role-specific order views.
"""

from typing import Optional
from pydantic import BaseModel, Field
from datetime import datetime


class CreateOrderRequest(BaseModel):
    """
    Buyer creates an order.
    ONLY product_id and quantity — never price, commission, or payout.
    Backend calculates everything from stored pricing snapshot.
    """
    product_id: str = Field(..., min_length=1)
    quantity: int = Field(..., gt=0, le=1_000_000)
    idempotency_key: Optional[str] = Field(None, max_length=100)


class BuyerOrderResponse(BaseModel):
    """Order response for buyer — NO farmer payout, NO commission."""
    order_id: str
    order_number: str
    product_name: str
    quantity: int
    unit: str
    buyer_unit_price_paise: int
    buyer_unit_price_display: str
    buyer_total_paise: int
    buyer_total_display: str
    order_status: str
    payment_status: str
    razorpay_order_id: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class FarmerOrderResponse(BaseModel):
    """Order response for farmer — only payout info, NO buyer price, NO commission."""
    order_id: str
    order_number: str
    product_name: str
    quantity: int
    unit: str
    farmer_unit_payout_paise: int
    farmer_unit_payout_display: str
    farmer_total_payout_paise: int
    farmer_total_payout_display: str
    order_status: str
    payout_status: str
    buyer_name: Optional[str] = None
    created_at: Optional[datetime] = None


class AdminOrderResponse(BaseModel):
    """Order response for admin — FULL financial breakdown."""
    order_id: str
    order_number: str
    buyer_id: str
    buyer_name: str
    farmer_id: str
    farmer_name: str
    product_id: str
    product_name: str
    quantity: int
    unit: str
    buyer_unit_price_paise: int
    buyer_total_paise: int
    farmer_unit_payout_paise: int
    farmer_total_payout_paise: int
    commission_percentage_bps: int
    commission_percentage_display: str
    commission_unit_amount_paise: int
    commission_total_paise: int
    commission_total_display: str
    government_reference_price_paise: int
    reference_price_date: Optional[str] = None
    order_status: str
    payment_status: str
    payout_status: str
    razorpay_order_id: Optional[str] = None
    razorpay_payment_id: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class OrderStatusUpdateRequest(BaseModel):
    """Admin status update."""
    order_status: str


class CancelOrderRequest(BaseModel):
    """Cancel order request."""
    reason: Optional[str] = None
