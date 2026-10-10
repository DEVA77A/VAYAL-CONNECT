"""
VayalConnect Backend — Pricing & Commission Schemas
"""

from typing import Optional
from pydantic import BaseModel, Field
from datetime import datetime, date


class PricingPolicyResponse(BaseModel):
    """Pricing policy visible to admin."""
    policy_id: str
    name: str
    description: str
    farmer_payout_percentage_bps: int
    buyer_price_percentage_bps: int
    version: int
    is_active: bool
    created_at: Optional[datetime] = None


class CreatePricingPolicyRequest(BaseModel):
    name: str = Field(..., min_length=2, max_length=200)
    description: str = Field(..., max_length=1000)
    farmer_payout_percentage_bps: int = Field(..., ge=0, le=10000)
    buyer_price_percentage_bps: int = Field(..., ge=0, le=10000)


class UpdatePricingPolicyRequest(BaseModel):
    name: Optional[str] = Field(None, min_length=2, max_length=200)
    description: Optional[str] = Field(None, max_length=1000)
    farmer_payout_percentage_bps: Optional[int] = Field(None, ge=0, le=10000)
    buyer_price_percentage_bps: Optional[int] = Field(None, ge=0, le=10000)
    is_active: Optional[bool] = None


class CommissionConfigResponse(BaseModel):
    """Active commission configuration."""
    config_id: str
    commission_percentage_bps: int
    commission_percentage_display: str
    effective_from: Optional[datetime] = None
    status: str
    version: int
    created_at: Optional[datetime] = None


class UpdateCommissionRequest(BaseModel):
    """Admin updates commission percentage. Basis points: 1500 = 15%."""
    commission_percentage_bps: int = Field(..., ge=0, le=5000)


class CommissionUpdateResponse(BaseModel):
    previous_percentage_bps: int
    new_percentage_bps: int
    previous_display: str
    new_display: str
    effective_from: Optional[datetime] = None
    note: str = "Applies only to new transactions. Historical transactions remain unchanged."


class PricingSnapshotResponse(BaseModel):
    """Pricing snapshot visible to admin only."""
    snapshot_id: str
    product_id: str
    government_reference_price_paise: int
    reference_price_unit: str
    reference_price_date: Optional[date] = None
    reference_price_source: str
    farmer_payout_per_unit_paise: int
    buyer_price_per_unit_paise: int
    commission_percentage_bps: int
    commission_per_unit_paise: int
    pricing_policy_id: Optional[str] = None
    pricing_policy_version: Optional[int] = None
    market: str
    location: str
    quality_grade: str
    calculated_at: Optional[datetime] = None
