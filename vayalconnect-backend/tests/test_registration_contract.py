from unittest.mock import AsyncMock

import pytest
from pydantic import ValidationError
from app.schemas.auth import RegisterRequest, OTPRequest
from app.services.auth_service import AuthService
from app.core.exceptions import EmailAlreadyExistsError, PhoneAlreadyExistsError


def registration_payload():
    return dict(name="Synthetic Test", email="safe@example.invalid", phone="9876543210",
                password="SyntheticTest123!", address="Test address", area_location="Village",
                gender="other", age=30, preferred_language="en")


def test_current_flutter_payload_matches_schema():
    request = RegisterRequest(**registration_payload())
    assert request.area_location == "Village"
    assert OTPRequest(email=request.email, purpose="REGISTRATION").purpose.value == "REGISTRATION"


@pytest.mark.parametrize("field,value", [("phone", "invalid-phone"), ("email", "invalid-email"),
                                         ("age", 17), ("password", "lowercaseonly")])
def test_invalid_registration_identifies_field(field, value):
    payload = registration_payload()
    payload[field] = value
    with pytest.raises(ValidationError) as error:
        RegisterRequest(**payload)
    assert error.value.errors()[0]["loc"] == (field,)


def test_lowercase_otp_purpose_is_rejected():
    with pytest.raises(ValidationError) as error:
        OTPRequest(email="safe@example.invalid", purpose="registration")
    assert error.value.errors()[0]["loc"] == ("purpose",)


@pytest.mark.asyncio
@pytest.mark.parametrize("duplicate", ["email", "phone"])
async def test_duplicate_registration_preserves_existing_account(mock_db, duplicate):
    service = AuthService(mock_db)
    service.user_repo = AsyncMock()
    service.user_repo.find_by_email.return_value = {"id": "existing"} if duplicate == "email" else None
    service.user_repo.find_by_phone.return_value = {"id": "existing"} if duplicate == "phone" else None
    error = EmailAlreadyExistsError if duplicate == "email" else PhoneAlreadyExistsError
    with pytest.raises(error) as caught:
        await service.register(registration_payload())
    assert caught.value.status_code == 409
    service.user_repo.create.assert_not_awaited()
    service.user_repo.set_email_verified.assert_not_awaited()
