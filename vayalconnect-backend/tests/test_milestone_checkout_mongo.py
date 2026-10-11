"""Real MongoDB + ASGI workflow, with government and payment providers mocked.
Uses and removes ONLY a uniquely named local disposable database.
"""
import os
import uuid
from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch
import httpx
import pytest
from bson import ObjectId
from cryptography.fernet import Fernet
from motor.motor_asyncio import AsyncIOMotorClient
from app.main import app
from app.core.database import get_database
from app.core.security import create_access_token
from app.core.exceptions import ValidationError
from tests.test_milestone_onboarding import reference


@pytest.mark.skipif(os.environ.get("VAYALCONNECT_RUN_MONGO_TESTS") != "1", reason="Opt-in isolated local MongoDB")
@pytest.mark.asyncio
async def test_farmer_application_pricing_fulfillment_and_security():
    client = AsyncIOMotorClient(os.environ.get("VAYALCONNECT_TEST_MONGO_URI", "mongodb://127.0.0.1:27019/?replicaSet=vayal_verification"), tz_aware=True, serverSelectionTimeoutMS=5000)
    name = "vayalconnect_checkout_checks_" + uuid.uuid4().hex
    db = client[name]
    ids = {role: ObjectId() for role in ("FARMER", "ADMIN", "BUYER", "OTHER")}
    def headers(role):
        return {"Authorization": "Bearer " + create_access_token({"sub": str(ids[role]), "role": role})}
    application = {"farm_name": "Test farm", "farm_address": "10 Test farm road", "pickup_address": "10 Pickup farm road", "crops": "Paddy", "delivery_available": True, "application_revision": 0, "coordinates": {"latitude":9.92,"longitude":78.12}}
    listing = {"product_name": "Paddy", "category": "Grains", "quantity": 20, "quantity_unit": "KG", "quality_grade": "A", "location": "Madurai", "market": "Madurai", "harvest_date": datetime.now(timezone.utc).date().isoformat(), "selling_price_per_unit_paise": 4321}
    delivery = {"recipient_name": "Test buyer", "phone": "9876543210", "address": "10 Test buyer road", "postal_code": "625001", "coordinates": {"latitude":9.94,"longitude":78.14}}
    try:
        await client.admin.command("ping")
        for role, identifier in ids.items():
            await db.users.insert_one({"_id": identifier, "role": "BUYER" if role == "OTHER" else role, "name": role, "email": role.lower()+"@example.invalid", "phone": "9876543210", "is_active": True, "email_verified": True})
        await db.farmer_profiles.insert_one({"user_id": ids["FARMER"], "approval_status": "PENDING"})
        await db.commission_configs.insert_one({"status": "ACTIVE", "commission_percentage_bps": 1500, "version": 1})
        app.dependency_overrides[get_database] = lambda: db
        with patch("app.core.security.settings.ENCRYPTION_KEY", Fernet.generate_key().decode()), patch("app.services.pricing_service.market_price_provider.get_market_price", AsyncMock(return_value=reference())), patch("app.services.payment_service.PaymentService.create_payment", AsyncMock(return_value={"razorpay_order_id": "synthetic-test-only"})):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://isolated-test") as api:
                async def put(url, payload, role): return await api.put('/api/v1/'+url, json=payload, headers=headers(role))
                async def post(url, payload, role): return await api.post('/api/v1/'+url, json=payload, headers=headers(role))
                approve = 'admin/farmers/'+str(ids['FARMER'])+'/approve'
                reject = 'admin/farmers/'+str(ids['FARMER'])+'/reject'
                bank = {'account_holder_name': 'Test Farmer', 'bank_name': 'Test Bank', 'account_number': '123456789012', 'ifsc': 'TEST0123456', 'upi_id': None}
                assert (await put('farmers/me/bank', bank, 'BUYER')).status_code == 403
                bank_saved = await put('farmers/me/bank', bank, 'FARMER')
                assert bank_saved.status_code == 200, bank_saved.text
                assert bank_saved.json()['data']['account_number_masked'].endswith('9012')
                assert bank['account_number'] not in bank_saved.text
                stored_farm = await db.farmer_profiles.find_one({'user_id': ids['FARMER']})
                assert stored_farm['bank_account_number'] != bank['account_number'] and not stored_farm['bank_details_verified']
                assert (await put(approve, {}, 'ADMIN')).status_code == 422
                assert (await put('farmers/me/application', application, 'BUYER')).status_code == 403
                assert (await post('products/', listing, 'FARMER')).status_code == 403
                assert (await put('farmers/me/application', application, 'FARMER')).status_code == 200
                assert (await put('farmers/me/application', application, 'FARMER')).status_code == 409
                review = (await api.get('/api/v1/admin/farmers?status=PENDING', headers=headers('ADMIN'))).json()['data']['items'][0]
                assert review['application']['pickup_address'] == application['pickup_address']
                assert (await put(reject, {'reason': 'Correct details', 'application_revision': 1}, 'ADMIN')).status_code == 200
                profile = (await api.get('/api/v1/farmers/me/profile', headers=headers('FARMER'))).json()['data']
                assert profile['rejection_reason'] == 'Correct details'
                assert (await put('farmers/me/application', application | {'application_revision': 1}, 'FARMER')).status_code == 200
                assert (await put(approve, {'application_revision': 1}, 'ADMIN')).status_code == 409
                assert (await put(approve, {'application_revision': 2}, 'BUYER')).status_code == 403
                assert (await put(approve, {'application_revision': 2}, 'ADMIN')).status_code == 200
                # Corrections to an approved application reset approval; checked separately.
                created = await post('products/', listing, 'FARMER')
                assert created.status_code == 201, created.text
                product = created.json()['data']
                assert product['farmer_payout_per_unit_paise'] == 4321
                assert product['market_reference']['reference_price_per_listing_unit_paise'] == 3000
                assert 'buyer_price_per_unit_paise' not in product
                pid = product['product_id']
                viewed = (await api.get('/api/v1/products/'+pid, headers=headers('BUYER'))).json()['data']
                assert viewed['delivery_available'] and viewed['pickup_address'] == application['pickup_address']
                assert viewed['buyer_price_per_unit_paise'] == 4969 and 'farmer_payout_per_unit_paise' not in viewed
                checkout = {'product_id': pid, 'quantity': 2, 'fulfillment_method': 'DELIVERY', 'delivery_address': delivery, 'idempotency_key': uuid.uuid4().hex}
                assert (await post('orders/', checkout | {'delivery_address': None}, 'BUYER')).status_code == 422
                order_response = await post('orders/', checkout, 'BUYER')
                assert order_response.status_code == 201, order_response.text
                order = order_response.json()['data']
                assert order['fulfillment_method'] == 'DELIVERY' and all(order['delivery_address'][key] == value for key,value in delivery.items())
                assert order['payment_status'] == 'PENDING' and order['order_status'] == 'PENDING_PAYMENT'
                assert order['buyer_total_paise'] == 9938 and order['commission_total_paise'] == 1296
                retry = await post('orders/', checkout, 'BUYER')
                assert retry.json()['data']['order_id'] == order['order_id']
                assert (await db.products.find_one({'_id': ObjectId(pid)}))['quantity_available'] == 18
                assert (await post('orders/', checkout | {'fulfillment_method': 'PICKUP', 'delivery_address': None}, 'BUYER')).status_code == 422
                assert (await api.get('/api/v1/orders/'+order['order_id'], headers=headers('OTHER'))).status_code == 404
                await db.commission_configs.update_one({'status': 'ACTIVE'}, {'$set': {'commission_percentage_bps': 2000, 'version': 2}})
                pickup = await post('orders/', {'product_id': pid, 'quantity': 1, 'fulfillment_method': 'PICKUP', 'idempotency_key': uuid.uuid4().hex}, 'BUYER')
                assert pickup.status_code == 201, pickup.text
                stale = await post('orders/', {'product_id': pid, 'quantity': 1, 'fulfillment_method': 'PICKUP', 'expected_unit_price_paise': 4969, 'idempotency_key': uuid.uuid4().hex}, 'BUYER')
                assert stale.status_code == 409 and stale.json()['error']['code'] == 'PRICE_CHANGED'
                assert (await db.products.find_one({'_id': ObjectId(pid)}))['quantity_available'] == 17
                assert pickup.json()['data']['buyer_total_paise'] == 5185
                assert pickup.json()['data']['pickup_address'] == application['pickup_address']
                assert (await db.orders.find_one({'_id': ObjectId(order['order_id'])}))['buyer_total_paise'] == 9938
                assert (await api.put('/api/v1/orders/'+order['order_id']+'/cancel', json={}, headers=headers('OTHER'))).status_code == 403
                await db.farmer_profiles.update_one({'user_id': ids['FARMER']}, {'$set': {'application.delivery_available': False}})
                assert (await post('orders/', checkout | {'idempotency_key': uuid.uuid4().hex}, 'BUYER')).status_code == 422
                assert (await put(reject, {'reason': 'Approval revoked', 'application_revision': 2}, 'ADMIN')).status_code == 200
                assert (await api.get('/api/v1/products/'+pid, headers=headers('BUYER'))).status_code == 404
    finally:
        app.dependency_overrides.pop(get_database, None)
        assert name.startswith('vayalconnect_checkout_checks_')
        await client.drop_database(name)
        client.close()
