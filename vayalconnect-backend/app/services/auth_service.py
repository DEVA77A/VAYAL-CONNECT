"""
VayalConnect Backend — Auth Service

Handles registration, login, token management, password reset.
"""

from typing import Optional, Dict, Any
from datetime import datetime, timedelta, timezone
from motor.motor_asyncio import AsyncIOMotorDatabase
from bson import ObjectId
import secrets
import hashlib
import re
import logging

from jose import JWTError
from app.core.security import (
    hash_password, verify_password,
    create_access_token, create_refresh_token, create_password_reset_token, decode_token,
    hash_otp, verify_otp as verify_otp_hash,
)
from app.core.config import settings
from app.core.transactions import transactional
from app.core.exceptions import (
    InvalidCredentialsError, UnauthorizedError,
    EmailAlreadyExistsError, PhoneAlreadyExistsError,
    ValidationError, NotFoundError, ForbiddenError,
    InvalidTokenError, TokenExpiredError, EmailDeliveryError,
)
from app.repositories.users import UserRepository
from app.repositories.farmers import FarmerRepository
from app.repositories.buyers import BuyerRepository
from app.services.otp_service import OTPService
from app.services.audit_service import AuditService
from app.integrations.brevo import brevo_service

logger = logging.getLogger(__name__)


class AuthService:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.db = db
        self.user_repo = UserRepository(db)
        self.farmer_repo = FarmerRepository(db)
        self.buyer_repo = BuyerRepository(db)
        self.otp_service = OTPService(db)
        self.audit_service = AuditService(db)
        self.refresh_tokens_collection = db["refresh_tokens"]

    async def register(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Register a new user. Email and phone must be unique."""
        email = data["email"].lower().strip()
        phone = data["phone"].strip()

        # Check uniqueness
        existing_email = await self.user_repo.find_by_email(email)
        if existing_email:
            raise EmailAlreadyExistsError()

        existing_phone = await self.user_repo.find_by_phone(phone)
        if existing_phone:
            raise PhoneAlreadyExistsError()

        # Hash password
        user_doc = {
            "name": data["name"].strip(),
            "email": email,
            "phone": phone,
            "password_hash": hash_password(data["password"]),
            "address": data["address"],
            "area_location": data["area_location"],
            "gender": data["gender"],
            "age": data["age"],
            "role": None,  # Set after OTP verification + role selection
            "email_verified": False,
            "is_active": True,
            "is_approved": False,
            "preferred_language": data.get("preferred_language", "en"),
        }

        if data.get("latitude") is not None and data.get("longitude") is not None:
            user_doc["latitude"] = round(data["latitude"], 6)
            user_doc["longitude"] = round(data["longitude"], 6)
        user_id = await self.user_repo.create(user_doc)

        await self.audit_service.log(
            actor_id=user_id,
            actor_role="UNVERIFIED",
            action="USER_REGISTERED",
            entity_type="user",
            entity_id=user_id,
        )

        return {"user_id": user_id}

    async def request_otp(self, email: str, purpose: str) -> Dict[str, Any]:
        """
        Generate and send OTP via Brevo.
        Uses generic response to avoid leaking account existence.
        """
        email = email.lower().strip()

        # For password reset, protect against email enumeration
        if purpose == "PASSWORD_RESET":
            user = await self.user_repo.find_by_email(email)
            if not user:
                return {
                    "message": "If an account exists with this email, a verification code has been sent. Check your inbox and spam folder."
                }
            name = user.get("name", "User")
            otp = await self.otp_service.create_otp(email, purpose)
            accepted = await brevo_service.send_password_reset_email(email, name, otp)
            if not accepted:
                await self.otp_service.invalidate(email, purpose)
                raise EmailDeliveryError()
            return {
                "message": "If an account exists with this email, a verification code has been sent. Check your inbox and spam folder."
            }

        # Registration OTP
        otp = await self.otp_service.create_otp(email, purpose)
        user = await self.user_repo.find_by_email(email)
        name = user["name"] if user else "User"

        accepted = await brevo_service.send_otp_email(email, name, otp)
        if not accepted:
            await self.otp_service.invalidate(email, purpose)
            raise EmailDeliveryError()

        return {"message": "Email provider accepted the OTP email. Check your inbox and spam folder; delivery may take a few minutes."}

    async def verify_reset_otp(self, email: str, otp: str) -> Dict[str, Any]:
        """
        Verify password reset OTP and return short-lived reset authorization token.
        """
        email = email.lower().strip()
        await self.otp_service.verify(email, otp, "PASSWORD_RESET")

        user = await self.user_repo.find_by_email(email)
        if not user:
            raise NotFoundError("User")

        user_id = str(user["id"] if isinstance(user, dict) else getattr(user, "id"))
        jti = secrets.token_urlsafe(32)
        reset_token = create_password_reset_token(user_id, email, jti=jti)

        user_oid = ObjectId(user_id) if ObjectId.is_valid(user_id) else user_id
        await self.db["password_resets"].insert_one({
            "jti": jti,
            "user_id": user_oid,
            "email": email,
            "expires_at": datetime.now(timezone.utc) + timedelta(minutes=15),
            "is_used": False,
            "created_at": datetime.now(timezone.utc),
        })

        return {
            "verified": True,
            "reset_token": reset_token,
            "message": "Code verified successfully. Please enter your new password.",
        }

    async def verify_otp(self, email: str, otp: str, purpose: str) -> bool:
        """Verify OTP and mark email as verified if registration OTP."""
        email = email.lower().strip()

        verified = await self.otp_service.verify(email, otp, purpose)

        if verified and purpose == "REGISTRATION":
            await self.user_repo.set_email_verified(email)

        return verified

    @transactional
    async def select_role(self, user_id: str, role: str) -> Dict[str, Any]:
        """Assign role after email verification."""
        user = await self.user_repo.find_by_id(user_id)
        if not user:
            raise NotFoundError("User")

        if not user.get("email_verified"):
            raise ForbiddenError("Email must be verified before selecting a role.")

        if user.get("role"):
            raise ValidationError("Role has already been assigned.")

        if role == "ADMIN":
            raise ForbiddenError("Admin accounts cannot be self-assigned.")

        # Set role
        await self.user_repo.set_role(user_id, role)

        # Create role-specific profile
        if role == "FARMER":
            await self.farmer_repo.create({
                "user_id": ObjectId(user_id),
                "approval_status": "PENDING",
            })
        elif role == "BUYER":
            await self.buyer_repo.create({
                "user_id": ObjectId(user_id),
            })

        await self.audit_service.log(
            actor_id=user_id,
            actor_role=role,
            action="ROLE_SELECTED",
            entity_type="user",
            entity_id=user_id,
            details={"role": role},
        )

        return {"role": role, "message": f"Role '{role}' assigned successfully."}

    async def login(self, email: str, password: str) -> Dict[str, Any]:
        """Authenticate user and issue JWT tokens."""
        email = email.lower().strip()

        user = await self.user_repo.find_by_email(email)
        if not user:
            raise InvalidCredentialsError()

        if not verify_password(password, user["password_hash"]):
            raise InvalidCredentialsError()

        if not user.get("is_active"):
            raise ForbiddenError("Account is deactivated.")

        if not user.get("email_verified"):
            raise ForbiddenError("Email not verified. Please verify your email first.")

        # Create tokens
        token_data = {"sub": user["id"], "role": user.get("role", ""), "session_version": user.get("session_version", 0)}
        access_token = create_access_token(token_data)
        refresh_token = create_refresh_token(token_data)

        # Store refresh token hash
        await self._store_refresh_token(user["id"], refresh_token)

        await self.audit_service.log(
            actor_id=user["id"],
            actor_role=user.get("role", "UNVERIFIED"),
            action="USER_LOGIN",
            entity_type="user",
            entity_id=user["id"],
        )

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
            "user": {
                "id": user["id"],
                "name": user["name"],
                "email": user["email"],
                "role": user.get("role"),
                "preferred_language": user.get("preferred_language", "en"),
                "phone": user.get("phone", ""), "address": user.get("address", ""), "area_location": user.get("area_location", ""),
            },
        }

    async def refresh_access_token(self, refresh_token: str) -> Dict[str, Any]:
        """Issue new access token using refresh token."""
        try:
            payload = decode_token(refresh_token)
        except Exception:
            raise InvalidTokenError()

        if payload.get("type") != "refresh":
            raise InvalidTokenError()

        user_id = payload.get("sub")
        if not user_id:
            raise InvalidTokenError()

        # Verify refresh token exists and is not revoked
        token_hash = "sha256:" + hashlib.sha256(refresh_token.encode("utf-8")).hexdigest()
        stored = await self.refresh_tokens_collection.find_one({
            "user_id": ObjectId(user_id),
            "is_revoked": False,
            "token_hash": token_hash,
        })
        if not stored:
            raise InvalidTokenError()

        user = await self.user_repo.find_by_id(user_id)
        if (not user or not user.get("is_active")
                or payload.get("session_version", 0) != user.get("session_version", 0)):
            raise InvalidTokenError()

        # Revoke old refresh token
        consumed = await self.refresh_tokens_collection.update_one(
            {"_id": stored["_id"], "is_revoked": False, "token_hash": token_hash},
            {"$set": {"is_revoked": True}},
        )

        if not consumed.modified_count:
            raise InvalidTokenError()

        # Issue new tokens
        token_data = {"sub": user["id"], "role": user.get("role", ""), "session_version": user.get("session_version", 0)}
        new_access = create_access_token(token_data)
        new_refresh = create_refresh_token(token_data)

        await self._store_refresh_token(user["id"], new_refresh)

        return {
            "access_token": new_access,
            "refresh_token": new_refresh,
            "token_type": "bearer",
            "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        }

    async def logout(self, user_id: str):
        """Revoke access and refresh sessions for the user."""
        await self.user_repo.invalidate_sessions(user_id)
        await self.refresh_tokens_collection.update_many(
            {"user_id": ObjectId(user_id)},
            {"$set": {"is_revoked": True}},
        )

    async def change_password(
        self, user_id: str, current_password: str, new_password: str
    ):
        """Change password for authenticated user."""
        user = await self.user_repo.find_by_id(user_id)
        if not user:
            raise NotFoundError("User")

        if not verify_password(current_password, user["password_hash"]):
            raise InvalidCredentialsError()

        new_hash = hash_password(new_password)
        await self.user_repo.update(user_id, {"password_hash": new_hash})

        # Revoke all refresh tokens (force re-login)
        await self.logout(user_id)

        await self.audit_service.log(
            actor_id=user_id,
            actor_role=user.get("role", ""),
            action="PASSWORD_CHANGED",
            entity_type="user",
            entity_id=user_id,
        )

    async def reset_password(
        self,
        new_password: str,
        confirm_password: Optional[str] = None,
        reset_token: Optional[str] = None,
        email: Optional[str] = None,
        otp: Optional[str] = None,
    ):
        """Reset password using reset authorization token or legacy OTP."""
        # Upfront password policy verification
        if len(new_password) < 8:
            raise ValidationError("Password must be at least 8 characters long.")
        if len(new_password.encode("utf-8")) > 72:
            raise ValidationError("Password cannot exceed 72 bytes.")
        if not re.search(r"[A-Z]", new_password):
            raise ValidationError("Password must contain at least one uppercase letter.")
        if not re.search(r"[0-9]", new_password):
            raise ValidationError("Password must contain at least one number.")
        if confirm_password is not None and new_password != confirm_password:
            raise ValidationError("Passwords do not match.")

        user_id = None
        user_email = None

        if reset_token:
            try:
                payload = decode_token(reset_token)
            except Exception:
                raise InvalidTokenError()

            if payload.get("type") != "password_reset":
                raise UnauthorizedError("Invalid token type for password reset.")

            jti = payload.get("jti")
            user_id = payload.get("sub")
            user_email = payload.get("email")

            if not jti or not user_id:
                raise InvalidTokenError()

            # Atomically claim the reset authorization record
            record = await self.db["password_resets"].find_one_and_update(
                {
                    "jti": jti,
                    "is_used": False,
                    "expires_at": {"$gt": datetime.now(timezone.utc)},
                },
                {"$set": {"is_used": True, "used_at": datetime.now(timezone.utc)}},
            )
            if not record:
                raise UnauthorizedError("Password reset authorization has expired or already been used.")

        elif email and otp:
            user_email = email.lower().strip()
            await self.otp_service.verify(user_email, otp, "PASSWORD_RESET")
            user = await self.user_repo.find_by_email(user_email)
            if not user:
                raise NotFoundError("User")
            user_id = user["id"] if isinstance(user, dict) else getattr(user, "id")
        else:
            raise ValidationError("Either reset_token or email and otp must be provided.")

        user = await self.user_repo.find_by_id(user_id)
        if not user:
            raise NotFoundError("User")

        new_hash = hash_password(new_password)
        await self.user_repo.update(user_id, {"password_hash": new_hash})

        # Revoke all active user sessions & refresh tokens
        await self.logout(user_id)

        # Invalidate any outstanding reset tokens and OTPs
        user_oid = ObjectId(user_id) if ObjectId.is_valid(user_id) else user_id
        if user_email:
            await self.otp_service.invalidate(user_email, "PASSWORD_RESET")
            await self.db["password_resets"].update_many(
                {"user_id": user_oid, "is_used": False},
                {"$set": {"is_used": True}},
            )

        actor_role = user.get("role", "USER") if isinstance(user, dict) else getattr(user, "role", "USER")
        await self.audit_service.log(
            actor_id=user_id,
            actor_role=actor_role,
            action="PASSWORD_RESET_COMPLETED",
            entity_type="user",
            entity_id=user_id,
        )
        return {
            "success": True,
            "message": "Password reset successfully. Please sign in with your new password.",
        }

    async def _store_refresh_token(self, user_id: str, token: str):
        """Store a hashed refresh token."""
        await self.refresh_tokens_collection.insert_one({
            "user_id": ObjectId(user_id),
            "token_hash": "sha256:" + hashlib.sha256(token.encode("utf-8")).hexdigest(),
            "is_revoked": False,
            "expires_at": datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
            "created_at": datetime.now(timezone.utc),
        })
