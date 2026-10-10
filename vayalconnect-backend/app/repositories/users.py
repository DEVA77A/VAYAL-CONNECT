"""
VayalConnect Backend — User Repository

Data access for the users collection.
"""

from typing import Optional, Dict, Any, List
from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import datetime, timezone
import logging

logger = logging.getLogger(__name__)


class UserRepository:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.collection = db["users"]

    async def create(self, user_data: Dict[str, Any]) -> str:
        user_data["created_at"] = datetime.now(timezone.utc)
        user_data["updated_at"] = datetime.now(timezone.utc)
        user_data.setdefault("is_active", True)
        user_data.setdefault("is_approved", False)
        user_data.setdefault("email_verified", False)
        result = await self.collection.insert_one(user_data)
        return str(result.inserted_id)

    async def find_by_id(self, user_id: str) -> Optional[Dict[str, Any]]:
        if not ObjectId.is_valid(user_id):
            return None
        doc = await self.collection.find_one({"_id": ObjectId(user_id)})
        return self._serialize(doc)

    async def find_by_email(self, email: str) -> Optional[Dict[str, Any]]:
        doc = await self.collection.find_one({"email": email.lower()})
        return self._serialize(doc)

    async def find_by_phone(self, phone: str) -> Optional[Dict[str, Any]]:
        doc = await self.collection.find_one({"phone": phone})
        return self._serialize(doc)

    async def update(self, user_id: str, update_data: Dict[str, Any]) -> bool:
        update_data["updated_at"] = datetime.now(timezone.utc)
        result = await self.collection.update_one(
            {"_id": ObjectId(user_id)},
            {"$set": update_data}
        )
        return result.modified_count > 0

    async def set_email_verified(self, email: str) -> bool:
        result = await self.collection.update_one(
            {"email": email.lower()},
            {"$set": {"email_verified": True, "updated_at": datetime.now(timezone.utc)}}
        )
        return result.modified_count > 0

    async def set_role(self, user_id: str, role: str) -> bool:
        result = await self.collection.update_one(
            {"_id": ObjectId(user_id)},
            {"$set": {"role": role, "updated_at": datetime.now(timezone.utc)}}
        )
        return result.modified_count > 0

    async def invalidate_sessions(self, user_id: str):
        await self.collection.update_one({"_id": ObjectId(user_id)},
            {"$inc": {"session_version": 1}, "$set": {"updated_at": datetime.now(timezone.utc)}})

    async def count_by_role(self, role: str, active_only: bool = True) -> int:
        query: Dict[str, Any] = {"role": role}
        if active_only:
            query["is_active"] = True
        return await self.collection.count_documents(query)

    async def list_users(
        self,
        role: Optional[str] = None,
        is_active: Optional[bool] = None,
        page: int = 1,
        limit: int = 50,
    ) -> tuple[List[Dict[str, Any]], int]:
        query: Dict[str, Any] = {}
        if role:
            query["role"] = role
        if is_active is not None:
            query["is_active"] = is_active

        total = await self.collection.count_documents(query)
        cursor = self.collection.find(query).sort("created_at", -1).skip((page - 1) * limit).limit(limit)
        docs = [self._serialize(doc) async for doc in cursor]
        return docs, total

    def _serialize(self, doc: Optional[Dict]) -> Optional[Dict[str, Any]]:
        if doc is None:
            return None
        doc["id"] = str(doc.pop("_id"))
        return doc
