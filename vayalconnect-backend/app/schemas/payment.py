"""
VayalConnect Backend — Payment Schemas
"""

from typing import Optional
from pydantic import BaseModel, Field
from datetime import datetime


class PaymentVerifyRequest(BaseModel):
    """Verify Razorpay payment — server validates signature."""
    order_id: str
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str


class PaymentVerifyResponse(BaseModel):
    payment_verified: bool
    order_status: str
    message: str = ""


class PaymentStatusResponse(BaseModel):
    payment_id: str
    order_id: str
    razorpay_order_id: Optional[str] = None
    razorpay_payment_id: Optional[str] = None
    amount_paise: int
    amount_display: str
    currency: str = "INR"
    payment_status: str
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
