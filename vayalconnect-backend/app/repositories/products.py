"""
VayalConnect Backend — Product Repository

Product data access with atomic inventory operations.
"""

from typing import Optional, Dict, Any, List
from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import datetime, timezone
import logging
import re

logger = logging.getLogger(__name__)


class ProductRepository:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.collection = db["products"]

    async def create(self, product_data: Dict[str, Any]) -> str:
        product_data["created_at"] = datetime.now(timezone.utc)
        product_data["updated_at"] = datetime.now(timezone.utc)
        product_data.setdefault("is_active", True)
        product_data.setdefault("status", "ACTIVE")
        if "farmer_id" in product_data and isinstance(product_data["farmer_id"], str):
            product_data["farmer_id"] = ObjectId(product_data["farmer_id"])
        result = await self.collection.insert_one(product_data)
        return str(result.inserted_id)

    async def find_by_id(self, product_id: str) -> Optional[Dict[str, Any]]:
        if not ObjectId.is_valid(product_id):
            return None
        doc = await self.collection.find_one({"_id": ObjectId(product_id)})
        return self._serialize(doc)

    async def find_active_by_id(self, product_id: str) -> Optional[Dict[str, Any]]:
        if not ObjectId.is_valid(product_id):
            return None
        docs = await self.collection.aggregate(
            self._visible_pipeline({"_id": ObjectId(product_id)}) + [{"$limit": 1}]
        ).to_list(1)
        return self._serialize(docs[0]) if docs else None

    @staticmethod
    def _visible_pipeline(filters: Dict[str, Any]) -> list:
        """Filter before pagination; approval is checked from current DB state."""
        return [
            {"$match": {"is_active": True, "status": "ACTIVE", "quantity_available": {"$gt": 0}, **filters}},
            {"$lookup": {"from": "users", "localField": "farmer_id", "foreignField": "_id", "as": "seller"}},
            {"$match": {"seller": {"$elemMatch": {"role": "FARMER", "is_active": True, "email_verified": True}}}},
            {"$lookup": {"from": "farmer_profiles", "localField": "farmer_id", "foreignField": "user_id", "as": "farm"}},
            {"$match": {"farm": {"$elemMatch": {"approval_status": "APPROVED"}}}},
            {"$project": {"seller": 0, "farm": 0}},
        ]

    async def list_by_farmer(
        self, farmer_id: str, page: int = 1, limit: int = 50
    ) -> tuple[List[Dict[str, Any]], int]:
        query = {"farmer_id": ObjectId(farmer_id)}
        total = await self.collection.count_documents(query)
        cursor = self.collection.find(query).sort("created_at", -1).skip((page - 1) * limit).limit(limit)
        docs = [self._serialize(doc) async for doc in cursor]
        return docs, total

    async def list_active(
        self,
        category: Optional[str] = None,
        location: Optional[str] = None,
        page: int = 1,
        limit: int = 50,
    ) -> tuple[List[Dict[str, Any]], int]:
        filters: Dict[str, Any] = {}
        if category:
            filters["category"] = {"$regex": re.escape(category), "$options": "i"}
        if location:
            filters["location"] = {"$regex": re.escape(location), "$options": "i"}
        result = await self.collection.aggregate(self._visible_pipeline(filters) + [
            {"$facet": {
                "items": [{"$sort": {"created_at": -1, "_id": -1}}, {"$skip": (page - 1) * limit}, {"$limit": limit}],
                "total": [{"$count": "count"}],
            }}
        ]).to_list(1)
        data = result[0] if result else {"items": [], "total": []}
        return [self._serialize(doc) for doc in data["items"]], (data["total"][0]["count"] if data["total"] else 0)

    async def list_all(
        self, page: int = 1, limit: int = 50
    ) -> tuple[List[Dict[str, Any]], int]:
        total = await self.collection.count_documents({})
        cursor = self.collection.find({}).sort("created_at", -1).skip((page - 1) * limit).limit(limit)
        docs = [self._serialize(doc) async for doc in cursor]
        return docs, total

    async def update(self, product_id: str, update_data: Dict[str, Any]) -> bool:
        update_data["updated_at"] = datetime.now(timezone.utc)
        result = await self.collection.update_one(
            {"_id": ObjectId(product_id)},
            {"$set": update_data}
        )
        return result.modified_count > 0

    async def atomic_reserve_quantity(
        self, product_id: str, quantity: int
    ) -> Optional[Dict[str, Any]]:
        """
        Atomically reserve quantity. Returns updated doc or None if insufficient stock.
        This prevents overselling via MongoDB atomic operations.
        """
        result = await self.collection.find_one_and_update(
            {
                "_id": ObjectId(product_id),
                "is_active": True,
                "status": "ACTIVE",
                "quantity_available": {"$gte": quantity},
            },
            {
                "$inc": {"quantity_available": -quantity},
                "$set": {"updated_at": datetime.now(timezone.utc)},
            },
            return_document=True,
        )
        if result:
            # Check if out of stock after reservation
            if result.get("quantity_available", 0) == 0:
                await self.collection.update_one(
                    {"_id": ObjectId(product_id), "quantity_available": 0},
                    {"$set": {"status": "OUT_OF_STOCK"}}
                )
        return self._serialize(result)

    async def restore_quantity(self, product_id: str, quantity: int) -> bool:
        """Restore quantity on order cancellation/failure."""
        result = await self.collection.update_one(
            {"_id": ObjectId(product_id)},
            {
                "$inc": {"quantity_available": quantity},
                "$set": {
                    "status": "ACTIVE",
                    "updated_at": datetime.now(timezone.utc),
                },
            }
        )
        return result.modified_count > 0

    async def count_by_farmer(self, farmer_id: str, active_only: bool = False) -> int:
        query: Dict[str, Any] = {"farmer_id": ObjectId(farmer_id)}
        if active_only:
            query["is_active"] = True
            query["status"] = "ACTIVE"
        return await self.collection.count_documents(query)

    async def deactivate(self, product_id: str) -> bool:
        return await self.update(product_id, {"is_active": False, "status": "INACTIVE"})

    def _serialize(self, doc: Optional[Dict]) -> Optional[Dict[str, Any]]:
        if doc is None:
            return None
        doc["id"] = str(doc.pop("_id"))
        if "farmer_id" in doc and isinstance(doc["farmer_id"], ObjectId):
            doc["farmer_id"] = str(doc["farmer_id"])
        if "pricing_snapshot_id" in doc and isinstance(doc["pricing_snapshot_id"], ObjectId):
            doc["pricing_snapshot_id"] = str(doc["pricing_snapshot_id"])
        if "pricing_policy_id" in doc and isinstance(doc["pricing_policy_id"], ObjectId):
            doc["pricing_policy_id"] = str(doc["pricing_policy_id"])
        return doc
