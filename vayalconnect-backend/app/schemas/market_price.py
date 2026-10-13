"""
VayalConnect Backend — Market Price Schemas

Defines source-verified market records with optional prices and original units.
"""

from typing import Optional, List
from pydantic import BaseModel, Field
from datetime import date, datetime


class MarketPriceItem(BaseModel):
    """Validated source record; verification_method identifies its provenance."""
    price_id: Optional[str] = None
    commodity: str
    market: str
    state: Optional[str] = None
    district: Optional[str] = None
    variety: Optional[str] = None
    grade: Optional[str] = None
    min_price_paise: Optional[int] = None
    max_price_paise: Optional[int] = None
    modal_price_paise: Optional[int] = None
    min_price_display: str = "Unavailable"
    max_price_display: str = "Unavailable"
    modal_price_display: str = "Unavailable"
    price_per_kg_paise: Optional[int] = None
    price_per_kg_display: str = "Unavailable"
    unit: str
    crop_name: Optional[str] = None
    category: Optional[str] = None
    price_paise: Optional[int] = None
    price_display: str = "Unavailable"
    currency: str = "INR"
    price_type: str = "unknown"
    observation_date: Optional[date] = None
    source_organization: Optional[str] = None
    source_title: Optional[str] = None
    verification_status: str = "unverified"
    verification_method: Optional[str] = None
    cached: bool = False
    arrival_date: Optional[date] = None
    source: str = "Unknown source"
    retrieved_at: Optional[datetime] = None
    source_url: Optional[str] = None
    source_record_id: Optional[str] = None
    original_price_value: Optional[str] = None
    original_min_value: Optional[str] = None
    original_max_value: Optional[str] = None
    original_unit: Optional[str] = None
    stale: bool = False
    commodity_id: Optional[str] = None
    quote_type: str = "unknown"
    freshness_status: str = "unavailable"
    last_successful_refresh_at: Optional[datetime] = None
    reference_scope: Optional[str] = None
    reference_label: Optional[str] = None
    aggregation_method: Optional[str] = None
    market_type: Optional[str] = None
    observation_count: Optional[int] = None
    observation_dates: List[date] = Field(default_factory=list)
    evidence_ids: List[str] = Field(default_factory=list)


class MarketPriceListResponse(BaseModel):
    """Response containing list of market price records."""
    records: List[MarketPriceItem]
    count: int
    live: bool
    source: str
    message: Optional[str] = None


class MarketPriceQuery(BaseModel):
    """Query parameters for market price lookup."""
    commodity: Optional[str] = None
    market: Optional[str] = None
    state: Optional[str] = None
    district: Optional[str] = None
    limit: int = Field(default=20, ge=1, le=100)
