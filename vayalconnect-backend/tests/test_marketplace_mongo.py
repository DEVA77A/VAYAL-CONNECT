"""Actual local MongoDB safety checks; only a unique disposable test DB is removed."""
import asyncio
import os
import uuid
import secrets
from unittest.mock import patch, AsyncMock
import httpx
from datetime import datetime, timezone
from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorClient
import pytest
from app.repositories.products import ProductRepository
from app.services.report_service import ReportService
from app.services.auth_service import AuthService
from app.core.exceptions import InvalidTokenError
from app.core.security import create_refresh_token

@pytest.mark.skipif(os.environ.get("VAYALCONNECT_RUN_MONGO_TESTS") != "1", reason="Opt-in local isolated MongoDB")
@pytest.mark.asyncio
async def test_visibility_finance_inventory_and_revocation_with_real_mongo():
    client = AsyncIOMotorClient("mongodb://127.0.0.1:27017", tz_aware=True, serverSelectionTimeoutMS=5000)
    name = "vayalconnect_milestone_checks_" + uuid.uuid4().hex
    db = client[name]
    now = datetime.now(timezone.utc)
    seller = ObjectId()
    profile = {"user_id": seller, "approval_status": "PENDING"}
    try:
        # Provision a genuine hashed administrator in the disposable DB only.
        from scripts.seed_admin import seed_admin
        from app.main import app
        from app.core.database import get_database
        from app.core.security import verify_password, create_access_token
        password = secrets.token_urlsafe(24) + "A1"
        with patch("scripts.seed_admin.connect_db", AsyncMock()), patch("scripts.seed_admin.close_db", AsyncMock()), patch("scripts.seed_admin.get_database", return_value=db):
            await seed_admin("admin@example.invalid", password, "9876543210")
        admin = await db.users.find_one({"email": "admin@example.invalid"})
        assert admin["role"] == "ADMIN" and verify_password(password, admin["password_hash"])
        assert await db.audit_logs.count_documents({"action": "ADMIN_PROVISIONED"}) == 1
        login = await AuthService(db).login("admin@example.invalid", password)
        assert login["user"]["role"] == "ADMIN"
        buyer = ObjectId()
        await db.users.insert_one({"_id": buyer, "role": "BUYER", "is_active": True, "email_verified": True})
        app.dependency_overrides[get_database] = lambda: db
        try:
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://local-test") as api:
                admin_headers = {"Authorization": "Bearer " + login["access_token"]}
                buyer_headers = {"Authorization": "Bearer " + create_access_token({"sub": str(buyer), "role": "ADMIN"})}
                # Backend persisted identity governs authorization, even if a token role differs.
                assert (await api.get("/api/v1/admin/dashboard", headers=admin_headers)).status_code == 200
                assert (await api.get("/api/v1/admin/dashboard", headers=buyer_headers)).status_code == 403
                await AuthService(db).logout(str(admin["_id"]))
                assert (await api.get("/api/v1/admin/dashboard", headers=admin_headers)).status_code == 401
        finally:
            app.dependency_overrides.pop(get_database, None)
        await db.users.insert_one({"_id": seller, "role": "FARMER", "is_active": True, "email_verified": True})
        await db.farmer_profiles.insert_one(profile)
        product_id = (await db.products.insert_one({"farmer_id": seller, "is_active": True, "status": "ACTIVE", "quantity_available": 1, "created_at": now})).inserted_id
        repo = ProductRepository(db)
        assert await repo.list_active() == ([], 0)
        await db.farmer_profiles.update_one({"user_id": seller}, {"$set": {"approval_status": "APPROVED"}})
        assert (await repo.list_active())[1] == 1
        assert await repo.find_active_by_id(str(product_id)) is not None
        await db.users.update_one({"_id": seller}, {"$set": {"is_active": False}})
        assert await repo.find_active_by_id(str(product_id)) is None
        await db.users.update_one({"_id": seller}, {"$set": {"is_active": True}})
        reservations = await asyncio.gather(repo.atomic_reserve_quantity(str(product_id), 1), repo.atomic_reserve_quantity(str(product_id), 1))
        assert sum(result is not None for result in reservations) == 1
        assert await repo.list_active() == ([], 0)
        for state, paid, commission in [("PENDING_PAYMENT", "CREATED", 900), ("COMPLETED", "CAPTURED", 100), ("REFUNDED", "REFUNDED", 800), ("COMPLETED", "FAILED", 700)]:
            await db.orders.insert_one({"order_status": state, "payment_status": paid, "commission_total_paise": commission, "buyer_total_paise": commission*5, "farmer_total_payout_paise": commission*4, "quantity": 1, "created_at": now})
        metrics = await ReportService(db).get_dashboard_metrics(period="today")
        assert metrics["total_orders"] == 4
        assert metrics["total_platform_commission_paise"] == 100
        auth = AuthService(db)
        token = create_refresh_token({"sub": str(seller), "role": "FARMER", "session_version": 0})
        await auth._store_refresh_token(str(seller), token)
        rotated = await auth.refresh_access_token(token)
        assert rotated["refresh_token"] != token
        with pytest.raises(InvalidTokenError): await auth.refresh_access_token(token)
        await auth.logout(str(seller))
        assert (await db.users.find_one({"_id": seller}))["session_version"] == 1
        with pytest.raises(InvalidTokenError): await auth.refresh_access_token(rotated["refresh_token"])
    finally:
        assert name.startswith("vayalconnect_milestone_checks_")
        await client.drop_database(name)
        client.close()
