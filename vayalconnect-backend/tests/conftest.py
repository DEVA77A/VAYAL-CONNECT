"""
Pytest configuration and global fixtures.
Sets up mock environment variables and test clients.
"""

import os

# Set environment variables for test suite before importing settings
os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("MONGODB_URI", "mongodb://localhost:27017")
os.environ.setdefault("MONGODB_DATABASE", "vayalconnect_test")
os.environ.setdefault("JWT_SECRET", "super-secret-jwt-key-vayalconnect-dev-test-12345")
os.environ.setdefault("ENCRYPTION_KEY", "s8zP_XWkY_wM8mQ6E9kL1B7V3C5xZ2A0T9qR8vU4oI4=")
os.environ.setdefault("RAZORPAY_KEY_ID", "rzp_test_mock")
os.environ.setdefault("RAZORPAY_KEY_SECRET", "rzp_secret_mock")
os.environ.setdefault("RAZORPAY_WEBHOOK_SECRET", "rzp_webhook_mock")
os.environ.setdefault("BREVO_API_KEY", "brevo_mock")
os.environ.setdefault("GOVERNMENT_MARKET_API_KEY", "gov_mock")

import pytest
from unittest.mock import AsyncMock
from motor.motor_asyncio import AsyncIOMotorDatabase


@pytest.fixture
def mock_db():
    db = AsyncMock(spec=AsyncIOMotorDatabase)
    return db
