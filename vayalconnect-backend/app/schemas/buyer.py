"""
VayalConnect Backend — Buyer Schemas
"""

from typing import Optional
from pydantic import BaseModel
from datetime import datetime


class BuyerProfileResponse(BaseModel):
    """Buyer profile visible to the buyer."""
    user_id: str
    name: str
    email: str
    phone: str
    address: str
    area_location: str
    gender: str
    age: int
    business_name: Optional[str] = None
    created_at: Optional[datetime] = None


class UpdateBuyerProfileRequest(BaseModel):
    """Buyer profile update."""
    business_name: Optional[str] = None
    business_type: Optional[str] = None
