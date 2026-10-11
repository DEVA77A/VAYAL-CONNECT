"""
VayalConnect Backend — Pricing Repository

Pricing policies, commission configs, and immutable pricing snapshots.
"""

from typing import Optional, Dict, Any, List
from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import date, datetime, timezone
import re


class PricingRepository:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.policies = db["pricing_policies"]
        self.commission_configs = db["commission_configs"]
        self.snapshots = db["pricing_snapshots"]
        self.market_prices = db["market_prices"]

    # ============================================================
    # Pricing Policies
    # ============================================================

    async def create_policy(self, policy_data: Dict[str, Any]) -> str:
        policy_data["created_at"] = datetime.now(timezone.utc)
        policy_data["updated_at"] = datetime.now(timezone.utc)
        if "created_by" in policy_data and isinstance(policy_data["created_by"], str):
            policy_data["created_by"] = ObjectId(policy_data["created_by"])
        result = await self.policies.insert_one(policy_data)
        return str(result.inserted_id)

    async def get_active_policy(self) -> Optional[Dict[str, Any]]:
        doc = await self.policies.find_one({"is_active": True})
        return self._serialize(doc)

    async def get_policy_by_id(self, policy_id: str) -> Optional[Dict[str, Any]]:
        if not ObjectId.is_valid(policy_id):
            return None
        doc = await self.policies.find_one({"_id": ObjectId(policy_id)})
        return self._serialize(doc)

    async def list_policies(self) -> List[Dict[str, Any]]:
        cursor = self.policies.find().sort("created_at", -1)
        return [self._serialize(doc) async for doc in cursor]

    async def update_policy(self, policy_id: str, update_data: Dict[str, Any]) -> bool:
        update_data["updated_at"] = datetime.now(timezone.utc)
        result = await self.policies.update_one(
            {"_id": ObjectId(policy_id)},
            {"$set": update_data}
        )
        return result.modified_count > 0

    # ============================================================
    # Commission Configs
    # ============================================================

    async def get_active_commission(self) -> Optional[Dict[str, Any]]:
        doc = await self.commission_configs.find_one({"status": "ACTIVE"})
        return self._serialize(doc)

    async def create_commission_config(self, config_data: Dict[str, Any]) -> str:
        config_data["created_at"] = datetime.now(timezone.utc)
        if "created_by" in config_data and isinstance(config_data["created_by"], str):
            config_data["created_by"] = ObjectId(config_data["created_by"])
        result = await self.commission_configs.insert_one(config_data)
        return str(result.inserted_id)

    async def supersede_active_commission(self) -> bool:
        """Mark the current active commission as SUPERSEDED."""
        result = await self.commission_configs.update_one(
            {"status": "ACTIVE"},
            {"$set": {
                "status": "SUPERSEDED",
                "effective_until": datetime.now(timezone.utc),
            }}
        )
        return result.modified_count > 0

    async def list_commission_history(self) -> List[Dict[str, Any]]:
        cursor = self.commission_configs.find().sort("created_at", -1)
        return [self._serialize(doc) async for doc in cursor]

    # ============================================================
    # Pricing Snapshots (IMMUTABLE)
    # ============================================================

    async def create_snapshot(self, snapshot_data: Dict[str, Any]) -> str:
        snapshot_data["created_at"] = datetime.now(timezone.utc)
        for field in ["product_id", "farmer_id", "pricing_policy_id", "commission_config_id"]:
            if field in snapshot_data and isinstance(snapshot_data[field], str) and ObjectId.is_valid(snapshot_data[field]):
                snapshot_data[field] = ObjectId(snapshot_data[field])
        result = await self.snapshots.insert_one(snapshot_data)
        return str(result.inserted_id)

    async def get_snapshot(self, snapshot_id: str) -> Optional[Dict[str, Any]]:
        if not ObjectId.is_valid(snapshot_id):
            return None
        doc = await self.snapshots.find_one({"_id": ObjectId(snapshot_id)})
        return self._serialize(doc)

    # ============================================================
    # Market Prices
    # ============================================================

    async def store_market_price(self, price_data: Dict[str, Any]) -> str:
        price_data = {k: v.isoformat() if isinstance(v, date) and not isinstance(v, datetime) else v for k, v in price_data.items()}
        price_data["created_at"] = datetime.now(timezone.utc)
        result = await self.market_prices.insert_one(price_data)
        return str(result.inserted_id)

    async def store_market_prices_bulk(self, prices: List[Dict[str, Any]]) -> int:
        """Upsert market price records to avoid duplicates."""
        if not prices:
            return 0
        now = datetime.now(timezone.utc)
        count = 0
        for p in prices:
            p_copy = dict(p)
            p_copy.pop("id", None)
            p_copy.pop("_id", None)
            p_copy["updated_at"] = now
            if "created_at" not in p_copy:
                p_copy["created_at"] = now

            # Unique key by commodity, market, and arrival_date
            query: Dict[str, Any] = {
                "commodity": {"$regex": f"^{re.escape(p_copy.get('commodity', ''))}$", "$options": "i"},
                "market": {"$regex": f"^{re.escape(p_copy.get('market', ''))}$", "$options": "i"},
            }
            if p_copy.get("arrival_date"):
                # Handle arrival_date as date or string
                arr_val = p_copy["arrival_date"]
                if hasattr(arr_val, "isoformat"):
                    query["arrival_date"] = arr_val.isoformat()
                    p_copy["arrival_date"] = arr_val.isoformat()
                else:
                    query["arrival_date"] = str(arr_val)

            await self.market_prices.update_one(
                query,
                {"$set": p_copy},
                upsert=True,
            )
            count += 1
        return count

    async def get_latest_market_price(
        self,
        commodity: str,
        market: Optional[str] = None,
        state: Optional[str] = None,
        district: Optional[str] = None,
    ) -> Optional[Dict[str, Any]]:
        query: Dict[str, Any] = {
            "commodity": {"$regex": f"^{re.escape(commodity)}$", "$options": "i"}
        }
        if market:
            query["market"] = {"$regex": f"^{re.escape(market)}$", "$options": "i"}
        if state:
            query["state"] = {"$regex": f"^{re.escape(state)}$", "$options": "i"}
        if district:
            query["district"] = {"$regex": f"^{re.escape(district)}$", "$options": "i"}
        doc = await self.market_prices.find_one(
            query, sort=[("arrival_date", -1), ("retrieved_at", -1)]
        )
        return self._serialize(doc)

    async def list_market_prices(
        self,
        commodity: Optional[str] = None,
        market: Optional[str] = None,
        state: Optional[str] = None,
        district: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> List[Dict[str, Any]]:
        query: Dict[str, Any] = {}
        if commodity:
            query["commodity"] = {"$regex": re.escape(commodity), "$options": "i"}
        if market:
            query["market"] = {"$regex": re.escape(market), "$options": "i"}
        if state:
            query["state"] = {"$regex": re.escape(state), "$options": "i"}
        if district:
            query["district"] = {"$regex": re.escape(district), "$options": "i"}
        cursor = (
            self.market_prices.find(query)
            .sort([("arrival_date", -1), ("retrieved_at", -1)])
            .skip(offset)
            .limit(limit)
        )
        return [self._serialize(doc) async for doc in cursor]

    def _serialize(self, doc: Optional[Dict]) -> Optional[Dict[str, Any]]:
        if doc is None:
            return None
        doc["id"] = str(doc.pop("_id"))
        for field in ["product_id", "farmer_id", "pricing_policy_id",
                       "commission_config_id", "created_by"]:
            if field in doc and isinstance(doc[field], ObjectId):
                doc[field] = str(doc[field])
        return doc
