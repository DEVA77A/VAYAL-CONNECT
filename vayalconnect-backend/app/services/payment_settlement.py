"""One transaction commits verified capture and all dependent financial state."""
from datetime import datetime, timezone
from app.core.transactions import transactional, collection
from app.core.exceptions import PaymentVerificationFailedError, ValidationError
from bson import ObjectId


class PaymentSettlement:
    def __init__(self, db):
        self.db = db

    @transactional
    async def captured(self, payment, gateway, verification_method):
        payments, orders, payouts = (collection(self.db, name) for name in ("payments", "orders", "payouts"))
        order = await orders.find_one({"_id": ObjectId(payment["order_id"])})
        if not order or order.get("buyer_total_paise") != payment["amount_paise"]:
            raise PaymentVerificationFailedError()
        latest = await payments.find_one({"_id": ObjectId(payment["id"])})
        if latest.get("payment_status") == "CAPTURED":
            if latest.get("razorpay_payment_id") != gateway["id"]:
                raise PaymentVerificationFailedError()
            return {"payment_verified": True, "order_status": order["order_status"], "message": "Test payment already verified."}
        now = datetime.now(timezone.utc)
        values = {"razorpay_payment_id": gateway["id"], "payment_status": "CAPTURED",
            "signature_verified": True, "verification_method": verification_method, "verified_at": now,
            "gateway_status": gateway["status"], "updated_at": now}
        if order["order_status"] == "CANCELLED":
            values["refund_required"] = True
            await payments.update_one({"_id": ObjectId(payment["id"])}, {"$set": values})
            await orders.update_one({"_id": order["_id"]}, {"$set": {"payment_status": "CAPTURED", "refund_required": True}})
            return {"payment_verified": True, "order_status": "CANCELLED", "message": "Test capture arrived after cancellation. Refund review required; order remains cancelled."}
        if order["order_status"] != "PENDING_PAYMENT":
            raise ValidationError("Order state does not allow a new capture.")
        await payments.update_one({"_id": ObjectId(payment["id"])}, {"$set": values})
        await orders.update_one({"_id": order["_id"], "order_status": "PENDING_PAYMENT"}, {"$set": {
            "payment_status": "CAPTURED", "order_status": "PAID", "updated_at": now, "paid_at": now,
            "payout_status": "PENDING_APPROVAL"}})
        await payouts.update_one({"order_id": order["_id"]}, {"$setOnInsert": {
            "order_id": order["_id"], "farmer_id": order["farmer_id"], "amount_paise": order["farmer_total_payout_paise"],
            "currency": "INR", "status": "PENDING_APPROVAL", "provider": "pending", "created_at": now,
            "payout_number": "PO-" + str(order["_id"]).upper(), "idempotency_key": "payout_" + str(order["_id"])}}, upsert=True)
        return {"payment_verified": True, "order_status": "PAID", "message": "Razorpay test payment verified. No real money charged."}
