"""
VayalConnect Backend — User Schemas

Profile management request/response models.
"""

from typing import Optional
from pydantic import BaseModel, Field, ConfigDict
from datetime import datetime
from app.schemas.common import Gender, Language


class UserProfileResponse(BaseModel):
    """User profile visible to the user themselves."""
    id: str
    name: str
    email: str
    phone: str
    address: str
    area_location: str
    gender: str
    age: int
    role: Optional[str] = None
    email_verified: bool
    preferred_language: str
    created_at: Optional[datetime] = None


class UpdateProfileRequest(BaseModel):
    """Profile update — only permitted fields."""
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    phone: Optional[str] = Field(None, pattern=r"^(\+91)?[6-9][0-9]{9}$")
    name: Optional[str] = Field(None, min_length=2, max_length=100)
    address: Optional[str] = Field(None, min_length=5, max_length=500)
    area_location: Optional[str] = Field(None, min_length=2, max_length=200)
    age: Optional[int] = Field(None, ge=18, le=120)
    gender: Optional[Gender] = None


class ChangeLanguageRequest(BaseModel):
    preferred_language: Language
