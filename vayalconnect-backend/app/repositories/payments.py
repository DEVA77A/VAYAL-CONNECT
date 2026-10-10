"""
VayalConnect Backend — Payment Repository
"""

from typing import Optional, Dict, Any, List
from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import datetime, timezone


class PaymentRepository:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.collection = db["payments"]

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
