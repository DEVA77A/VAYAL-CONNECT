"""
VayalConnect Backend — Brevo Email Integration

Send OTP emails through Brevo transactional email API.
Credentials are NEVER exposed to the mobile app.
"""

import sib_api_v3_sdk
from sib_api_v3_sdk.rest import ApiException
import logging
import asyncio
import json
from html import escape

from app.core.config import settings

logger = logging.getLogger(__name__)


def sanitized_provider_error(error: ApiException) -> tuple:
    """Keep only status and allowlisted classifications; never return raw data."""
    status = error.status if type(error.status) is int else None
    code, category = "unknown", "provider_rejection"
    try:
        body = json.loads(error.body or "{}")
        if not isinstance(body, dict):
            return status, code, category
        candidate = body.get("code")
        if candidate in (
            "unauthorized", "permission_denied", "invalid_parameter",
            "missing_parameter", "out_of_range", "not_enough_credits",
            "duplicate_parameter", "document_not_found", "method_not_allowed",
            "too_many_requests", "bad_request",
        ):
            code = candidate
        message = body.get("message", "")
        if isinstance(message, str):
            message = message.lower()
            if "unrecognised ip" in message or "unrecognized ip" in message:
                category = "ip_not_authorized"
            elif "key not found" in message or "invalid api key" in message:
                category = "invalid_api_key"
            elif "sender" in message and ("valid" in message or "verif" in message):
                category = "sender_not_validated"
            elif "credit" in message:
                category = "credits_unavailable"
            elif "account" in message and ("activat" in message or "suspend" in message):
                category = "account_unavailable"
    except (ValueError, TypeError):
        pass
    return status, code, category


def log_provider_error(error: ApiException) -> None:
    status, code, category = sanitized_provider_error(error)
    logger.error(
        "Brevo request failed: status=%s code=%s category=%s",
        status, code, category,
    )


class BrevoEmailService:
    """Send transactional emails via Brevo API."""

    def __init__(self):
        self._configured = bool(settings.BREVO_API_KEY)
        if self._configured:
            configuration = sib_api_v3_sdk.Configuration()
            configuration.host = "https://api.brevo.com/v3"
            configuration.api_key["api-key"] = settings.BREVO_API_KEY
            self.api_instance = sib_api_v3_sdk.TransactionalEmailsApi(
                sib_api_v3_sdk.ApiClient(configuration)
            )
        else:
            logger.warning(
                "Brevo API key not configured. OTP delivery is unavailable."
            )

    async def send_otp_email(self, to_email: str, to_name: str, otp: str) -> bool:
        """
        Send OTP verification email.
        Returns True if sent successfully, False otherwise.
        """
        to_name = escape(to_name)
        subject = "VayalConnect - Email Verification OTP"
        html_content = f"""
        <html>
        <body style="font-family: Arial, sans-serif; padding: 20px;">
            <div style="max-width: 600px; margin: 0 auto; background: #f9f9f9; padding: 30px; border-radius: 10px;">
                <h2 style="color: #2d7a3a;">🌾 VayalConnect / வயல் Connect</h2>
                <p>Hello {to_name},</p>
                <p>Your One-Time Password (OTP) for email verification is:</p>
                <div style="background: #2d7a3a; color: white; font-size: 32px; font-weight: bold;
                            text-align: center; padding: 20px; border-radius: 8px; letter-spacing: 8px;
                            margin: 20px 0;">
                    {otp}
                </div>
                <p>This OTP is valid for <strong>10 minutes</strong>.</p>
                <p style="color: #888; font-size: 12px;">
                    If you did not request this OTP, please ignore this email.
                    Do not share your OTP with anyone.
                </p>
                <hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;">
                <p style="color: #888; font-size: 11px;">
                    நம்ம வயல், நேரடி CONNECT<br>
                    VayalConnect - Agricultural Marketplace
                </p>
            </div>
        </body>
        </html>
        """

        if not self._configured:
            return False

        try:
            send_smtp_email = sib_api_v3_sdk.SendSmtpEmail(
                to=[{"email": to_email, "name": to_name}],
                sender={
                    "email": settings.BREVO_SENDER_EMAIL,
                    "name": settings.BREVO_SENDER_NAME,
                },
                subject=subject,
                html_content=html_content,
            )
            response = await asyncio.to_thread(
                self.api_instance.send_transac_email, send_smtp_email, _request_timeout=10
            )
            if not getattr(response, "message_id", None):
                logger.error("Brevo request failed: category=missing_message_id")
                return False
            logger.info("Email provider accepted the message.")
            return True
        except ApiException as error:
            log_provider_error(error)
            return False
        except Exception:
            logger.error("Brevo request failed: category=transport_or_client_error")
            return False

    async def send_password_reset_email(
        self, to_email: str, to_name: str, otp: str
    ) -> bool:
        """Send password reset OTP email."""
        to_name = escape(to_name)
        subject = "VayalConnect - Password Reset OTP"
        html_content = f"""
        <html>
        <body style="font-family: Arial, sans-serif; padding: 20px;">
            <div style="max-width: 600px; margin: 0 auto; background: #f9f9f9; padding: 30px; border-radius: 10px;">
                <h2 style="color: #2d7a3a;">🌾 VayalConnect / வயல் Connect</h2>
                <p>Hello {to_name},</p>
                <p>Your OTP for password reset is:</p>
                <div style="background: #d9534f; color: white; font-size: 32px; font-weight: bold;
                            text-align: center; padding: 20px; border-radius: 8px; letter-spacing: 8px;
                            margin: 20px 0;">
                    {otp}
                </div>
                <p>This OTP is valid for <strong>10 minutes</strong>.</p>
                <p style="color: #888;">If you did not request a password reset, please secure your account immediately.</p>
            </div>
        </body>
        </html>
        """

        if not self._configured:
            return False

        try:
            send_smtp_email = sib_api_v3_sdk.SendSmtpEmail(
                to=[{"email": to_email, "name": to_name}],
                sender={
                    "email": settings.BREVO_SENDER_EMAIL,
                    "name": settings.BREVO_SENDER_NAME,
                },
                subject=subject,
                html_content=html_content,
            )
            response = await asyncio.to_thread(
                self.api_instance.send_transac_email, send_smtp_email, _request_timeout=10
            )
            if not getattr(response, "message_id", None):
                logger.error("Brevo request failed: category=missing_message_id")
                return False
            logger.info("Email provider accepted the message.")
            return True
        except ApiException as error:
            log_provider_error(error)
            return False
        except Exception:
            logger.error("Brevo request failed: category=transport_or_client_error")
            return False


# Singleton
brevo_service = BrevoEmailService()
