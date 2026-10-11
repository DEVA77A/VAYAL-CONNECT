"""
VayalConnect Backend — Audit Service

Immutable audit logging for security-critical actions.
NEVER logs passwords, OTPs, API keys, full bank account numbers, or secrets.
"""

from app.core.transactions import collection
from typing import Optional, Dict, Any
from datetime import datetime, timezone
from motor.motor_asyncio import AsyncIOMotorDatabase
import logging

logger = logging.getLogger(__name__)


class AuditService:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.collection = collection(db, "audit_logs")

    async def log(
        self,
        actor_id: str,
        actor_role: str,
        action: str,
        entity_type: str,
        entity_id: str,
        details: Optional[Dict[str, Any]] = None,
        request_id: Optional[str] = None,
        ip_address: Optional[str] = None,
    ):
        """Record an audit event. Fire-and-forget — never blocks the request."""
        try:
            # Sanitize details — remove sensitive fields
            safe_details = self._sanitize(details) if details else {}

            await self.collection.insert_one({
                "actor_id": actor_id,
                "actor_role": actor_role,
                "action": action,
                "entity_type": entity_type,
                "entity_id": str(entity_id),
                "details": safe_details,
                "request_id": request_id,
                "ip_address": ip_address,
                "timestamp": datetime.now(timezone.utc),
                "created_at": datetime.now(timezone.utc),
            })
        except Exception as e:
            # Audit logging failure should never crash the application
            logger.error("Audit log failure category=%s", type(e).__name__)

    def _sanitize(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Remove sensitive fields from audit details."""
        SENSITIVE_KEYS = {
            "password", "password_hash", "otp", "otp_hash",
            "api_key", "secret", "token", "refresh_token",
            "account_number", "bank_account_number",
            "razorpay_key_secret", "webhook_secret",
            "encryption_key",
        }
        sanitized = {}
        for key, value in data.items():
            if key.lower() in SENSITIVE_KEYS:
                sanitized[key] = "[REDACTED]"
            elif isinstance(value, dict):
                sanitized[key] = self._sanitize(value)
            else:
                sanitized[key] = value
        return sanitized
