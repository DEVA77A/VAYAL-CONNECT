"""Opt-in local MongoDB/API tests. Synthetic accounts, isolated databases, mocked email."""
import os
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, patch
import httpx
import pytest
from motor.motor_asyncio import AsyncIOMotorClient
from app.core.config import settings
from app.core.database import get_database
from app.main import app

@pytest.mark.skipif(os.environ.get('VAYALCONNECT_RUN_MONGO_TESTS') != '1', reason='Opt-in isolated local MongoDB test')
@pytest.mark.asyncio
@pytest.mark.parametrize('role', ['FARMER', 'BUYER'])
async def test_local_mongo_registration_flow(role):
    assert settings.MONGODB_URI.startswith(('mongodb://localhost:', 'mongodb://127.0.0.1:'))
    client = AsyncIOMotorClient(settings.MONGODB_URI, tz_aware=True, serverSelectionTimeoutMS=5000)
    db = client['vayalconnect_auth_checks_' + uuid.uuid4().hex[:8]]
    app.dependency_overrides[get_database] = lambda: db
    captured = {}
    async def send(email, name, code):
        captured[email] = code
        return True
    email = 'synthetic@example.invalid'
    data = dict(name='Synthetic Test', email=email, phone='9876543210', password='SyntheticTest123!', address='Test address', area_location='Test village', gender='other', age=30)
    try:
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test') as api:
            with patch('app.services.auth_service.brevo_service.send_otp_email', side_effect=send):
                assert (await api.post('/api/v1/auth/register', json=data)).status_code == 201
                credentials = dict(email=email, password=data['password'])
                assert (await api.post('/api/v1/auth/login', json=credentials)).status_code == 403
                assert (await api.post('/api/v1/auth/select-role', json={'role': role})).status_code == 401
                otp_request = dict(email=email, purpose='REGISTRATION')
                assert (await api.post('/api/v1/auth/request-otp', json=otp_request)).status_code == 200
                assert (await api.post('/api/v1/auth/request-otp', json=otp_request)).status_code == 429
                assert (await api.post('/api/v1/auth/verify-otp', json=dict(otp_request, otp='000000'))).status_code != 200
                verify_request = dict(otp_request, otp=captured[email])
                assert (await api.post('/api/v1/auth/verify-otp', json=verify_request)).status_code == 200
                assert (await api.post('/api/v1/auth/verify-otp', json=verify_request)).status_code != 200
                login = await api.post('/api/v1/auth/login', json=credentials)
                assert login.status_code == 200
                headers = {'Authorization': 'Bearer ' + login.json()['data']['access_token']}
                assert (await api.post('/api/v1/auth/select-role', json={'role': 'ADMIN'}, headers=headers)).status_code != 200
                assert (await api.post('/api/v1/auth/select-role', json={'role': role}, headers=headers)).status_code == 200
                login = await api.post('/api/v1/auth/login', json=credentials)
                assert login.status_code == 200 and login.json()['data']['user']['role'] == role
                assert (await api.post('/api/v1/auth/login', json=dict(credentials, password='WrongPassword123!'))).status_code == 401
                await db.otp_verifications.update_many({'email': email}, {'$set': {'created_at': datetime.now(timezone.utc)-timedelta(seconds=61)}})
                assert (await api.post('/api/v1/auth/request-otp', json=otp_request)).status_code == 200
                await db.otp_verifications.update_many({'email': email, 'is_used': False}, {'$set': {'expires_at': datetime.now(timezone.utc)-timedelta(seconds=1)}})
                assert (await api.post('/api/v1/auth/verify-otp', json=dict(otp_request, otp=captured[email]))).status_code != 200
            with patch('app.services.auth_service.brevo_service.send_otp_email', AsyncMock(return_value=False)):
                failure = await api.post('/api/v1/auth/request-otp', json={'email': 'failure@example.invalid', 'purpose': 'REGISTRATION'})
                assert failure.status_code == 503
                assert await db.otp_verifications.count_documents({'email': 'failure@example.invalid', 'is_used': False}) == 0
    finally:
        app.dependency_overrides.clear()
        client.close()
        # Leave isolated synthetic test data; never delete existing databases or users.
