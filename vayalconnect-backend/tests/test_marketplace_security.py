from tests.conftest import complete_farmer
from unittest.mock import AsyncMock, MagicMock, patch
import pytest
from app.api.deps import get_approved_farmer
from app.core.exceptions import ForbiddenError, PaymentVerificationFailedError, ValidationError
from app.services.payment_service import PaymentService
from app.schemas.auth import RegisterRequest


@pytest.mark.asyncio
@pytest.mark.parametrize("state", ["PENDING", "REJECTED", "SUSPENDED", None])
async def test_unapproved_farmer_cannot_publish(state):
    with patch("app.repositories.farmers.FarmerRepository.find_by_user_id", AsyncMock(return_value=None if state is None else {"approval_status": state})):
        with pytest.raises(ForbiddenError):
            await get_approved_farmer({"id": "test", "role": "FARMER", "is_active": True, "email_verified": True}, MagicMock())


@pytest.mark.asyncio
async def test_approved_farmer_can_publish():
    user = {"id": "test", "role": "FARMER", "is_active": True, "email_verified": True}
    with patch("app.repositories.farmers.FarmerRepository.find_by_user_id", AsyncMock(return_value=complete_farmer())):
        assert await get_approved_farmer(user, MagicMock()) == user


@pytest.mark.asyncio
@pytest.mark.parametrize("verified", [True, False])
async def test_payment_is_bound_to_its_stored_order_even_on_retry(verified):
    service = PaymentService(MagicMock())
    service.payment_repo.find_by_razorpay_order_id = AsyncMock(return_value={"order_id": "stored", "buyer_id": "buyer", "signature_verified": verified})
    service.order_repo.update_status = AsyncMock()
    with pytest.raises(ForbiddenError):
        await service.verify_payment("different", "gateway-order", "gateway-payment", "synthetic", "buyer")
    service.order_repo.update_status.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("change", [{"status": "authorized"}, {"amount": 999}, {"order_id": "different"}, {"currency": "USD"}])
async def test_signature_alone_cannot_mark_order_paid(change):
    service = PaymentService(MagicMock())
    service.payment_repo.find_by_razorpay_order_id = AsyncMock(return_value={"id": "payment", "order_id": "order", "buyer_id": "buyer", "razorpay_order_id": "gateway-order", "signature_verified": False, "amount_paise": 100, "currency": "INR"})
    service.payment_repo.find_by_razorpay_payment_id = AsyncMock(return_value=None)
    service.order_repo.update_status = AsyncMock()
    body = {"id": "gateway-payment", "order_id": "gateway-order", "status": "captured", "amount": 100, "currency": "INR", **change}
    with patch("app.services.payment_service.razorpay_payment.verify_payment_signature", AsyncMock(return_value=True)), patch("app.services.payment_service.razorpay_payment.fetch_payment", AsyncMock(return_value=body)):
        with pytest.raises(PaymentVerificationFailedError):
            await service.verify_payment("order", "gateway-order", "gateway-payment", "synthetic", "buyer")
    service.order_repo.update_status.assert_not_awaited()


@pytest.mark.asyncio
async def test_provisioning_never_promotes_existing_buyer():
    from scripts.seed_admin import seed_admin
    with patch("scripts.seed_admin.connect_db", AsyncMock()), patch("scripts.seed_admin.close_db", AsyncMock()), patch("scripts.seed_admin.get_database", return_value=AsyncMock()) as database, patch("scripts.seed_admin.collection") as locks, patch("scripts.seed_admin.UserRepository") as repo:
        locks.return_value.update_one = AsyncMock()
        database.return_value.__getitem__.return_value.update_one = AsyncMock()
        repo.return_value.find_by_email = AsyncMock(return_value={"role": "BUYER"})
        repo.return_value.create = AsyncMock()
        with pytest.raises(ValidationError):
            await seed_admin("admin@example.invalid", "SyntheticProvision123!", "9876543210")
        repo.return_value.create.assert_not_awaited()


def test_coordinate_pair_is_optional_and_range_validated():
    from tests.test_registration_contract import registration_payload
    from pydantic import ValidationError as PydanticError
    assert RegisterRequest(**registration_payload()).latitude is None
    assert RegisterRequest(**registration_payload(), latitude=0, longitude=0).latitude == 0
    for coordinates in ({"latitude": 10}, {"latitude": 91, "longitude": 10}, {"latitude": 10, "longitude": float('nan')}):
        with pytest.raises(PydanticError): RegisterRequest(**registration_payload(), **coordinates)


@pytest.mark.asyncio
async def test_reused_order_key_never_returns_another_buyers_record():
    from app.services.order_service import OrderService
    service = OrderService(MagicMock())
    service.order_repo.find_by_idempotency_key = AsyncMock(return_value={"buyer_id": "owner", "product_id": "product", "quantity": 1})
    with pytest.raises(ForbiddenError):
        await service.create_order("other-buyer", "product", 1, "test-key")


@pytest.mark.asyncio
async def test_sequential_payment_retry_reuses_gateway_order():
    service = PaymentService(MagicMock())
    service.order_repo.find_by_id = AsyncMock(return_value={"buyer_id": "buyer", "order_status": "PENDING_PAYMENT", "buyer_total_paise": 100})
    service.payment_repo.find_by_order_id = AsyncMock(return_value={"id": "payment", "razorpay_order_id": "existing-gateway-order", "amount_paise": 100, "payment_status": "CREATED"})
    with patch("app.services.payment_service.razorpay_payment.create_order", AsyncMock()) as gateway:
        result = await service.create_payment("order", "buyer")
        assert result["razorpay_order_id"] == "existing-gateway-order"
        gateway.assert_not_awaited()


def test_live_gateway_keys_are_disabled():
    from app.integrations.razorpay import RazorpayPaymentProvider
    with patch("app.integrations.razorpay.settings.RAZORPAY_KEY_ID", "rzp_live_synthetic"), patch("app.integrations.razorpay.settings.RAZORPAY_KEY_SECRET", "unit-test-only"):
        assert RazorpayPaymentProvider()._configured is False


def test_new_passwords_reject_bcrypt_truncation_and_weak_reset():
    from app.schemas.auth import ResetPasswordRequest
    from app.core.security import hash_password
    from pydantic import ValidationError as SchemaValidationError
    with pytest.raises(ValueError): hash_password('A1'+'x'*71)
    with pytest.raises(SchemaValidationError): ResetPasswordRequest(email='test@example.invalid',otp='123456',new_password='weakpassword')
    with pytest.raises(SchemaValidationError): ResetPasswordRequest(email='test@example.invalid',otp='123456',new_password='A1'+'x'*71)


def test_production_settings_require_private_strong_jwt_without_echoing_inputs():
    from app.core.config import Settings
    from cryptography.fernet import Fernet
    from pydantic import ValidationError as SchemaValidationError
    with pytest.raises(SchemaValidationError) as error:
        Settings(APP_ENV='production',JWT_SECRET='unsafe-short-fixture',ENCRYPTION_KEY=Fernet.generate_key().decode())
    assert 'unsafe-short-fixture' not in str(error.value)
    with pytest.raises(SchemaValidationError):
        Settings(APP_ENV='production',JWT_SECRET='your-super-secret-jwt-key-change-this-in-production',ENCRYPTION_KEY=Fernet.generate_key().decode())
    with pytest.raises(SchemaValidationError):
        Settings(APP_ENV='production',JWT_SECRET='PrivateFixture123!'*4,ENCRYPTION_KEY='invalid-fixture-key')


@pytest.mark.asyncio
async def test_validation_responses_never_echo_submitted_password():
    import httpx
    from app.main import create_app
    from app.core.database import get_database
    app=create_app();app.dependency_overrides[get_database]=lambda:AsyncMock()
    from tests.test_registration_contract import registration_payload
    payload=registration_payload();payload['password']='private-invalid-password-marker'
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app),base_url='http://isolated-test') as client:
        response=await client.post('/api/v1/auth/register',json=payload)
    assert response.status_code==422
    assert payload['password'] not in response.text
    assert response.json()['error']['code']=='VALIDATION_ERROR'
