"""
VayalConnect Backend — Farmer Repository

Farmer profile and bank detail data access.
"""

from app.core.transactions import collection
from typing import Optional, Dict, Any, List
from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import datetime, timezone
import logging

logger = logging.getLogger(__name__)


class FarmerRepository:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.collection = collection(db, "farmer_profiles")
        self.users = collection(db, "users")

    async def create(self, profile_data: Dict[str, Any]) -> str:
        profile_data["created_at"] = datetime.now(timezone.utc)
        profile_data["updated_at"] = datetime.now(timezone.utc)
        profile_data.setdefault("approval_status", "PENDING")
        profile_data.setdefault("bank_details_verified", False)
        result = await self.collection.insert_one(profile_data)
        return str(result.inserted_id)

    async def find_by_user_id(self, user_id: str) -> Optional[Dict[str, Any]]:
        if not ObjectId.is_valid(user_id):
            return None
        doc = await self.collection.find_one({"user_id": ObjectId(user_id)})
        return self._serialize(doc)

    async def ensure_pending_profile(self, user_id: str) -> None:
        """Repair a missing profile during an explicit onboarding write only.

        Existing applications, bank details and approval decisions are untouched.
        The caller must verify the authenticated account's farmer role.
        """
        now = datetime.now(timezone.utc)
        await self.collection.update_one(
            {"user_id": ObjectId(user_id)},
            {"$setOnInsert": {"approval_status": "PENDING", "application_revision": 0,
                              "bank_details_verified": False, "created_at": now, "updated_at": now}},
            upsert=True,
        )

    async def submit_application(self, user_id: str, application: dict, revision: int) -> bool:
        revision_query = {"application_revision": revision} if revision else {"$or": [{"application_revision": 0}, {"application_revision": {"$exists": False}}]}
        now = datetime.now(timezone.utc)
        result = await self.collection.update_one(
            {"user_id": ObjectId(user_id), "approval_status": {"$in": ["PENDING", "REJECTED", "APPROVED"]}, **revision_query},
            {"$set": {"application": application, "submitted_at": now, "updated_at": now, "approval_status": "PENDING", "rejection_reason": None},
             "$inc": {"application_revision": 1}, "$unset": {"approved_by": "", "approved_at": ""}},
        )
        return result.modified_count == 1

    async def decide_application(self, user_id: str, revision: int, status: str, actor_id: str, reason=None) -> bool:
        revision_query = {"application_revision": revision} if revision else {"$or": [{"application_revision": 0}, {"application_revision": {"$exists": False}}]}
        result = await self.collection.update_one(
            {"user_id": ObjectId(user_id), "approval_status": {"$in": ["PENDING", "APPROVED"]} if status == "REJECTED" else "PENDING", **revision_query},
            {"$set": {"approval_status": status, "reviewed_by": ObjectId(actor_id), "reviewed_at": datetime.now(timezone.utc),
                      "rejection_reason": reason, "updated_at": datetime.now(timezone.utc)}},
        )
        return result.modified_count == 1

    async def update_bank_details(
        self, user_id: str, bank_data: Dict[str, Any]
    ) -> bool:
        bank_data["updated_at"] = datetime.now(timezone.utc)
        result = await self.collection.update_one(
            {"user_id": ObjectId(user_id)},
            {"$set": bank_data}
        )
        return result.modified_count > 0

    async def update_approval_status(
        self,
        user_id: str,
        status: str,
        approved_by: Optional[str] = None,
        rejection_reason: Optional[str] = None,
    ) -> bool:
        update: Dict[str, Any] = {
            "approval_status": status,
            "updated_at": datetime.now(timezone.utc),
        }
        if approved_by:
            update["approved_by"] = ObjectId(approved_by)
            update["approved_at"] = datetime.now(timezone.utc)
        if rejection_reason:
            update["rejection_reason"] = rejection_reason

        result = await self.collection.update_one(
            {"user_id": ObjectId(user_id)},
            {"$set": update}
        )
        return result.modified_count > 0

    async def list_by_status(
        self, status: str, page: int = 1, limit: int = 50
    ) -> tuple[List[Dict[str, Any]], int]:
        rows = await self.users.aggregate(
            self._farmer_profiles_pipeline(status) + [{"$facet": {
                "items": [{"$sort": {"created_at": -1, "user_id": 1}},
                          {"$skip": (page - 1) * limit}, {"$limit": limit}],
                "total": [{"$count": "count"}],
            }}]
        ).to_list(1)
        result = rows[0] if rows else {"items": [], "total": []}
        return ([self._serialize(doc) for doc in result["items"]],
                result["total"][0]["count"] if result["total"] else 0)

    @staticmethod
    def _farmer_profiles_pipeline(status):
        # A legacy farmer account can lack its profile. Include it in admin
        # views without writing on GET or deriving approval from user flags.
        pipeline = [
            {"$match": {"role": "FARMER"}},
            {"$lookup": {"from": "farmer_profiles", "localField": "_id",
                         "foreignField": "user_id", "as": "profile"}},
            {"$unwind": {"path": "$profile", "preserveNullAndEmptyArrays": True}},
            {"$replaceRoot": {"newRoot": {"$mergeObjects": [
                {"_id": "$_id", "user_id": "$_id", "created_at": "$created_at",
                 "approval_status": "PENDING", "application_revision": 0,
                 "profile_present": {"$eq": [{"$type": "$profile"}, "object"]}},
                "$profile",
            ]}}},
        ]
        if status:
            pipeline.append({"$match": {"approval_status": status}})
        return pipeline

    async def count_by_status(self, status: str) -> int:
        rows = await self.users.aggregate(
            self._farmer_profiles_pipeline(status) + [{"$count": "count"}]
        ).to_list(1)
        return rows[0]["count"] if rows else 0

    def _serialize(self, doc: Optional[Dict]) -> Optional[Dict[str, Any]]:
        if doc is None:
            return None
        doc["id"] = str(doc.pop("_id"))
        if "user_id" in doc and isinstance(doc["user_id"], ObjectId):
            doc["user_id"] = str(doc["user_id"])
        if "approved_by" in doc and isinstance(doc["approved_by"], ObjectId):
            doc["approved_by"] = str(doc["approved_by"])
        return doc
