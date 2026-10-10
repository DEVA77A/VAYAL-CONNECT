"""
VayalConnect Backend — Order Repository
"""

from typing import Optional, Dict, Any, List
from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import datetime, timezone
import logging

logger = logging.getLogger(__name__)


class OrderRepository:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.collection = db["orders"]

    async def create(self, order_data: Dict[str, Any]) -> str:
        order_data["created_at"] = datetime.now(timezone.utc)
        order_data["updated_at"] = datetime.now(timezone.utc)
        # Convert string IDs to ObjectId for references
        for field in ["buyer_id", "farmer_id", "product_id", "pricing_snapshot_id"]:
            if field in order_data and isinstance(order_data[field], str):
                order_data[field] = ObjectId(order_data[field])
        result = await self.collection.insert_one(order_data)
        return str(result.inserted_id)

    async def find_by_id(self, order_id: str) -> Optional[Dict[str, Any]]:
        if not ObjectId.is_valid(order_id):
            return None
        doc = await self.collection.find_one({"_id": ObjectId(order_id)})
        return self._serialize(doc)

    async def find_by_order_number(self, order_number: str) -> Optional[Dict[str, Any]]:
        doc = await self.collection.find_one({"order_number": order_number})
        return self._serialize(doc)

    async def find_by_idempotency_key(self, key: str) -> Optional[Dict[str, Any]]:
        doc = await self.collection.find_one({"idempotency_key": key})
        return self._serialize(doc)

    async def list_by_buyer(
        self, buyer_id: str, page: int = 1, limit: int = 50
    ) -> tuple[List[Dict[str, Any]], int]:
        query = {"buyer_id": ObjectId(buyer_id)}
        total = await self.collection.count_documents(query)
        cursor = self.collection.find(query).sort("created_at", -1).skip((page - 1) * limit).limit(limit)
        docs = [self._serialize(doc) async for doc in cursor]
        return docs, total

    async def list_by_farmer(
        self, farmer_id: str, page: int = 1, limit: int = 50
    ) -> tuple[List[Dict[str, Any]], int]:
        query = {"farmer_id": ObjectId(farmer_id)}
        total = await self.collection.count_documents(query)
        cursor = self.collection.find(query).sort("created_at", -1).skip((page - 1) * limit).limit(limit)
        docs = [self._serialize(doc) async for doc in cursor]
        return docs, total

    async def list_all(
        self,
        status: Optional[str] = None,
        page: int = 1,
        limit: int = 50,
    ) -> tuple[List[Dict[str, Any]], int]:
        query: Dict[str, Any] = {}
        if status:
            query["order_status"] = status
        total = await self.collection.count_documents(query)
        cursor = self.collection.find(query).sort("created_at", -1).skip((page - 1) * limit).limit(limit)
        docs = [self._serialize(doc) async for doc in cursor]
        return docs, total

    async def update_status(
        self, order_id: str, order_status: str, **extra_fields
    ) -> bool:
        update = {
            "order_status": order_status,
            "updated_at": datetime.now(timezone.utc),
            **extra_fields,
        }
        result = await self.collection.update_one(
            {"_id": ObjectId(order_id)},
            {"$set": update}
        )
        return result.modified_count > 0

    async def update_payment_status(
        self, order_id: str, payment_status: str
    ) -> bool:
        result = await self.collection.update_one(
            {"_id": ObjectId(order_id)},
            {"$set": {
                "payment_status": payment_status,
                "updated_at": datetime.now(timezone.utc),
            }}
        )
        return result.modified_count > 0

    async def update_payout_status(
        self, order_id: str, payout_status: str
    ) -> bool:
        result = await self.collection.update_one(
            {"_id": ObjectId(order_id)},
            {"$set": {
                "payout_status": payout_status,
                "updated_at": datetime.now(timezone.utc),
            }}
        )
        return result.modified_count > 0

    async def count_all(self, status: Optional[str] = None) -> int:
        query: Dict[str, Any] = {}
        if status:
            query["order_status"] = status
        return await self.collection.count_documents(query)

    async def count_by_farmer(self, farmer_id: str, status: Optional[str] = None) -> int:
        query: Dict[str, Any] = {"farmer_id": ObjectId(farmer_id)}
        if status:
            query["order_status"] = status
        return await self.collection.count_documents(query)

    async def aggregate_totals(self, match: Optional[Dict] = None) -> Dict[str, Any]:
        """Aggregate total sales, payouts, commissions using MongoDB pipeline."""
        pipeline = []
        if match:
            pipeline.append({"$match": match})
        pipeline.append({
            "$group": {
                "_id": None,
                "total_buyer_amount": {"$sum": "$buyer_total_paise"},
                "total_farmer_payout": {"$sum": "$farmer_total_payout_paise"},
                "total_commission": {"$sum": "$commission_total_paise"},
                "total_quantity": {"$sum": "$quantity"},
                "count": {"$sum": 1},
            }
        })
        result = await self.collection.aggregate(pipeline).to_list(1)
        if result:
            return result[0]
        return {
            "total_buyer_amount": 0,
            "total_farmer_payout": 0,
            "total_commission": 0,
            "total_quantity": 0,
            "count": 0,
        }

    async def generate_order_number(self) -> str:
        """Generate a unique order number: VC-YYYYMMDD-NNN."""
        today = datetime.now(timezone.utc).strftime("%Y%m%d")
        prefix = f"VC-{today}-"
        # Count today's orders
        count = await self.collection.count_documents({
            "order_number": {"$regex": f"^{prefix}"}
        })
        return f"{prefix}{count + 1:04d}"

    def _serialize(self, doc: Optional[Dict]) -> Optional[Dict[str, Any]]:
        if doc is None:
            return None
        doc["id"] = str(doc.pop("_id"))
        for field in ["buyer_id", "farmer_id", "product_id", "pricing_snapshot_id"]:
            if field in doc and isinstance(doc[field], ObjectId):
                doc[field] = str(doc[field])
        return doc
