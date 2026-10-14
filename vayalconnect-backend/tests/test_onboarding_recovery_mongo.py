"""Regression checks on a disposable LOCAL replica-set database, never Atlas."""
import os
import uuid
from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch

import httpx
import pytest
import pytest_asyncio
from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorClient

from app.core.database import get_database
from app.core.security import create_access_token
from app.main import create_app
from app.repositories.farmers import FarmerRepository
from app.services.auth_service import AuthService
from app.services.onboarding_service import OnboardingService
from tests.conftest import complete_farmer
from tests.test_milestone_onboarding import reference
from tests.market_fixtures import discovery

pytestmark = [pytest.mark.asyncio, pytest.mark.skipif(
    os.environ.get("VAYALCONNECT_RUN_MONGO_TESTS") != "1", reason="Opt-in isolated local MongoDB")]


@pytest_asyncio.fixture
async def workflow():
    client = AsyncIOMotorClient("mongodb://127.0.0.1:27019/?replicaSet=vayal_verification",
                               tz_aware=True, serverSelectionTimeoutMS=5000)
    name = "vayal_onboarding_" + uuid.uuid4().hex
    db = client[name]
    app = create_app()
    ids = {role: ObjectId() for role in ("FARMER", "ADMIN", "BUYER", "OTHER")}
    try:
        await client.admin.command("ping")
        await db.farmer_profiles.create_index("user_id", unique=True)
        await db.create_collection("audit_logs")
        for role, identifier in ids.items():
            await db.users.insert_one({"_id": identifier, "role": "FARMER" if role == "OTHER" else role,
                "name": role, "email": role.lower() + "@example.invalid", "phone": "9876543210",
                "is_active": True, "email_verified": True, "is_approved": True,
                "password_hash": "unchanged-test-only-password-hash", "session_version": 7,
                "created_at": datetime.now(timezone.utc)})
        await db.farmer_profiles.insert_one(complete_farmer(user_id=ids["OTHER"], approval_status="REJECTED"))
        await db.commission_configs.insert_one({"status": "ACTIVE", "version": 1, "commission_percentage_bps": 1500})
        app.dependency_overrides[get_database] = lambda: db
        app.state.database_ready = True  # The fixture initialized its disposable DB.
        def headers(role):
            # Deliberately claim ADMIN in a BUYER token: persisted role must win.
            return {"Authorization": "Bearer " + create_access_token({"sub": str(ids[role]),
                    "role": "ADMIN", "session_version": 7})}
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://local-test") as api:
            yield db, api, ids, headers
    finally:
        app.dependency_overrides.clear()
        assert name.startswith("vayal_onboarding_")
        await client.drop_database(name)
        client.close()


@pytest.mark.parametrize("bank_first", [True, False])
async def test_missing_profile_submission_review_and_marketplace(workflow, bank_first):
    db, api, ids, headers = workflow
    farmer = str(ids["FARMER"])
    user_before = await db.users.find_one({"_id": ids["FARMER"]})
    other_before = await db.farmer_profiles.find_one({"user_id": ids["OTHER"]})
    application = {"farm_name": "Test farm", "farm_address": "10 Test farm road",
        "pickup_address": "10 Test pickup road", "crops": "Paddy", "application_revision": 0,
        "coordinates": {"latitude": 9.92, "longitude": 78.12}}
    bank = {"account_holder_name": "Test Farmer", "bank_name": "Test Bank",
            "account_number": "123456789012", "ifsc": "TEST0123456"}
    listing = {"product_name": "Paddy", "category": "Grains", "quantity": 20,
        "quantity_unit": "KG", "quality_grade": "A", "location": "Madurai", "market": "Madurai",
        "harvest_date": datetime.now(timezone.utc).date().isoformat(), "selling_price_per_unit_paise": 4321}
    async def put(path, body, role="FARMER"):
        return await api.put("/api/v1/" + path, json=body, headers=headers(role))
    async def publish():
        return await api.post("/api/v1/products/", json=listing, headers=headers("FARMER"))
    async def visible():
        response = await api.get("/api/v1/products/", headers=headers("BUYER"))
        assert response.status_code == 200, response.text
        return response.json()["data"]
    approve = f"admin/farmers/{farmer}/approve"
    reject = f"admin/farmers/{farmer}/reject"

    profile = await api.get("/api/v1/farmers/me/profile", headers=headers("FARMER"))
    assert profile.status_code == 200 and not profile.json()["data"]["profile_present"]
    pending = await api.get("/api/v1/admin/farmers?status=PENDING", headers=headers("ADMIN"))
    assert pending.status_code == 200, pending.text
    assert pending.json()["data"]["total"] == 1
    item = pending.json()["data"]["items"][0]
    assert item["user_id"] == farmer and not item["profile_present"] and item["submitted_at"] is None
    assert await FarmerRepository(db).count_by_status("PENDING") == 1
    detail = await api.get(f"/api/v1/admin/farmers/{farmer}", headers=headers("ADMIN"))
    assert detail.status_code == 200 and not detail.json()["data"]["profile_present"]
    assert await db.farmer_profiles.count_documents({"user_id": ids["FARMER"]}) == 0  # GET never repairs data.
    assert (await publish()).status_code == 403
    assert (await put(approve, {}, "ADMIN")).status_code == 404
    assert (await put("farmers/me/application", application, "BUYER")).status_code == 403
    assert (await put("farmers/me/bank", bank, "BUYER")).status_code == 403
    assert (await api.get("/api/v1/admin/farmers", headers=headers("BUYER"))).status_code == 403
    assert (await put("farmers/me/application", application | {"application_revision": 9})).status_code == 409
    assert await db.farmer_profiles.count_documents({"user_id": ids["FARMER"]}) == 0

    writes = [("farmers/me/bank", bank), ("farmers/me/application", application)]
    if not bank_first:
        writes.reverse()
    for path, body in writes:
        saved = await put(path, body)
        assert saved.status_code == 200, saved.text
    stored = await db.farmer_profiles.find_one({"user_id": ids["FARMER"]})
    assert stored["approval_status"] == "PENDING" and stored["application_revision"] == 1
    assert stored["bank_account_number"] != bank["account_number"]
    assert not (await db.users.find_one({"_id": ids["FARMER"]}))["is_approved"]
    assert (await put("farmers/me/application", application)).status_code == 409
    assert (await publish()).status_code == 403
    assert (await put(reject, {"reason": "Correct farm details", "application_revision": 1}, "ADMIN")).status_code == 200
    assert (await db.farmer_profiles.find_one({"user_id": ids["FARMER"]}))["rejection_reason"] == "Correct farm details"
    assert (await publish()).status_code == 403
    assert (await put("farmers/me/application", application | {"application_revision": 1})).status_code == 200
    assert (await put(approve, {"application_revision": 1}, "ADMIN")).status_code == 409
    assert (await put(approve, {"application_revision": 2}, "BUYER")).status_code == 403
    # Failure between the profile decision and account flag must roll back both.
    with patch("app.repositories.users.UserRepository.update", AsyncMock(side_effect=RuntimeError("test write failure"))):
        with pytest.raises(RuntimeError):
            await OnboardingService(db).decide(farmer, 2, str(ids["ADMIN"]), True)
    assert (await db.farmer_profiles.find_one({"user_id": ids["FARMER"]}))["approval_status"] == "PENDING"
    assert not (await db.users.find_one({"_id": ids["FARMER"]}))["is_approved"]
    assert (await put(approve, {"application_revision": 2}, "ADMIN")).status_code == 200
    approved = await db.farmer_profiles.find_one({"user_id": ids["FARMER"]})
    assert approved["_id"] == stored["_id"] and approved["approval_status"] == "APPROVED"
    assert approved["reviewed_by"] == ids["ADMIN"]
    assert (await db.users.find_one({"_id": ids["FARMER"]}))["is_approved"]
    assert (await put(approve, {"application_revision": 2}, "ADMIN")).status_code == 409
    assert await db.farmer_profiles.find_one({"user_id": ids["OTHER"]}) == other_before
    assert await db.farmer_profiles.count_documents({"user_id": ids["FARMER"]}) == 1

    with patch("app.services.pricing_service.MarketDiscoveryService.lookup", AsyncMock(return_value=discovery([reference()]))):
        created = await publish()
    assert created.status_code == 201, created.text
    pid = created.json()["data"]["product_id"]
    doc = await db.products.find_one({"_id": ObjectId(pid)})
    for changes in ({"status": "INACTIVE"}, {"is_active": False}, {"quantity_available": 0}, {"farmer_id": ids["OTHER"]}):
        await db.products.insert_one({k: v for k, v in doc.items() if k != "_id"} | changes)
    assert (await visible())["total"] == 1
    assert (await visible())["items"][0]["product_id"] == pid
    # Correcting an approved farm requires another explicit review.
    assert (await put("farmers/me/application", application | {"application_revision": 2})).status_code == 200
    assert (await visible())["total"] == 0
    assert (await publish()).status_code == 403
    assert (await db.farmer_profiles.find_one({"user_id": ids["FARMER"]}))["bank_account_number"] == stored["bank_account_number"]
    assert (await put(approve, {"application_revision": 3}, "ADMIN")).status_code == 200
    assert (await visible())["total"] == 1
    assert (await put(reject, {"reason": "Approval revoked", "application_revision": 3}, "ADMIN")).status_code == 200
    assert (await visible())["total"] == 0
    assert (await api.get("/api/v1/products/" + pid, headers=headers("BUYER"))).status_code == 404
    assert (await publish()).status_code == 403
    assert (await api.put("/api/v1/products/" + pid, json={"status": "ACTIVE"}, headers=headers("FARMER"))).status_code == 403
    after = await db.users.find_one({"_id": ids["FARMER"]})
    assert all(after[k] == user_before[k] for k in ("_id", "email", "password_hash", "role", "session_version"))


async def test_role_selection_rolls_back_when_profile_creation_fails(workflow):
    db, _, _, _ = workflow
    identifier = (await db.users.insert_one({"role": None, "email_verified": True,
                    "password_hash": "preserve-existing", "session_version": 3})).inserted_id
    with patch("app.repositories.farmers.FarmerRepository.create", AsyncMock(side_effect=RuntimeError("test insert failure"))):
        with pytest.raises(RuntimeError):
            await AuthService(db).select_role(str(identifier), "FARMER")
    user = await db.users.find_one({"_id": identifier})
    assert user["role"] is None and user["password_hash"] == "preserve-existing"
    assert user["session_version"] == 3
    await AuthService(db).select_role(str(identifier), "FARMER")
    assert (await db.users.find_one({"_id": identifier}))["role"] == "FARMER"
    assert (await db.farmer_profiles.find_one({"user_id": identifier}))["approval_status"] == "PENDING"


async def test_invalid_stored_application_is_clear_validation_error(workflow):
    db, api, ids, headers = workflow
    await db.farmer_profiles.insert_one(complete_farmer(user_id=ids["FARMER"], approval_status="PENDING",
        submitted_at=datetime.now(timezone.utc), application_revision=1, application={"farm_name": ""}))
    response = await api.put(f"/api/v1/admin/farmers/{ids['FARMER']}/approve",
                            json={"application_revision": 1}, headers=headers("ADMIN"))
    assert response.status_code == 422
    assert "correct and resubmit" in response.json()["error"]["message"]
    assert (await db.farmer_profiles.find_one({"user_id": ids["FARMER"]}))["approval_status"] == "PENDING"


async def test_unverified_farmer_cannot_create_missing_profile(workflow):
    db, api, ids, headers = workflow
    await db.users.update_one({"_id": ids["FARMER"]}, {"$set": {"email_verified": False}})
    for path, body in [
        ("application", {"farm_name": "Test farm", "farm_address": "10 Test farm road",
                         "pickup_address": "10 Test farm road", "crops": "Paddy"}),
        ("bank", {"account_holder_name": "Test Farmer", "bank_name": "Test Bank",
                  "account_number": "123456789012", "ifsc": "TEST0123456"}),
    ]:
        response = await api.put("/api/v1/farmers/me/" + path, json=body, headers=headers("FARMER"))
        assert response.status_code == 403 and "Verify your email" in response.json()["error"]["message"]
    assert await db.farmer_profiles.count_documents({"user_id": ids["FARMER"]}) == 0
