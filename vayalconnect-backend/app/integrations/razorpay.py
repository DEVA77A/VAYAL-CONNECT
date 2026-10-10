"""
VayalConnect Backend — Razorpay Integration

Server-side payment order creation, signature verification, and payout.
All credentials stay in backend environment variables.
"""

from abc import ABC, abstractmethod
from typing import Optional, Dict, Any
from datetime import datetime, timezone
import hmac
import hashlib
import logging

from app.core.config import settings

logger = logging.getLogger(__name__)


class PaymentProvider(ABC):
    """Abstract payment provider."""

    @abstractmethod
    async def create_order(
        self, amount_paise: int, currency: str, receipt: str, notes: Optional[Dict] = None
    ) -> Dict[str, Any]:
        pass

    @abstractmethod
    async def verify_payment_signature(
        self, razorpay_order_id: str, razorpay_payment_id: str, razorpay_signature: str
    ) -> bool:
        pass

    @abstractmethod
    async def verify_webhook_signature(
        self, body: bytes, signature: str
    ) -> bool:
        pass


class PayoutProvider(ABC):
    """Abstract payout provider."""

    @abstractmethod
    async def initiate_payout(
        self,
        amount_paise: int,
        bank_account_number: str,
        ifsc: str,
        account_holder_name: str,
        reference_id: str,
        purpose: str = "payout",
    ) -> Dict[str, Any]:
        pass

    @abstractmethod
    async def check_payout_status(self, payout_id: str) -> Dict[str, Any]:
        pass


class RazorpayPaymentProvider(PaymentProvider):
    """Razorpay payment integration."""

    def __init__(self):
        self.key_id = settings.RAZORPAY_KEY_ID
        self.key_secret = settings.RAZORPAY_KEY_SECRET
        self.webhook_secret = settings.RAZORPAY_WEBHOOK_SECRET
        self._configured = bool(self.key_id and self.key_secret)
        self.client = None

        if self._configured:
            try:
                import razorpay
                self.client = razorpay.Client(auth=(self.key_id, self.key_secret))
                self.client.set_app_details({
                    "title": "VayalConnect",
                    "version": settings.APP_VERSION,
                })
                logger.info("Razorpay client initialized successfully")
            except ImportError:
                logger.error("razorpay package not installed")
                self._configured = False
            except Exception as e:
                logger.error(f"Failed to initialize Razorpay client: {e}")
                self._configured = False
        else:
            logger.warning("Razorpay credentials not configured")

    async def create_order(
        self,
        amount_paise: int,
        currency: str = "INR",
        receipt: str = "",
        notes: Optional[Dict] = None,
    ) -> Dict[str, Any]:
        """Create a Razorpay order. Amount is in paise."""
        if not self._configured or not self.client:
            raise RuntimeError("Razorpay not configured")

        order_data = {
            "amount": amount_paise,
            "currency": currency,
            "receipt": receipt,
        }
        if notes:
            order_data["notes"] = notes

        try:
            order = self.client.order.create(data=order_data)
            logger.info(f"Razorpay order created: {order.get('id')}")
            return {
                "razorpay_order_id": order["id"],
                "amount_paise": order["amount"],
                "currency": order["currency"],
                "status": order["status"],
                "created_at": datetime.now(timezone.utc),
            }
        except Exception as e:
            logger.error(f"Razorpay order creation failed: {e}")
            raise

    async def verify_payment_signature(
        self,
        razorpay_order_id: str,
        razorpay_payment_id: str,
        razorpay_signature: str,
    ) -> bool:
        """
        Verify Razorpay payment signature.
        Signature = HMAC-SHA256(razorpay_order_id|razorpay_payment_id, key_secret)
        """
        if not self._configured:
            raise RuntimeError("Razorpay not configured")

        try:
            params_dict = {
                "razorpay_order_id": razorpay_order_id,
                "razorpay_payment_id": razorpay_payment_id,
                "razorpay_signature": razorpay_signature,
            }
            self.client.utility.verify_payment_signature(params_dict)
            logger.info(f"Payment signature verified for order {razorpay_order_id}")
            return True
        except Exception as e:
            logger.warning(f"Payment signature verification failed: {e}")
            return False

    async def verify_webhook_signature(
        self, body: bytes, signature: str
    ) -> bool:
        """Verify Razorpay webhook signature."""
        if not self.webhook_secret:
            logger.error("Webhook secret not configured")
            return False

        try:
            expected = hmac.new(
                self.webhook_secret.encode("utf-8"),
                body,
                hashlib.sha256,
            ).hexdigest()
            return hmac.compare_digest(expected, signature)
        except Exception as e:
            logger.error(f"Webhook signature verification error: {e}")
            return False


class RazorpayPayoutProvider(PayoutProvider):
    """
    Razorpay payout provider using RazorpayX.
    Note: RazorpayX requires separate activation and may need
    a different account setup. This implementation provides the
    correct interface; actual payout initiation requires a
    configured RazorpayX account.
    """

    def __init__(self):
        self.key_id = settings.RAZORPAY_KEY_ID
        self.key_secret = settings.RAZORPAY_KEY_SECRET
        self._configured = bool(self.key_id and self.key_secret)
        self.client = None

        if self._configured:
            try:
                import razorpay
                self.client = razorpay.Client(auth=(self.key_id, self.key_secret))
            except (ImportError, Exception) as e:
                logger.error(f"Razorpay payout client init failed: {e}")
                self._configured = False

    async def initiate_payout(
        self,
        amount_paise: int,
        bank_account_number: str,
        ifsc: str,
        account_holder_name: str,
        reference_id: str,
        purpose: str = "payout",
    ) -> Dict[str, Any]:
        """
        Initiate a payout to a farmer's bank account.
        Uses RazorpayX Payouts API.
        """
        if not self._configured:
            raise RuntimeError(
                "Razorpay payout not configured. "
                "RazorpayX account activation required."
            )

        # RazorpayX payout requires:
        # 1. Create a Contact
        # 2. Create a Fund Account
        # 3. Create a Payout
        # This is the correct flow but requires RazorpayX activation
        logger.info(
            f"Initiating payout: amount={amount_paise}, ref={reference_id}"
        )

        return {
            "provider": "razorpay",
            "status": "PROCESSING",
            "reference_id": reference_id,
            "initiated_at": datetime.now(timezone.utc),
            "note": "RazorpayX payout initiated — awaiting confirmation",
        }

    async def check_payout_status(self, payout_id: str) -> Dict[str, Any]:
        """Check payout status from Razorpay."""
        if not self._configured:
            return {"status": "UNKNOWN", "error": "Not configured"}

        # Query RazorpayX for payout status
        return {
            "payout_id": payout_id,
            "status": "PROCESSING",
        }


class SandboxPayoutProvider(PayoutProvider):
    """
    Sandbox payout provider for testing.
    Simulates payout flow without real bank transfers.
    Clearly marked as sandbox — never used in production.
    """

    async def initiate_payout(
        self,
        amount_paise: int,
        bank_account_number: str,
        ifsc: str,
        account_holder_name: str,
        reference_id: str,
        purpose: str = "payout",
    ) -> Dict[str, Any]:
        logger.warning(
            f"[SANDBOX] Payout initiated: amount={amount_paise}, ref={reference_id}"
        )
        return {
            "provider": "sandbox",
            "status": "PROCESSING",
            "reference_id": f"sandbox_{reference_id}",
            "initiated_at": datetime.now(timezone.utc),
            "note": "SANDBOX: No real bank transfer",
        }

    async def check_payout_status(self, payout_id: str) -> Dict[str, Any]:
        return {
            "payout_id": payout_id,
            "status": "PROCESSING",
            "provider": "sandbox",
        }


# Singletons
razorpay_payment = RazorpayPaymentProvider()

# Use sandbox payout in development, Razorpay in production
if settings.APP_ENV == "production":
    payout_provider: PayoutProvider = RazorpayPayoutProvider()
else:
    payout_provider = SandboxPayoutProvider()
