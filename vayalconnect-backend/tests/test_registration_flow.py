from unittest.mock import AsyncMock, patch
import pytest
from app.services.auth_service import AuthService
from app.core.security import generate_otp
from app.core.exceptions import ForbiddenError

@pytest.mark.asyncio
@pytest.mark.parametrize('role', ['FARMER', 'BUYER'])
async def test_registration_verification_and_role_login(mock_db, role):
    service = AuthService(mock_db)
    service.user_repo = AsyncMock()
    service.farmer_repo = AsyncMock()
    service.buyer_repo = AsyncMock()
    service.audit_service = AsyncMock()
    service.otp_service = AsyncMock()
    service._store_refresh_token = AsyncMock()
    user = {}
    async def create(doc):
        user.update(doc, id='000000000000000000000001')
        return user['id']
    async def lookup(email): return user or None
    async def verified(email): user['email_verified'] = True
    async def assigned(user_id, selected): user['role'] = selected
    service.user_repo.create.side_effect = create
    service.user_repo.find_by_email.side_effect = lookup
    service.user_repo.find_by_phone.return_value = None
    service.user_repo.find_by_id.side_effect = lambda _: user
    service.user_repo.set_email_verified.side_effect = verified
    service.user_repo.set_role.side_effect = assigned
    data = dict(name='Synthetic Test', email='test@example.invalid', phone='9876543210', password='SyntheticTest123!', address='Test address', area_location='Test village', gender='other', age=30)
    await service.register(data)
    with pytest.raises(ForbiddenError): await service.login(data['email'], data['password'])
    with pytest.raises(ForbiddenError): await service.select_role(user['id'], role)
    service.otp_service.create_otp.return_value = generate_otp()
    service.otp_service.verify.return_value = True
    with patch('app.services.auth_service.brevo_service.send_otp_email', AsyncMock(return_value=True)):
        await service.request_otp(data['email'], 'REGISTRATION')
    await service.verify_otp(data['email'], service.otp_service.create_otp.return_value, 'REGISTRATION')
    await service.login(data['email'], data['password'])
    with pytest.raises(ForbiddenError): await service.select_role(user['id'], 'ADMIN')
    await service.select_role(user['id'], role)
    assert (await service.login(data['email'], data['password']))['user']['role'] == role
