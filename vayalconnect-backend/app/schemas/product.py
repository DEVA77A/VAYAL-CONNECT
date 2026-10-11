"""
VayalConnect Backend — Product Schemas

Role-specific product views:
- Farmer: sees own payout, NOT buyer price or commission
- Buyer: sees buyer price, NOT farmer payout or commission
- Admin: sees complete financial breakdown
"""

from typing import Optional
from pydantic import BaseModel, Field, ConfigDict
from datetime import date, datetime
from app.schemas.common import QuantityUnit, QualityGrade, ProductStatus


class CreateProductRequest(BaseModel):
    """Farmer selects payout per unit; buyer totals and commission stay server-owned."""
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    selling_price_per_unit_paise: int = Field(..., gt=0, le=100_000_000, strict=True)
    description: str = Field("", max_length=2000)
    product_name: str = Field(..., min_length=2, max_length=200)
    category: str = Field(..., min_length=2, max_length=100)
    quantity: int = Field(..., gt=0, le=1_000_000)
    quantity_unit: QuantityUnit
    quality_grade: QualityGrade
    image_url: Optional[str] = None
    location: str = Field(..., min_length=2, max_length=200)
    market: str = Field(..., min_length=2, max_length=200)
    harvest_date: date


class UpdateProductRequest(BaseModel):
    """Farmer edits own listing; sold order snapshots never change."""
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    description: Optional[str] = Field(None, max_length=2000)
    selling_price_per_unit_paise: Optional[int] = Field(None, gt=0, le=100_000_000, strict=True)
    stock_adjustment: Optional[int] = Field(None, ge=-1_000_000, le=1_000_000, strict=True)
    quantity: Optional[int] = Field(None, gt=0, le=1_000_000)
    quality_grade: Optional[QualityGrade] = None
    harvest_date: Optional[date] = None
    image_url: Optional[str] = None
    status: Optional[ProductStatus] = None


# ============================================================
# FARMER-SAFE Response — No buyer price, no commission, no gov price
# ============================================================

class FarmerProductResponse(BaseModel):
    """Product view for the owning farmer. Shows ONLY farmer payout."""
    description: str = ""
    product_id: str
    product_name: str
    category: str
    quantity_available: int
    quantity_unit: str
    quality_grade: str
    image_url: Optional[str] = None
    location: str
    market: str
    harvest_date: Optional[date] = None
    market_reference: Optional[dict] = None
    farmer_payout_per_unit_paise: int
    farmer_payout_per_unit_display: str
    status: str
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


# ============================================================
# BUYER-SAFE Response — No farmer payout, no commission, no gov price
# ============================================================

class BuyerProductResponse(BaseModel):
    """Product view for buyers. Shows ONLY buyer price."""
    description: str = ""
    product_id: str
    product_name: str
    category: str
    quantity_available: int
    quantity_unit: str
    quality_grade: str
    image_url: Optional[str] = None
    location: str
    farmer_name: Optional[str] = None
    pickup_address: Optional[str] = None
    delivery_available: bool = False
    farmer_base_price_paise: int = 0
    commission_per_unit_paise: int = 0
    commission_percentage_bps: int = 0
    market_reference: Optional[dict] = None
    farm_coordinates: Optional[dict] = None
    buyer_price_per_unit_paise: int
    buyer_price_per_unit_display: str
    harvest_date: Optional[date] = None


# ============================================================
# ADMIN Response — Complete financial breakdown
# ============================================================

class AdminProductResponse(BaseModel):
    """Product view for admin. Shows ALL financial details."""
    description: str = ""
    product_id: str
    product_name: str
    category: str
    farmer_id: str
    farmer_name: str
    quantity_available: int
    quantity_unit: str
    quality_grade: str
    image_url: Optional[str] = None
    location: str
    market: str
    harvest_date: Optional[date] = None
    government_reference_price_paise: int
    government_reference_price_display: str
    reference_price_date: Optional[date] = None
    reference_price_source: Optional[str] = None
    farmer_payout_per_unit_paise: int
    farmer_payout_per_unit_display: str
    buyer_price_per_unit_paise: int
    buyer_price_per_unit_display: str
    commission_percentage_bps: int
    commission_percentage_display: str
    commission_per_unit_paise: int
    commission_per_unit_display: str
    pricing_policy_id: Optional[str] = None
    pricing_policy_version: Optional[int] = None
    status: str
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
