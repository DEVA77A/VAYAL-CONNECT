"""
VayalConnect Backend — Buyer Repository
"""

from app.core.transactions import collection
from typing import Optional, Dict, Any
from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import datetime, timezone


class BuyerRepository:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.collection = collection(db, "buyer_profiles")

    async def create(self, profile_data: Dict[str, Any]) -> str:
        profile_data["created_at"] = datetime.now(timezone.utc)
        profile_data["updated_at"] = datetime.now(timezone.utc)
        result = await self.collection.insert_one(profile_data)
        return str(result.inserted_id)

    async def find_by_user_id(self, user_id: str) -> Optional[Dict[str, Any]]:
        if not ObjectId.is_valid(user_id):
            return None
        doc = await self.collection.find_one({"user_id": ObjectId(user_id)})
        return self._serialize(doc)

    async def update(self, user_id: str, update_data: Dict[str, Any]) -> bool:
        update_data["updated_at"] = datetime.now(timezone.utc)
        result = await self.collection.update_one(
            {"user_id": ObjectId(user_id)},
            {"$set": update_data}
        )
        return result.modified_count > 0

    def _serialize(self, doc: Optional[Dict]) -> Optional[Dict[str, Any]]:
        if doc is None:
            return None
        doc["id"] = str(doc.pop("_id"))
        if "user_id" in doc and isinstance(doc["user_id"], ObjectId):
            doc["user_id"] = str(doc["user_id"])
        return doc
