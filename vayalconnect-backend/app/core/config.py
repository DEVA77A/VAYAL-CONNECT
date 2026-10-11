"""
VayalConnect Backend — Core Configuration

All settings loaded from environment variables.
No secrets hardcoded. No defaults for sensitive values.
"""

from typing import List, Optional
from pydantic_settings import BaseSettings
from pydantic import Field, model_validator
import hashlib


class Settings(BaseSettings):
    """Application settings from environment variables."""

    # Application
    APP_ENV: str = "development"
    APP_NAME: str = "VayalConnect"
    APP_VERSION: str = "1.1.0"
    DEBUG: bool = False

    # MongoDB
    MONGODB_URI: str
    MONGODB_DATABASE: str = "vayalconnect"

    # JWT
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # Brevo (Email OTP)
    BREVO_API_KEY: str = ""
    BREVO_SENDER_EMAIL: str = "vayalconnect@gmail.com"
    BREVO_SENDER_NAME: str = "Vayal Connect"

    # Government Market Price API
    GOVERNMENT_MARKET_API_KEY: str = ""
    GOVERNMENT_MARKET_API_BASE_URL: str = (
        "https://api.data.gov.in/resource/9ef84268-d588-465a-a308-a864a43d0070"
    )

    ORDER_RESERVATION_MINUTES: int = Field(30, ge=5, le=120)
    DELIVERY_SPEED_KMH: float = Field(30, gt=0, le=120)
    DELIVERY_DISTANCE_FACTOR: float = Field(1.5, ge=1, le=5)
    DELIVERY_PREPARATION_HOURS: int = Field(24, ge=0, le=168)

    # Razorpay
    RAZORPAY_KEY_ID: str = ""
    RAZORPAY_KEY_SECRET: str = ""
    RAZORPAY_WEBHOOK_SECRET: str = ""

    # Encryption (Fernet key for bank details)
    ENCRYPTION_KEY: str = ""

    # Rate Limiting
    RATE_LIMIT_AUTH: str = "10/minute"
    RATE_LIMIT_OTP: str = "5/hour"
    RATE_LIMIT_GENERAL: str = "100/minute"

    # CORS
    CORS_ORIGINS: str = '["*"]'

    # Media
    MEDIA_STORAGE_PROVIDER: str = "local"
    MEDIA_STORAGE_BASE_URL: str = "/media"

    # Admin
    ADMIN_EMAIL: str = ""
    ADMIN_PASSWORD: str = ""

    @model_validator(mode="after")
    def production_secrets(self):
        if self.is_production:
            if self.JWT_SECRET.startswith("your-") or "change-this" in self.JWT_SECRET.lower() or len(self.JWT_SECRET) < 32 or hashlib.sha256(self.JWT_SECRET.encode()).hexdigest() == "93302424403b692cc563209fc6ef4694a83ff784d1ce3fa292fb6bffde2d4b39":
                raise ValueError("Production JWT_SECRET must be a fresh private value of at least 32 characters.")
            if hashlib.sha256(self.ENCRYPTION_KEY.encode()).hexdigest() == "6200e62e9a41165720a66b144dff157d24e79b372f117a41c04530c67973db5f":
                raise ValueError("Production bank encryption key matches an exposed test fixture. Complete the documented coordinated key rotation.")
            from cryptography.fernet import Fernet
            try:
                Fernet(self.ENCRYPTION_KEY.encode())
            except Exception:
                raise ValueError("Production ENCRYPTION_KEY must be a valid private Fernet key.") from None
        return self

    @property
    def cors_origins_list(self) -> List[str]:
        """Parse CORS origins from JSON string."""
        import json
        try:
            return json.loads(self.CORS_ORIGINS)
        except (json.JSONDecodeError, TypeError):
            return ["*"]

    @property
    def ALLOWED_ORIGINS(self) -> List[str]:
        """Alias for CORS origins."""
        return self.cors_origins_list

    @property
    def is_production(self) -> bool:
        return self.APP_ENV == "production"

    @property
    def is_development(self) -> bool:
        return self.APP_ENV == "development"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True
        hide_input_in_errors = True


# Singleton settings instance
settings = Settings()
