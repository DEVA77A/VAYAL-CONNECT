"""
VayalConnect Backend — Farmer Schemas

Bank details, farmer profile, and farmer dashboard schemas.
Bank details are always masked in responses.
"""

from typing import Optional
from pydantic import BaseModel, Field, field_validator
from datetime import datetime
from app.utils.validators import is_valid_ifsc, is_valid_upi


class FarmerBankDetailsRequest(BaseModel):
    """Request to set/update farmer bank details."""
    account_holder_name: str = Field(..., min_length=2, max_length=200)
    bank_name: str = Field(..., min_length=2, max_length=200)
    account_number: str = Field(..., min_length=8, max_length=20)
    ifsc: str = Field(..., min_length=11, max_length=11)
    upi_id: Optional[str] = Field(None, max_length=100)

    @field_validator("ifsc")
    @classmethod
    def validate_ifsc(cls, v: str) -> str:
        v = v.upper().strip()
        if not is_valid_ifsc(v):
            raise ValueError("Invalid IFSC code format")
        return v

    @field_validator("upi_id")
    @classmethod
    def validate_upi(cls, v: Optional[str]) -> Optional[str]:
        if v and not is_valid_upi(v):
            raise ValueError("Invalid UPI ID format")
        return v


class FarmerBankDetailsResponse(BaseModel):
    """Masked bank details — NEVER show full account numbers."""
    bank_name: str
    account_number_masked: str  # XXXX1234
    ifsc: str
    upi_id_masked: Optional[str] = None  # XXXX@upi
    bank_details_verified: bool = False


class FarmerProfileResponse(BaseModel):
    """Farmer profile visible to the farmer."""
    user_id: str
    name: str
    email: str
    phone: str
    address: str
    area_location: str
    gender: str
    age: int
    approval_status: str
    bank_details_present: bool = False
    created_at: Optional[datetime] = None


class FarmerDashboardResponse(BaseModel):
    """Farmer dashboard summary."""
    total_products: int = 0
    active_products: int = 0
    total_orders: int = 0
    pending_orders: int = 0
    completed_orders: int = 0
    total_payout_paise: int = 0
    total_payout_display: str = "₹0.00"
    pending_payout_paise: int = 0
    pending_payout_display: str = "₹0.00"


class FarmerPayoutResponse(BaseModel):
    """Payout information visible to farmer — NO buyer price, no commission."""
    payout_id: str
    order_id: str
    amount_paise: int
    amount_display: str
    status: str
    created_at: Optional[datetime] = None
    paid_at: Optional[datetime] = None


class FarmerTransactionResponse(BaseModel):
    """Transaction history entry for farmer."""
    order_id: str
    order_number: str
    product_name: str
    quantity: int
    unit: str
    farmer_payout_per_unit_paise: int
    farmer_total_payout_paise: int
    farmer_total_payout_display: str
    payout_status: str
    order_status: str
    created_at: Optional[datetime] = None


class FarmerAdminDetailResponse(BaseModel):
    """Full farmer details visible to admin only."""
    user_id: str
    name: str
    email: str
    phone: str
    address: str
    area_location: str
    gender: str
    age: int
    role: str
    approval_status: str
    bank_name: Optional[str] = None
    account_number_masked: Optional[str] = None
    ifsc: Optional[str] = None
    upi_id_masked: Optional[str] = None
    bank_details_verified: bool = False
    total_products: int = 0
    total_orders: int = 0
    total_payout_paise: int = 0
    created_at: Optional[datetime] = None
