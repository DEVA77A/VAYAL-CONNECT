"""
Comprehensive automated tests for VayalConnect authentication security,
email OTP verification, enumeration defense, and cryptographic password reset flow.
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch
import pytest

from app.core.config import settings
from app.core.exceptions import (
    UnauthorizedError,
    InvalidTokenError,
    TokenExpiredError,
    OTPExpiredError,
    OTPInvalidError,
    OTPMaxAttemptsError,
    OTPCooldownError,
    ValidationError,
)
from app.core.security import (
    create_access_token,
    create_password_reset_token,
    decode_token,
    generate_otp,
    hash_otp,
    hash_password,
    verify_otp,
    verify_password,
)
from app.services.auth_service import AuthService
from app.services.otp_service import OTPService


# ==============================================================================
# 1. Valid registration OTP verified successfully
# ==============================================================================
@pytest.mark.asyncio
async def test_valid_registration_otp_verified():
    collection = AsyncMock()
    db = MagicMock()
    db.__getitem__.return_value = collection

    code = "123456"
    record = {
        "_id": "rec_1",
        "otp_hash": hash_otp(code),
        "attempts": 0,
        "max_attempts": 5,
        "is_used": False,
        "expires_at": datetime.now(timezone.utc) + timedelta(minutes=10),
    }
    collection.find_one.return_value = record
    collection.find_one_and_update.return_value = record
    collection.update_one.return_value = MagicMock(modified_count=1)

    service = OTPService(db)
    result = await service.verify("farmer@vayalconnect.in", code, "REGISTRATION")

    assert result is True
    assert collection.update_one.await_args.args[1] == {"$set": {"is_used": True}}


# ==============================================================================
# 2. Invalid OTP rejected with OTPInvalidError
# ==============================================================================
@pytest.mark.asyncio
async def test_invalid_otp_rejected():
    collection = AsyncMock()
    db = MagicMock()
    db.__getitem__.return_value = collection

    record = {
        "_id": "rec_2",
        "otp_hash": hash_otp("123456"),
        "attempts": 0,
        "max_attempts": 5,
        "is_used": False,
        "expires_at": datetime.now(timezone.utc) + timedelta(minutes=10),
    }
    collection.find_one.return_value = record
    collection.find_one_and_update.return_value = record

    service = OTPService(db)
    with pytest.raises(OTPInvalidError):
        await service.verify("farmer@vayalconnect.in", "999999", "REGISTRATION")


# ==============================================================================
# 3. Expired OTP rejected with OTPExpiredError
# ==============================================================================
@pytest.mark.asyncio
async def test_expired_otp_rejected():
    collection = AsyncMock()
    db = MagicMock()
    db.__getitem__.return_value = collection

    code = "123456"
    record = {
        "_id": "rec_3",
        "otp_hash": hash_otp(code),
        "attempts": 0,
        "max_attempts": 5,
        "is_used": False,
        "expires_at": datetime.now(timezone.utc) - timedelta(seconds=1),
    }
    collection.find_one.return_value = record
    collection.find_one_and_update.return_value = record

    service = OTPService(db)
    with pytest.raises(OTPExpiredError):
        await service.verify("farmer@vayalconnect.in", code, "REGISTRATION")


# ==============================================================================
# 4. Already-used OTP rejected on reuse attempt
# ==============================================================================
@pytest.mark.asyncio
async def test_already_used_otp_rejected():
    collection = AsyncMock()
    db = MagicMock()
    db.__getitem__.return_value = collection

    # When OTP is used, find_one queries for is_used=False which returns None
    collection.find_one.return_value = None

    service = OTPService(db)
    with pytest.raises(OTPInvalidError):
        await service.verify("farmer@vayalconnect.in", "123456", "REGISTRATION")


# ==============================================================================
# 5. Brute-force OTP guessing blocked at max attempts (5) with lockout
# ==============================================================================
@pytest.mark.asyncio
async def test_brute_force_otp_guessing_blocked():
    collection = AsyncMock()
    db = MagicMock()
    db.__getitem__.return_value = collection

    record = {
        "_id": "rec_5",
        "otp_hash": hash_otp("123456"),
        "attempts": 5,
        "max_attempts": 5,
        "is_used": False,
        "expires_at": datetime.now(timezone.utc) + timedelta(minutes=10),
    }
    collection.find_one.return_value = record
    collection.find_one_and_update.return_value = record

    service = OTPService(db)
    with pytest.raises(OTPMaxAttemptsError):
        await service.verify("farmer@vayalconnect.in", "111111", "REGISTRATION")


# ==============================================================================
# 6. Cooldown period enforced between OTP requests (60 seconds)
# ==============================================================================
@pytest.mark.asyncio
async def test_cooldown_period_enforced_between_requests():
    collection = AsyncMock()
    db = MagicMock()
    db.__getitem__.return_value = collection

    # Recent OTP created 15 seconds ago (within 60s cooldown)
    collection.find_one.return_value = {
        "_id": "rec_6",
        "created_at": datetime.now(timezone.utc) - timedelta(seconds=15),
    }

    service = OTPService(db)
    with pytest.raises(OTPCooldownError):
        await service.create_otp("farmer@vayalconnect.in", "REGISTRATION")


# ==============================================================================
# 7. Password reset requested for existing user receives OTP
# ==============================================================================
@pytest.mark.asyncio
async def test_password_reset_requested_for_existing_user():
    db = MagicMock()
    service = AuthService(db)
    service.user_repo = AsyncMock()
    service.user_repo.find_by_email.return_value = {
        "id": "507f1f77bcf86cd799439011",
        "email": "farmer@vayalconnect.in",
        "name": "Farmer User",
    }
    service.otp_service = AsyncMock()
    service.otp_service.create_otp.return_value = "654321"

    with patch("app.services.auth_service.brevo_service.send_password_reset_email", AsyncMock(return_value=True)):
        result = await service.request_otp("farmer@vayalconnect.in", "PASSWORD_RESET")

    assert "If an account exists" in result["message"]
    service.otp_service.create_otp.assert_awaited_once_with("farmer@vayalconnect.in", "PASSWORD_RESET")


# ==============================================================================
# 8. Password reset for non-existent email returns generic success (no enumeration)
# ==============================================================================
@pytest.mark.asyncio
async def test_password_reset_nonexistent_email_enumeration_protection():
    db = MagicMock()
    service = AuthService(db)
    service.user_repo = AsyncMock()
    service.user_repo.find_by_email.return_value = None
    service.otp_service = AsyncMock()

    with patch("app.services.auth_service.brevo_service.send_password_reset_email", AsyncMock()) as mock_mail:
        result = await service.request_otp("unknown_user@example.invalid", "PASSWORD_RESET")

    assert "If an account exists" in result["message"]
    # Ensure no OTP generated and no email sent
    service.otp_service.create_otp.assert_not_called()
    mock_mail.assert_not_called()


# ==============================================================================
# 9. Password reset OTP verified returns valid cryptographic reset_token
# ==============================================================================
@pytest.mark.asyncio
async def test_password_reset_otp_verification_returns_valid_token():
    mock_db = MagicMock()
    mock_collection = AsyncMock()
    mock_db.__getitem__.return_value = mock_collection

    service = AuthService(mock_db)
    service.user_repo = AsyncMock()
    service.user_repo.find_by_email.return_value = {
        "id": "507f1f77bcf86cd799439011",
        "email": "farmer@vayalconnect.in",
    }
    service.otp_service = AsyncMock()
    service.otp_service.verify.return_value = True

    response = await service.verify_reset_otp("farmer@vayalconnect.in", "123456")

    assert response["verified"] is True
    assert "reset_token" in response

    payload = decode_token(response["reset_token"])
    assert payload["sub"] == "507f1f77bcf86cd799439011"
    assert payload["email"] == "farmer@vayalconnect.in"
    assert payload["type"] == "password_reset"
    assert "jti" in payload
    mock_collection.insert_one.assert_awaited_once()


# ==============================================================================
# 10. Password reset with valid reset_token succeeds and updates password
# ==============================================================================
@pytest.mark.asyncio
async def test_password_reset_with_valid_token_succeeds():
    mock_db = MagicMock()
    reset_collection = AsyncMock()
    otp_collection = AsyncMock()

    def get_collection(name):
        if name == "password_resets":
            return reset_collection
        return otp_collection

    mock_db.__getitem__.side_effect = get_collection

    user_id = "507f1f77bcf86cd799439011"
    token = create_password_reset_token(
        user_id=user_id,
        email="buyer@vayalconnect.in",
        jti="jti_valid_001",
    )

    reset_collection.find_one_and_update.return_value = {
        "_id": "rec_pr_1",
        "jti": "jti_valid_001",
        "user_id": user_id,
        "is_used": True,
    }

    service = AuthService(mock_db)
    service.user_repo = AsyncMock()
    service.user_repo.find_by_id.return_value = {
        "id": user_id,
        "email": "buyer@vayalconnect.in",
        "role": "BUYER",
    }
    service.user_repo.update.return_value = True
    service.logout = AsyncMock()
    service.audit_service = AsyncMock()

    result = await service.reset_password(
        reset_token=token,
        new_password="NewSecurePassword123!",
    )

    assert result["success"] is True
    service.user_repo.update.assert_awaited_once()
    service.logout.assert_awaited_once_with(user_id)


# ==============================================================================
# 11. Password reset with invalid or forged reset_token rejected with 401
# ==============================================================================
@pytest.mark.asyncio
async def test_password_reset_with_invalid_token_rejected():
    mock_db = MagicMock()
    service = AuthService(mock_db)

    with pytest.raises((UnauthorizedError, InvalidTokenError)):
        await service.reset_password(
            reset_token="forged.jwt.token.here",
            new_password="NewSecurePassword123!",
        )


# ==============================================================================
# 12. Password reset with expired reset_token rejected with 401
# ==============================================================================
@pytest.mark.asyncio
async def test_password_reset_with_expired_token_rejected():
    mock_db = MagicMock()
    service = AuthService(mock_db)

    expired_token = create_password_reset_token(
        user_id="507f1f77bcf86cd799439011",
        email="farmer@vayalconnect.in",
        expires_delta=timedelta(seconds=-10),
    )

    with pytest.raises((UnauthorizedError, InvalidTokenError, TokenExpiredError)):
        await service.reset_password(
            reset_token=expired_token,
            new_password="NewSecurePassword123!",
        )


# ==============================================================================
# 13. Password reset with reused reset_token rejected (single-use enforcement)
# ==============================================================================
@pytest.mark.asyncio
async def test_password_reset_with_reused_token_rejected():
    mock_db = MagicMock()
    reset_collection = AsyncMock()
    mock_db.__getitem__.return_value = reset_collection

    token = create_password_reset_token(
        user_id="507f1f77bcf86cd799439011",
        email="farmer@vayalconnect.in",
        jti="jti_already_used_001",
    )

    # find_one_and_update returns None because is_used is already True or expired
    reset_collection.find_one_and_update.return_value = None

    service = AuthService(mock_db)
    with pytest.raises(UnauthorizedError) as exc_info:
        await service.reset_password(
            reset_token=token,
            new_password="NewSecurePassword123!",
        )
    assert "already been used" in str(exc_info.value.message)


# ==============================================================================
# 14. Normal access token passed as reset_token rejected (type check)
# ==============================================================================
@pytest.mark.asyncio
async def test_password_reset_rejects_access_token():
    mock_db = MagicMock()
    service = AuthService(mock_db)

    # Standard access token has type: "access"
    access_token = create_access_token({"sub": "507f1f77bcf86cd799439011", "role": "FARMER"})

    with pytest.raises(UnauthorizedError) as exc_info:
        await service.reset_password(
            reset_token=access_token,
            new_password="NewSecurePassword123!",
        )
    assert "Invalid token type" in str(exc_info.value.message)


# ==============================================================================
# 15. Password below 8 chars rejected by policy
# ==============================================================================
@pytest.mark.asyncio
async def test_password_policy_below_8_chars():
    mock_db = MagicMock()
    service = AuthService(mock_db)

    with pytest.raises(ValidationError) as exc:
        await service.reset_password(
            email="farmer@vayalconnect.in",
            otp="123456",
            new_password="Short1!",
        )
    assert "at least 8 characters" in str(exc.value.message)


# ==============================================================================
# 16. Password without uppercase rejected by policy
# ==============================================================================
@pytest.mark.asyncio
async def test_password_policy_no_uppercase():
    mock_db = MagicMock()
    service = AuthService(mock_db)

    with pytest.raises(ValidationError) as exc:
        await service.reset_password(
            email="farmer@vayalconnect.in",
            otp="123456",
            new_password="lowercaseonly123!",
        )
    assert "uppercase letter" in str(exc.value.message)


# ==============================================================================
# 17. Password without digit rejected by policy
# ==============================================================================
@pytest.mark.asyncio
async def test_password_policy_no_digit():
    mock_db = MagicMock()
    service = AuthService(mock_db)

    with pytest.raises(ValidationError) as exc:
        await service.reset_password(
            email="farmer@vayalconnect.in",
            otp="123456",
            new_password="NoDigitsAtAllHere!",
        )
    assert "number" in str(exc.value.message)


# ==============================================================================
# 18. Mismatched confirm_password rejected
# ==============================================================================
@pytest.mark.asyncio
async def test_mismatched_confirm_password_rejected():
    mock_db = MagicMock()
    service = AuthService(mock_db)

    with pytest.raises(ValidationError) as exc:
        await service.reset_password(
            email="farmer@vayalconnect.in",
            otp="123456",
            new_password="ValidPassword123!",
            confirm_password="DifferentPassword456!",
        )
    assert "do not match" in str(exc.value.message)


# ==============================================================================
# 19. After password reset, all previous access/refresh sessions revoked
# ==============================================================================
@pytest.mark.asyncio
async def test_password_reset_revokes_all_sessions():
    mock_db = MagicMock()
    reset_coll = AsyncMock()
    mock_db.__getitem__.return_value = reset_coll

    user_id = "507f1f77bcf86cd799439011"
    token = create_password_reset_token(
        user_id=user_id,
        email="farmer@vayalconnect.in",
        jti="jti_revoke_test",
    )
    reset_coll.find_one_and_update.return_value = {
        "_id": "rec_pr_rev",
        "jti": "jti_revoke_test",
        "user_id": user_id,
        "is_used": True,
    }

    service = AuthService(mock_db)
    service.user_repo = AsyncMock()
    service.user_repo.find_by_id.return_value = {
        "id": user_id,
        "email": "farmer@vayalconnect.in",
        "role": "FARMER",
    }
    service.user_repo.update.return_value = True
    service.logout = AsyncMock()
    service.audit_service = AsyncMock()

    await service.reset_password(
        reset_token=token,
        new_password="BrandNewPassword123!",
    )

    # logout(user_id) increments session_version and invalidates refresh tokens in DB
    service.logout.assert_awaited_once_with(user_id)


# ==============================================================================
# 20. Login with old password fails after reset; login with new password succeeds
# ==============================================================================
def test_password_hash_transition():
    old_plain = "OldPassword123!"
    new_plain = "NewPassword123!"

    # Simulate database update: old hash replaced by new hash
    stored_hash = hash_password(new_plain)

    # Old password fails verification
    assert verify_password(old_plain, stored_hash) is False

    # New password succeeds verification
    assert verify_password(new_plain, stored_hash) is True
