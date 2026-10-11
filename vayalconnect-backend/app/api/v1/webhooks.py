"""
VayalConnect Backend — Webhooks Router

Razorpay webhook endpoint with signature verification.
"""

from fastapi import APIRouter, Request, Header
from motor.motor_asyncio import AsyncIOMotorDatabase
import json
import logging

from app.core.database import get_database
from app.integrations.razorpay import razorpay_payment
from app.services.payment_service import PaymentService
from app.schemas.common import APIResponse

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/webhooks", tags=["Webhooks"])


@router.post("/razorpay")
async def razorpay_webhook(
    request: Request,
    x_razorpay_signature: str = Header(None, alias="X-Razorpay-Signature"),
):
    """
    Handle Razorpay webhook events.
    Verifies webhook signature before processing.
    Handlers are idempotent — safe for duplicate deliveries.
    """
    body = await request.body()

    # Verify webhook signature
    if x_razorpay_signature:
        is_valid = await razorpay_payment.verify_webhook_signature(
            body, x_razorpay_signature
        )
        if not is_valid:
            logger.warning("Invalid Razorpay webhook signature")
            return {"status": "invalid_signature"}

    try:
        payload = json.loads(body)
        event_type = payload.get("event", "")

        db = get_database()
        payment_service = PaymentService(db)
        await payment_service.handle_webhook(event_type, payload)

        logger.info(f"Webhook processed: {event_type}")
        return {"status": "ok"}

    except Exception as e:
        logger.error("Webhook processing failed category=%s", type(e).__name__)
        return {"status": "error"}
