"""
VayalConnect Backend — Payment Repository
"""

from app.core.transactions import collection
from typing import Optional, Dict, Any, List
from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import datetime, timezone


class PaymentRepository:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.collection = collection(db, "payments")

    async def create(self, payment_data: Dict[str, Any]) -> str:
        payment_data["created_at"] = datetime.now(timezone.utc)
        payment_data["updated_at"] = datetime.now(timezone.utc)
        for field in ["order_id", "buyer_id"]:
            if field in payment_data and isinstance(payment_data[field], str):
                payment_data[field] = ObjectId(payment_data[field])
        result = await self.collection.insert_one(payment_data)
        return str(result.inserted_id)

    async def find_by_order_id(self, order_id: str) -> Optional[Dict[str, Any]]:
        doc = await self.collection.find_one({"order_id": ObjectId(order_id)})
        return self._serialize(doc)

    async def find_by_razorpay_order_id(self, rz_order_id: str) -> Optional[Dict[str, Any]]:
        doc = await self.collection.find_one({"razorpay_order_id": rz_order_id})
        return self._serialize(doc)

    async def find_by_razorpay_payment_id(self, rz_payment_id: str) -> Optional[Dict[str, Any]]:
        doc = await self.collection.find_one({"razorpay_payment_id": rz_payment_id})
        return self._serialize(doc)

    async def update(self, payment_id: str, update_data: Dict[str, Any]) -> bool:
        update_data["updated_at"] = datetime.now(timezone.utc)
        result = await self.collection.update_one(
            {"_id": ObjectId(payment_id)},
            {"$set": update_data}
        )
        return result.modified_count > 0

    async def update_by_razorpay_order_id(
        self, rz_order_id: str, update_data: Dict[str, Any]
    ) -> bool:
        update_data["updated_at"] = datetime.now(timezone.utc)
        result = await self.collection.update_one(
            {"razorpay_order_id": rz_order_id},
            {"$set": update_data}
        )
        return result.modified_count > 0

    def _serialize(self, doc: Optional[Dict]) -> Optional[Dict[str, Any]]:
        if doc is None:
            return None
        doc["id"] = str(doc.pop("_id"))
        for field in ["order_id", "buyer_id"]:
            if field in doc and isinstance(doc[field], ObjectId):
                doc[field] = str(doc[field])
        return doc


    async def claim_creation(self, order_id, buyer_id, amount):
        from datetime import timedelta
        from pymongo import ReturnDocument
        from pymongo.errors import DuplicateKeyError
        import uuid
        now = datetime.now(timezone.utc)
        token = uuid.uuid4().hex
        try:
            doc = await self.collection.find_one_and_update({"order_id": ObjectId(order_id),
                "$or": [{"creation_lease_until": {"$lt": now}}, {"creation_lease_until": {"$exists": False}}]},
                {"$set": {"creation_lease_until": now + timedelta(seconds=60), "creation_owner": token},
                 "$setOnInsert": {"buyer_id": ObjectId(buyer_id), "amount_paise": amount, "currency": "INR",
                    "payment_status": "CREATED", "signature_verified": False, "idempotency_key": "pay_" + order_id, "created_at": now}},
                upsert=True, return_document=ReturnDocument.AFTER)
        except DuplicateKeyError:
            return None
        return self._serialize(doc)

    async def complete_creation(self, payment_id, token, gateway_order_id):
        result = await self.collection.update_one({"_id": ObjectId(payment_id), "creation_owner": token},
            {"$set": {"razorpay_order_id": gateway_order_id, "updated_at": datetime.now(timezone.utc)},
             "$unset": {"creation_owner": "", "creation_lease_until": ""}})
        return result.modified_count == 1
