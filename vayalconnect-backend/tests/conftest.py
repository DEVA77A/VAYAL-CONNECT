"""
Pytest configuration and global fixtures.
Sets up mock environment variables and test clients.
"""

import os
import secrets
from cryptography.fernet import Fernet

# Set environment variables for test suite before importing settings
os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("MONGODB_URI", "mongodb://localhost:27017")
os.environ.setdefault("MONGODB_DATABASE", "vayalconnect_test")
os.environ["JWT_SECRET"] = secrets.token_urlsafe(48)
os.environ["ENCRYPTION_KEY"] = Fernet.generate_key().decode()
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


@pytest.fixture(autouse=True)
def unit_transaction_adapter(monkeypatch):
    """Unit mocks execute callbacks; real Motor databases retain real transactions.

    Rollback/concurrency guarantees are separately exercised against a replica set.
    """
    from unittest.mock import Mock
    import app.core.transactions as transactions
    real = transactions.run_transaction
    async def run(db, operation):
        if isinstance(db, Mock):
            return await operation()
        return await real(db, operation)
    monkeypatch.setattr(transactions, "run_transaction", run)


def complete_farmer(**changes):
    from app.core.security import encrypt_value
    return {"approval_status": "APPROVED", "application": {
        "farm_name": "Isolated test farm", "farm_address": "10 Isolated test farm road",
        "pickup_address": "10 Isolated test farm road", "crops": "Paddy",
        "coordinates": {"latitude": 9.92, "longitude": 78.12}},
        "bank_account_holder_name": encrypt_value("Test Farmer"),
        "bank_name": encrypt_value("Test Bank"), "bank_account_number": encrypt_value("123456789012"),
        "bank_ifsc": encrypt_value("TEST0123456"), **changes}
