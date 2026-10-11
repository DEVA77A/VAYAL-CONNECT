"""
VayalConnect Backend — Order Schemas

Role-specific order views.
"""

from typing import Optional
from pydantic import BaseModel, Field, ConfigDict, model_validator
from typing import Literal
from datetime import datetime


from app.schemas.location import Coordinates


class DeliveryAddress(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    recipient_name: str = Field(..., min_length=2, max_length=200)
    phone: str = Field(..., pattern=r"^[6-9][0-9]{9}$")
    address: str = Field(..., min_length=10, max_length=500)
    postal_code: str = Field(..., pattern=r"^[1-9][0-9]{5}$")
    building: Optional[str] = Field(None, max_length=100)
    street: Optional[str] = Field(None, max_length=200)
    locality: Optional[str] = Field(None, max_length=200)
    city: Optional[str] = Field(None, max_length=100)
    state: Optional[str] = Field(None, max_length=100)
    instructions: str = Field("", max_length=500)
    coordinates: Optional[Coordinates] = None


class CreateOrderRequest(BaseModel):
    """
    Buyer creates an order.
    Product, quantity and fulfillment; expected price is only a stale-preview guard.
    Backend determines authoritative pricing and freezes the order snapshot.
    """
    model_config = ConfigDict(extra="forbid")
    expected_unit_price_paise: Optional[int] = Field(None, gt=0, strict=True)
    fulfillment_method: Literal["PICKUP", "DELIVERY"]
    delivery_address: Optional[DeliveryAddress] = None
    product_id: str = Field(..., min_length=1)
    quantity: int = Field(..., gt=0, le=1_000_000, strict=True)
    idempotency_key: Optional[str] = Field(None, max_length=100)


    @model_validator(mode="after")
    def validate_fulfillment(self):
        if self.fulfillment_method == "DELIVERY" and (self.delivery_address is None or self.delivery_address.coordinates is None):
            raise ValueError("A delivery address with actual destination coordinates is required.")
        if self.fulfillment_method == "PICKUP" and self.delivery_address is not None:
            raise ValueError("Pickup must not include a delivery address.")
        return self


class FulfillmentResponse(BaseModel):
    reservation_expires_at: Optional[datetime] = None
    fulfillment_method: Optional[str] = None
    delivery_address: Optional[DeliveryAddress] = None
    pickup_address: Optional[str] = None
    delivery_fee_paise: Optional[int] = None
    delivery_estimate: Optional[dict] = None
    farmer_base_total_paise: Optional[int] = None
    commission_total_paise: Optional[int] = None
    commission_percentage_bps: Optional[int] = None
    cancellation_reason: Optional[str] = None
    payment_status: str = "PENDING"


class BuyerOrderResponse(FulfillmentResponse):
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


class FarmerOrderResponse(FulfillmentResponse):
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


class AdminOrderResponse(FulfillmentResponse):
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
