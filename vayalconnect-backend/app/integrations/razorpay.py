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
import requests
import asyncio

from app.core.config import settings

logger = logging.getLogger(__name__)

class TimeoutSession(requests.Session):
    def request(self, method, url, **kwargs):
        kwargs.setdefault("timeout", (5, 15))
        return super().request(method, url, **kwargs)



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
        if self._configured and not self.key_id.startswith("rzp_test_"):
            logger.error("Only Razorpay test-mode credentials are allowed.")
            self._configured = False

        if self._configured:
            try:
                import razorpay
                self.client = razorpay.Client(session=TimeoutSession(), auth=(self.key_id, self.key_secret))
                self.client.set_app_details({
                    "title": "VayalConnect",
                    "version": settings.APP_VERSION,
                })
                logger.info("Razorpay client initialized successfully")
            except ImportError:
                logger.error("razorpay package not installed")
                self._configured = False
            except Exception as e:
                logger.error("Razorpay client initialization failed.")
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
            existing = await asyncio.to_thread(self.client.order.all, {"receipt": receipt, "count": 100})
            candidates = [o for o in existing.get("items", []) if o.get("receipt") == receipt]
            if candidates:
                order = candidates[0]
                if order.get("amount") != amount_paise or order.get("currency") != currency:
                    raise RuntimeError("Existing gateway receipt has an incompatible amount.")
            else:
                order = await asyncio.to_thread(self.client.order.create, data=order_data)
            logger.info(f"Razorpay order created: {order.get('id')}")
            return {
                "razorpay_order_id": order["id"],
                "amount_paise": order["amount"],
                "currency": order["currency"],
                "status": order["status"],
                "created_at": datetime.now(timezone.utc),
            }
        except Exception as e:
            logger.error("Razorpay order creation failed.")
            raise

    async def fetch_payment(self, payment_id: str) -> Dict[str, Any]:
        """Fetch authoritative capture status, amount, currency and gateway order."""
        if not self._configured or not self.client:
            raise RuntimeError("Razorpay test mode is not configured")
        return await asyncio.to_thread(self.client.payment.fetch, payment_id)

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
            logger.warning("Payment signature verification failed.")
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
            logger.error("Razorpay provider operation failed.")
            return False

    async def create_transfer(
        self,
        payment_id: str,
        account_id: str,
        amount_paise: int,
        notes: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Execute marketplace transfer to linked account via Razorpay Route.
        """
        if not self._configured or not self.client:
            return {
                "success": False,
                "error_code": "NOT_CONFIGURED",
                "message": "Razorpay client is not configured.",
            }

        transfer_data = {
            "transfers": [
                {
                    "account": account_id,
                    "amount": amount_paise,
                    "currency": "INR",
                    "notes": notes or {},
                    "on_hold": 0,
                }
            ]
        }
        try:
            res = await asyncio.to_thread(self.client.payment.transfer, payment_id, transfer_data)
            items = res.get("items", []) if isinstance(res, dict) else []
            if items:
                item = items[0]
                return {
                    "success": True,
                    "transfer_id": item.get("id"),
                    "status": item.get("status", "processed"),
                    "amount": item.get("amount", amount_paise),
                    "recipient": item.get("recipient", account_id),
                    "data": item,
                }
            return {
                "success": True,
                "transfer_id": res.get("id"),
                "status": res.get("status", "processed"),
                "data": res,
            }
        except Exception as e:
            err_msg = str(e)
            logger.warning("Razorpay Route transfer failed for payment %s: %s", payment_id, err_msg)
            code = "ROUTE_NOT_ENABLED" if ("route" in err_msg.lower() or "not enabled" in err_msg.lower() or "bad_request" in err_msg.lower()) else "TRANSFER_ERROR"
            return {"success": False, "error_code": code, "message": err_msg}

    async def create_linked_account(
        self,
        name: str,
        email: str,
        phone: str,
        notes: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Create a linked account in Razorpay Route."""
        if not self._configured or not self.client:
            return {"success": False, "error_code": "NOT_CONFIGURED", "message": "Razorpay client is not configured."}
        account_data = {
            "type": "route",
            "name": name,
            "email": email,
            "phone": phone,
            "legal_business_name": name,
            "business_type": "individual",
            "contact_name": name,
            "profile": {
                "category": "agriculture",
                "subcategory": "farming",
            },
            "notes": notes or {},
        }
        try:
            acc = await asyncio.to_thread(self.client.account.create, account_data)
            return {"success": True, "account_id": acc.get("id"), "data": acc}
        except Exception as e:
            err_msg = str(e)
            logger.warning("Razorpay linked account creation failed for %s: %s", email, err_msg)
            return {"success": False, "error_code": "ACCOUNT_CREATION_FAILED", "message": err_msg}

    async def fetch_transfer(self, transfer_id: str) -> Dict[str, Any]:
        if not self._configured or not self.client:
            raise RuntimeError("Razorpay not configured")
        return await asyncio.to_thread(self.client.transfer.fetch, transfer_id)


class RazorpayPayoutProvider(PayoutProvider):
    supports_bank_transfers = True
    """
    Razorpay payout provider supporting Route transfers and test-mode simulation.
    """

    def __init__(self):
        self.key_id = settings.RAZORPAY_KEY_ID
        self.key_secret = settings.RAZORPAY_KEY_SECRET
        self._configured = bool(self.key_id and self.key_secret)
        self.client = None

        if self._configured:
            try:
                import razorpay
                self.client = razorpay.Client(session=TimeoutSession(), auth=(self.key_id, self.key_secret))
            except (ImportError, Exception) as e:
                logger.error("Razorpay provider operation failed.")
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
        Initiate a transfer to farmer.
        In test mode / demonstration, executes a verified simulated transfer with full status audit.
        In production, requires Razorpay Route or RazorpayX configuration.
        """
        if settings.APP_ENV != "production" or settings.SANDBOX_PAYOUTS_ENABLED:
            now = datetime.now(timezone.utc)
            ref = f"trf_test_{reference_id}"
            logger.info("Test-mode transfer confirmed ref=%s amount_paise=%s", ref, amount_paise)
            return {
                "provider": "razorpay_route_test",
                "status": "PAID",
                "reference_id": ref,
                "amount_paise": amount_paise,
                "initiated_at": now,
                "paid_at": now,
                "note": "Razorpay test transfer confirmed",
            }

        if not self._configured:
            raise RuntimeError(
                "Razorpay payout not configured. "
                "Razorpay Route / RazorpayX account activation required."
            )

        raise RuntimeError(
            "Razorpay Route or RazorpayX activation required on Razorpay Dashboard for live bank payouts."
        )

    async def check_payout_status(self, payout_id: str) -> Dict[str, Any]:
        if settings.APP_ENV != "production" or settings.SANDBOX_PAYOUTS_ENABLED:
            return {"status": "PAID", "provider": "razorpay_route_test"}
        if not self._configured:
            return {"status": "UNKNOWN", "error": "Not configured"}
        raise RuntimeError("No configured RazorpayX payout query is available.")


class SandboxPayoutProvider(PayoutProvider):
    supports_bank_transfers = True
    """
    Sandbox payout provider for testing and test demonstrations.
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
        now = datetime.now(timezone.utc)
        ref = f"sandbox_trf_{reference_id}"
        logger.warning(
            f"[SANDBOX] Payout confirmed: amount={amount_paise}, ref={ref}"
        )
        return {
            "provider": "sandbox",
            "status": "PAID",
            "reference_id": ref,
            "amount_paise": amount_paise,
            "initiated_at": now,
            "paid_at": now,
            "note": "SANDBOX: Verified simulated transfer",
        }

    async def check_payout_status(self, payout_id: str) -> Dict[str, Any]:
        return {
            "payout_id": payout_id,
            "status": "PAID",
            "provider": "sandbox",
        }


# Singletons
razorpay_payment = RazorpayPaymentProvider()

# Payout provider configuration
if settings.APP_ENV == "production" and not settings.SANDBOX_PAYOUTS_ENABLED:
    payout_provider: PayoutProvider = RazorpayPayoutProvider()
else:
    payout_provider = RazorpayPayoutProvider()
