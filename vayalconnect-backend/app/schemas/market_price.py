"""
VayalConnect Backend — Market Price Schemas

Defines response structures for official Government AGMARKNET mandi rates.
"""

from typing import Optional, List
from pydantic import BaseModel, Field
from datetime import date, datetime


class MarketPriceItem(BaseModel):
    """Normalized market price record from data.gov.in AGMARKNET."""
    price_id: Optional[str] = None
    commodity: str
    market: str
    state: str
    district: str
    variety: Optional[str] = None
    grade: Optional[str] = None
    min_price_paise: int = 0
    max_price_paise: int = 0
    modal_price_paise: int = 0
    min_price_display: str = "₹0.00"
    max_price_display: str = "₹0.00"
    modal_price_display: str = "₹0.00"
    price_per_kg_paise: int = 0
    price_per_kg_display: str = "₹0.00"
    unit: str = "Quintal"
    arrival_date: Optional[date] = None
    source: str = "data.gov.in AGMARKNET"
    retrieved_at: Optional[datetime] = None


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
