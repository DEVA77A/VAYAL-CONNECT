"""
VayalConnect Backend — Payout Schemas
"""

from typing import Optional
from pydantic import BaseModel, Field
from datetime import datetime


class PayoutApproveRequest(BaseModel):
    """Admin approves a payout."""
    pass  # No additional data needed


class PayoutRejectRequest(BaseModel):
    """Admin rejects a payout."""
    rejection_reason: str = Field(..., min_length=5, max_length=500)


class FarmerPayoutDetailResponse(BaseModel):
    """Payout visible to farmer — NO commission info."""
    payout_id: str
    payout_number: str
    order_id: str
    order_number: str
    product_name: str
    amount_paise: int
    amount_display: str
    status: str
    created_at: Optional[datetime] = None
    paid_at: Optional[datetime] = None


class AdminPayoutDetailResponse(BaseModel):
    """Payout visible to admin — full details."""
    payout_id: str
    payout_number: str
    order_id: str
    order_number: str
    farmer_id: str
    farmer_name: str
    product_name: str
    amount_paise: int
    amount_display: str
    commission_total_paise: int
    commission_display: str
    buyer_total_paise: int
    status: str
    provider: Optional[str] = None
    provider_reference_id: Optional[str] = None
    approved_by: Optional[str] = None
    approved_at: Optional[datetime] = None
    rejection_reason: Optional[str] = None
    processed_at: Optional[datetime] = None
    paid_at: Optional[datetime] = None
    failure_reason: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
