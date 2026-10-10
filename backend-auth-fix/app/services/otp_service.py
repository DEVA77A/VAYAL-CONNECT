"""
VayalConnect Backend — OTP Service

Handles OTP generation, storage, verification, expiry, and rate limiting.
OTPs are bcrypt-hashed before storage. Never stored in plaintext.
"""

from datetime import datetime, timedelta, timezone
from typing import Optional
from motor.motor_asyncio import AsyncIOMotorDatabase
import logging

from app.core.security import generate_otp, hash_otp, verify_otp
from app.core.exceptions import (
    OTPExpiredError, OTPInvalidError, OTPMaxAttemptsError, OTPCooldownError,
)

logger = logging.getLogger(__name__)

OTP_EXPIRY_MINUTES = 10
OTP_MAX_ATTEMPTS = 5
OTP_RESEND_COOLDOWN_SECONDS = 60


class OTPService:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.collection = db["otp_verifications"]

    async def create_otp(self, email: str, purpose: str) -> str:
        """
        Generate and store a new OTP.
        Enforces resend cooldown. Returns the plaintext OTP for sending.
        """
        email = email.lower().strip()

        # Check cooldown — prevent OTP spam
        recent = await self.collection.find_one(
            {
                "email": email,
                "purpose": purpose,
                "created_at": {
                    "$gte": datetime.now(timezone.utc) - timedelta(seconds=OTP_RESEND_COOLDOWN_SECONDS)
                },
            },
            sort=[("created_at", -1)],
        )
        if recent:
            elapsed = (datetime.now(timezone.utc) - recent["created_at"]).total_seconds()
            remaining = int(OTP_RESEND_COOLDOWN_SECONDS - elapsed)
            if remaining > 0:
                raise OTPCooldownError(remaining)

        # Invalidate previous OTPs for this email+purpose
        await self.collection.update_many(
            {"email": email, "purpose": purpose, "is_used": False},
            {"$set": {"is_used": True}},
        )

        # Generate new OTP
        otp = generate_otp()
        otp_hash = hash_otp(otp)

        await self.collection.insert_one({
            "email": email,
            "otp_hash": otp_hash,
            "purpose": purpose,
            "attempts": 0,
            "max_attempts": OTP_MAX_ATTEMPTS,
            "expires_at": datetime.now(timezone.utc) + timedelta(minutes=OTP_EXPIRY_MINUTES),
            "is_used": False,
            "created_at": datetime.now(timezone.utc),
        })

        # Return plaintext OTP to be sent via email — NEVER logged in production
        return otp

    async def invalidate(self, email: str, purpose: str):
        """Invalidate an undelivered OTP without leaving an active code."""
        await self.collection.update_many(
            {"email": email.lower().strip(), "purpose": purpose, "is_used": False},
            {"$set": {"is_used": True}},
        )

    async def verify(self, email: str, otp: str, purpose: str) -> bool:
        """
        Verify an OTP. Enforces expiry and attempt limits.
        Returns True if valid. Raises specific exceptions on failure.
        """
        email = email.lower().strip()

        record = await self.collection.find_one(
            {"email": email, "purpose": purpose, "is_used": False},
            sort=[("created_at", -1)],
        )

        if not record:
            raise OTPInvalidError()

        # Check expiry
        if datetime.now(timezone.utc) > record["expires_at"]:
            await self.collection.update_one(
                {"_id": record["_id"]},
                {"$set": {"is_used": True}},
            )
            raise OTPExpiredError()

        # Check max attempts
        if record["attempts"] >= record["max_attempts"]:
            await self.collection.update_one(
                {"_id": record["_id"]},
                {"$set": {"is_used": True}},
            )
            raise OTPMaxAttemptsError()

        # Increment attempt count
        await self.collection.update_one(
            {"_id": record["_id"]},
            {"$inc": {"attempts": 1}},
        )

        # Verify OTP hash
        if not verify_otp(otp, record["otp_hash"]):
            # Check if this was the last attempt
            if record["attempts"] + 1 >= record["max_attempts"]:
                await self.collection.update_one(
                    {"_id": record["_id"]},
                    {"$set": {"is_used": True}},
                )
                raise OTPMaxAttemptsError()
            raise OTPInvalidError()

        # Mark as used
        await self.collection.update_one(
            {"_id": record["_id"]},
            {"$set": {"is_used": True}},
        )

        return True
