"""Addresses embedded on the buyer profile: default switching is one atomic write."""
import uuid
from bson import ObjectId
from app.core.exceptions import NotFoundError, ConflictError, ValidationError
from app.schemas.address import SavedAddress


class AddressService:
    def __init__(self, db):
        self.profiles = db["buyer_profiles"]

    async def list(self, buyer_id):
        doc = await self.profiles.find_one({"user_id": ObjectId(buyer_id)})
        return (doc or {}).get("addresses", [])

    async def save(self, buyer_id, data: SavedAddress, address_id=None):
        query = {"user_id": ObjectId(buyer_id)}
        for _ in range(3):
            doc = await self.profiles.find_one(query)
            if not doc:
                raise NotFoundError("Buyer profile")
            old = doc.get("addresses", [])
            if address_id and not any(a["id"] == address_id for a in old):
                raise NotFoundError("Address")
            if not address_id and len(old) >= 20:
                raise ValidationError("At most 20 saved addresses are supported.")
            item = {"id": address_id or uuid.uuid4().hex, **data.model_dump()}
            addresses = [dict(a) for a in old if a["id"] != address_id]
            if item["is_default"]:
                for address in addresses:
                    address["is_default"] = False
            addresses.append(item)
            if not any(a.get("is_default") for a in addresses):
                item["is_default"] = True
            revision = doc.get("address_revision", 0)
            guard = {"address_revision": revision} if revision else {"$or": [{"address_revision": 0}, {"address_revision": {"$exists": False}}]}
            result = await self.profiles.update_one({**query, **guard}, {"$set": {"addresses": addresses}, "$inc": {"address_revision": 1}})
            if result.modified_count:
                return item
        raise ConflictError("ADDRESS_CHANGED", "Address book changed; please reload.")

    async def delete(self, buyer_id, address_id):
        query = {"user_id": ObjectId(buyer_id)}
        for _ in range(3):
            doc = await self.profiles.find_one(query)
            old = (doc or {}).get("addresses", [])
            if not any(a["id"] == address_id for a in old):
                raise NotFoundError("Address")
            items = [dict(a) for a in old if a["id"] != address_id]
            if items and not any(a.get("is_default") for a in items):
                items[0]["is_default"] = True
            revision = doc.get("address_revision", 0)
            guard = {"address_revision": revision} if revision else {"$or": [{"address_revision": 0}, {"address_revision": {"$exists": False}}]}
            result = await self.profiles.update_one({**query, **guard}, {"$set": {"addresses": items}, "$inc": {"address_revision": 1}})
            if result.modified_count:
                return
        raise ConflictError("ADDRESS_CHANGED", "Address book changed; please reload.")
