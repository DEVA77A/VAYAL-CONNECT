from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch
import pytest
from sib_api_v3_sdk.rest import ApiException
from app.integrations.brevo import BrevoEmailService
from app.services.otp_service import OTPService
from app.core.security import generate_otp, hash_otp
from app.core.exceptions import OTPCooldownError, OTPInvalidError

@pytest.mark.asyncio
@pytest.mark.parametrize('reset', [False, True])
@pytest.mark.parametrize('failure', [401, 403, 400, 429, 'timeout', 'network', 'missing_id'])
async def test_provider_failures_are_safe(reset, failure, caplog):
    mail = BrevoEmailService()
    mail._configured = True
    mail.api_instance = MagicMock()
    diagnostic = 'private-provider-diagnostic'
    if isinstance(failure, int):
        mail.api_instance.send_transac_email.side_effect = ApiException(status=failure, reason=diagnostic)
    elif failure == 'timeout':
        mail.api_instance.send_transac_email.side_effect = TimeoutError(diagnostic)
    elif failure == 'network':
        mail.api_instance.send_transac_email.side_effect = OSError(diagnostic)
    else:
        mail.api_instance.send_transac_email.return_value = MagicMock(message_id=None)
    code = generate_otp()
    method = mail.send_password_reset_email if reset else mail.send_otp_email
    assert await method('recipient@example.invalid', 'Test', code) is False
    assert code not in caplog.text and diagnostic not in caplog.text

@pytest.mark.asyncio
async def test_official_brevo_endpoint_header_and_message_contract():
    with patch('app.integrations.brevo.settings.BREVO_API_KEY', 'unit-test-only-credential'), patch('app.integrations.brevo.settings.BREVO_SENDER_EMAIL', 'vayalconnect@gmail.com'), patch('app.integrations.brevo.settings.BREVO_SENDER_NAME', 'Vayal Connect'):
        mail = BrevoEmailService()
    assert mail.api_instance.api_client.configuration.host == 'https://api.brevo.com/v3'
    assert mail.api_instance.api_client.configuration.api_key['api-key'] == 'unit-test-only-credential'
    code = generate_otp()
    with patch.object(mail.api_instance.api_client, 'call_api', return_value=MagicMock(message_id='accepted')) as call:
        assert await mail.send_otp_email('recipient@example.invalid', 'Test', code)
    args, kwargs = call.call_args
    assert args[0] == '/smtp/email' and args[1] == 'POST'
    assert 'api-key' in kwargs['auth_settings']
    body = kwargs['body']
    assert body.sender == {'email': 'vayalconnect@gmail.com', 'name': 'Vayal Connect'}
    assert body.to[0]['email'] == 'recipient@example.invalid'
    assert code in body.html_content
    assert kwargs['_request_timeout'] == 10

@pytest.mark.asyncio
async def test_resend_cooldown_blocks_code_generation():
    collection = AsyncMock()
    db = MagicMock()
    db.__getitem__.return_value = collection
    collection.find_one.return_value = {'created_at': datetime.now(timezone.utc)}
    with pytest.raises(OTPCooldownError):
        await OTPService(db).create_otp('test@example.invalid', 'REGISTRATION')
    collection.insert_one.assert_not_awaited()

@pytest.mark.asyncio
async def test_concurrent_consumption_cannot_reuse_code():
    collection = AsyncMock()
    db = MagicMock()
    db.__getitem__.return_value = collection
    from datetime import timedelta
    code = generate_otp()
    record = {'_id': 'test-record', 'attempts': 0, 'max_attempts': 5,
        'expires_at': datetime.now(timezone.utc)+timedelta(minutes=10), 'otp_hash': hash_otp(code)}
    collection.find_one.return_value = record
    collection.find_one_and_update.return_value = record
    collection.update_one.return_value = MagicMock(modified_count=0)
    with pytest.raises(OTPInvalidError):
        await OTPService(db).verify('test@example.invalid', code, 'REGISTRATION')
    assert collection.update_one.await_args.args[0]['is_used'] is False
