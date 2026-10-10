from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch
import pytest
from app.integrations.brevo import BrevoEmailService
from app.services.auth_service import AuthService
from app.services.otp_service import OTPService
from app.core.security import generate_otp, hash_otp
from app.core.exceptions import EmailDeliveryError, OTPExpiredError, OTPInvalidError, OTPMaxAttemptsError

@pytest.mark.asyncio
@pytest.mark.parametrize("reset", [False, True])
async def test_unconfigured_never_succeeds_or_logs_code(caplog, reset):
    with patch("app.integrations.brevo.settings.BREVO_API_KEY", ""):
        mail = BrevoEmailService()
    method = mail.send_password_reset_email if reset else mail.send_otp_email
    code = generate_otp()
    assert await method("test@example.com", "User", code) is False
    assert code not in caplog.text

@pytest.mark.asyncio
@pytest.mark.parametrize("accepted", [True, False])
async def test_provider_acceptance_and_failure(accepted):
    mail = BrevoEmailService()
    mail._configured = True
    mail.api_instance = MagicMock()
    if accepted:
        mail.api_instance.send_transac_email.return_value = MagicMock(message_id="accepted-id")
    else:
        mail.api_instance.send_transac_email.side_effect = RuntimeError("sensitive provider response")
    assert await mail.send_otp_email("test@example.com", "User", generate_otp()) is accepted

@pytest.mark.asyncio
async def test_request_failure_invalidates_and_returns_safe_error(mock_db):
    service = AuthService(mock_db)
    service.otp_service = AsyncMock()
    service.user_repo = AsyncMock()
    service.user_repo.find_by_email.return_value = None
    with patch("app.services.auth_service.brevo_service.send_otp_email", AsyncMock(return_value=False)):
        with pytest.raises(EmailDeliveryError):
            await service.request_otp("test@example.com", "REGISTRATION")
    service.otp_service.invalidate.assert_awaited_once_with("test@example.com", "REGISTRATION")

@pytest.mark.asyncio
async def test_request_accepted(mock_db):
    service = AuthService(mock_db)
    service.otp_service = AsyncMock()
    service.user_repo = AsyncMock()
    service.user_repo.find_by_email.return_value = None
    with patch("app.services.auth_service.brevo_service.send_otp_email", AsyncMock(return_value=True)):
        assert "accepted" in (await service.request_otp("test@example.com", "REGISTRATION"))["message"]

@pytest.mark.asyncio
@pytest.mark.parametrize("state", ["expired", "invalid", "limited", "valid", "used"])
async def test_otp_states(state):
    collection = AsyncMock()
    db = MagicMock()
    db.__getitem__.return_value = collection
    code = generate_otp()
    record = {"_id": "record", "otp_hash": hash_otp(code), "attempts": 0,
              "max_attempts": 5, "expires_at": datetime.now(timezone.utc)+timedelta(minutes=10)}
    if state == "expired": record["expires_at"] = datetime.now(timezone.utc)-timedelta(seconds=1)
    if state == "limited": record["attempts"] = 5
    collection.find_one.return_value = None if state == "used" else record
    collection.find_one_and_update.return_value = record
    collection.update_one.return_value = MagicMock(modified_count=1)
    service = OTPService(db)
    if state == "valid":
        assert await service.verify("test@example.com", code, "REGISTRATION")
        assert collection.update_one.await_args.args[1] == {"$set": {"is_used": True}}
    else:
        error = {"expired": OTPExpiredError, "limited": OTPMaxAttemptsError}.get(state, OTPInvalidError)
        with pytest.raises(error):
            await service.verify("test@example.com", "000000" if state == "invalid" else code, "REGISTRATION")

def test_secure_otp_format():
    assert all(len(code := generate_otp()) == 6 and code.isdigit() for _ in range(100))

@pytest.mark.asyncio
@pytest.mark.parametrize("role", ["FARMER", "BUYER", "ADMIN"])
async def test_verified_login_preserves_backend_role(mock_db, role):
    from app.core.security import hash_password, decode_token
    service = AuthService(mock_db)
    service.user_repo = AsyncMock()
    service.audit_service = AsyncMock()
    service._store_refresh_token = AsyncMock()
    service.user_repo.find_by_email.return_value = {
        "id": "000000000000000000000001", "name": "Test", "email": "test@example.com",
        "password_hash": hash_password("TestPassword123!"), "is_active": True,
        "email_verified": True, "role": role,
    }
    result = await service.login("test@example.com", "TestPassword123!")
    assert result["user"]["role"] == role
    assert decode_token(result["access_token"])["role"] == role

@pytest.mark.asyncio
@pytest.mark.parametrize("state", ["unknown", "unverified", "wrong_password"])
async def test_login_rejects_invalid_accounts(mock_db, state):
    from app.core.security import hash_password
    from app.core.exceptions import InvalidCredentialsError, ForbiddenError
    service = AuthService(mock_db)
    service.user_repo = AsyncMock()
    service.user_repo.find_by_email.return_value = None if state == "unknown" else {
        "password_hash": hash_password("TestPassword123!"), "is_active": True,
        "email_verified": state != "unverified",
    }
    with pytest.raises(ForbiddenError if state == "unverified" else InvalidCredentialsError):
        await service.login("test@example.com", "WrongPassword123!" if state == "wrong_password" else "TestPassword123!")

@pytest.mark.asyncio
async def test_registration_verification_updates_account(mock_db):
    service = AuthService(mock_db)
    service.otp_service = AsyncMock()
    service.otp_service.verify.return_value = True
    service.user_repo = AsyncMock()
    assert await service.verify_otp("TEST@example.com", generate_otp(), "REGISTRATION")
    service.user_repo.set_email_verified.assert_awaited_once_with("test@example.com")
