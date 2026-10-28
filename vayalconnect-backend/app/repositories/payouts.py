"""
VayalConnect Backend — Payout Repository
"""

from app.core.transactions import collection
from typing import Optional, Dict, Any, List
from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import datetime, timezone


class PayoutRepository:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.collection = collection(db, "payouts")

    async def create(self, payout_data: Dict[str, Any]) -> str:
        payout_data["created_at"] = datetime.now(timezone.utc)
        payout_data["updated_at"] = datetime.now(timezone.utc)
        for field in ["order_id", "farmer_id"]:
            if field in payout_data and isinstance(payout_data[field], str):
                payout_data[field] = ObjectId(payout_data[field])
        result = await self.collection.insert_one(payout_data)
        return str(result.inserted_id)

    async def find_by_id(self, payout_id: str) -> Optional[Dict[str, Any]]:
        if not ObjectId.is_valid(payout_id):
            return None
        doc = await self.collection.find_one({"_id": ObjectId(payout_id)})
        return self._serialize(doc)

    async def find_by_order_id(self, order_id: str) -> Optional[Dict[str, Any]]:
        doc = await self.collection.find_one({"order_id": ObjectId(order_id)})
        return self._serialize(doc)

    async def find_by_provider_reference(self, reference_id: str) -> Optional[Dict[str, Any]]:
        doc = await self.collection.find_one({"provider_reference_id": reference_id})
        return self._serialize(doc)

    async def list_by_farmer(
        self, farmer_id: str, page: int = 1, limit: int = 50
    ) -> tuple[List[Dict[str, Any]], int]:
        query = {"farmer_id": ObjectId(farmer_id)}
        total = await self.collection.count_documents(query)
        cursor = self.collection.find(query).sort("created_at", -1).skip((page - 1) * limit).limit(limit)
        docs = [self._serialize(doc) async for doc in cursor]
        return docs, total

    async def list_all(
        self, status: Optional[str] = None, page: int = 1, limit: int = 50
    ) -> tuple[List[Dict[str, Any]], int]:
        query: Dict[str, Any] = {}
        if status:
            query["status"] = status
        total = await self.collection.count_documents(query)
        cursor = self.collection.find(query).sort("created_at", -1).skip((page - 1) * limit).limit(limit)
        docs = [self._serialize(doc) async for doc in cursor]
        return docs, total

    async def update_status(
        self, payout_id: str, status: str, **extra_fields
    ) -> bool:
        update = {
            "status": status,
            "updated_at": datetime.now(timezone.utc),
            **extra_fields,
        }
        result = await self.collection.update_one(
            {"_id": ObjectId(payout_id)},
            {"$set": update}
        )
        return result.modified_count > 0

    async def count_by_status(self, status: str) -> int:
        return await self.collection.count_documents({"status": status})

    async def aggregate_farmer_payouts(self, farmer_id: str) -> Dict[str, Any]:
        pipeline = [
            {"$match": {"farmer_id": ObjectId(farmer_id)}},
            {"$group": {
                "_id": "$status",
                "total": {"$sum": "$amount_paise"},
                "count": {"$sum": 1},
            }}
        ]
        results = await self.collection.aggregate(pipeline).to_list(10)
        summary: Dict[str, Any] = {
            "total_paid": 0,
            "total_pending": 0,
            "total_processing": 0,
            "total_failed": 0,
            "paid_count": 0,
            "pending_count": 0,
            "processing_count": 0,
            "failed_count": 0,
        }
        for r in results:
            status = r["_id"]
            total = r["total"]
            count = r["count"]
            if status == "PAID":
                summary["total_paid"] = total
                summary["paid_count"] = count
            elif status in ("PENDING_APPROVAL", "APPROVED"):
                summary["total_pending"] += total
                summary["pending_count"] += count
            elif status == "PROCESSING":
                summary["total_processing"] += total
                summary["processing_count"] += count
                summary["total_pending"] += total
            elif status == "FAILED":
                summary["total_failed"] += total
                summary["failed_count"] += count
        return summary

    async def generate_payout_number(self) -> str:
        today = datetime.now(timezone.utc).strftime("%Y%m%d")
        prefix = f"PO-{today}-"
        count = await self.collection.count_documents({
            "payout_number": {"$regex": f"^{prefix}"}
        })
        return f"{prefix}{count + 1:04d}"

    def _serialize(self, doc: Optional[Dict]) -> Optional[Dict[str, Any]]:
        if doc is None:
            return None
        doc["id"] = str(doc.pop("_id"))
        for field in ["order_id", "farmer_id", "approved_by"]:
            if field in doc and isinstance(doc[field], ObjectId):
                doc[field] = str(doc[field])
        return doc
