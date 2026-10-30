"""
VayalConnect Backend — Authentication Schemas

Request/response models for registration, login, OTP, and tokens.
"""

from typing import Optional
from pydantic import BaseModel, Field, field_validator, model_validator
from app.schemas.common import UserRole, Gender, Language, OTPPurpose
from app.utils.validators import is_valid_email, is_valid_phone


def validate_password_policy(v: str) -> str:
    """Validate password against security policy.

    Requirements:
    - Minimum 8 characters, maximum 128 characters, at most 72 UTF-8 bytes (bcrypt limit).
    - At least one uppercase letter.
    - At least one number.
    """
    if len(v.encode("utf-8")) > 72:
        raise ValueError("Password must be at most 72 UTF-8 bytes.")
    if len(v) < 8:
        raise ValueError("Password must be at least 8 characters long.")
    missing = []
    if not any(c.isupper() for c in v):
        missing.append("one uppercase letter")
    if not any(c.isdigit() for c in v):
        missing.append("one number")
    if missing:
        reqs = " and ".join(missing)
        raise ValueError(f"Your password must contain at least {reqs}.")
    return v


class RegisterRequest(BaseModel):
    """User registration request."""
    name: str = Field(..., min_length=2, max_length=100)
    email: str = Field(..., max_length=255)
    phone: str = Field(..., max_length=20)
    password: str = Field(..., min_length=8, max_length=128)
    address: str = Field(..., min_length=5, max_length=500)
    area_location: str = Field(..., min_length=2, max_length=200)
    gender: Gender
    age: int = Field(..., ge=18, le=120)
    preferred_language: Language = Language.ENGLISH

    latitude: Optional[float] = Field(None, ge=-90, le=90, allow_inf_nan=False)
    longitude: Optional[float] = Field(None, ge=-180, le=180, allow_inf_nan=False)

    @model_validator(mode="after")
    def coordinate_pair(self):
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("Provide both latitude and longitude, or neither.")
        return self

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        v = v.lower().strip()
        if not is_valid_email(v):
            raise ValueError("Invalid email format")
        return v

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        v = v.strip()
        if not is_valid_phone(v):
            raise ValueError("Invalid phone number format")
        return v

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        return validate_password_policy(v)


class RegisterResponse(BaseModel):
    user_id: str
    message: str = "Registration successful. Please verify your email."


class OTPRequest(BaseModel):
    """OTP request."""
    email: str = Field(..., max_length=255)
    purpose: OTPPurpose = OTPPurpose.REGISTRATION

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        return v.lower().strip()


class OTPVerifyRequest(BaseModel):
    """OTP verification request."""
    email: str = Field(..., max_length=255)
    otp: str = Field(..., min_length=6, max_length=6)
    purpose: OTPPurpose = OTPPurpose.REGISTRATION

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        return v.lower().strip()


class OTPResponse(BaseModel):
    message: str


class OTPVerifyResponse(BaseModel):
    verified: bool
    message: str = ""


class RoleSelectRequest(BaseModel):
    """Role selection after OTP verification."""
    role: UserRole

    @field_validator("role")
    @classmethod
    def validate_role(cls, v: UserRole) -> UserRole:
        if v == UserRole.ADMIN:
            raise ValueError("Admin accounts cannot be self-assigned")
        return v


class RoleSelectResponse(BaseModel):
    role: str
    message: str


class LoginRequest(BaseModel):
    """Login request."""
    email: str = Field(..., max_length=255)
    password: str = Field(..., max_length=128)

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        return v.lower().strip()


class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: "UserBasicInfo"


class UserBasicInfo(BaseModel):
    id: str
    name: str
    email: str
    role: Optional[str] = None
    preferred_language: str = "en"


class RefreshTokenRequest(BaseModel):
    refresh_token: str


class RefreshTokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(..., min_length=8)
    new_password: str = Field(..., min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def validate_new_password(cls, v: str) -> str:
        return validate_password_policy(v)


class ForgotPasswordRequest(BaseModel):
    email: str = Field(..., max_length=255)

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        return v.lower().strip()


class ResetPasswordRequest(BaseModel):
    email: str = Field(..., max_length=255)
    otp: str = Field(..., min_length=6, max_length=6)
    new_password: str = Field(..., min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def validate_reset_password(cls, v: str) -> str:
        return validate_password_policy(v)

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        return v.lower().strip()
