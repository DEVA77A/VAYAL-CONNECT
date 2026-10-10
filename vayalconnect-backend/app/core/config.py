"""
VayalConnect Backend — Core Configuration

All settings loaded from environment variables.
No secrets hardcoded. No defaults for sensitive values.
"""

from typing import List, Optional
from pydantic_settings import BaseSettings
from pydantic import Field


class Settings(BaseSettings):
    """Application settings from environment variables."""

    # Application
    APP_ENV: str = "development"
    APP_NAME: str = "VayalConnect"
    APP_VERSION: str = "1.0.0"
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


# Singleton settings instance
settings = Settings()
