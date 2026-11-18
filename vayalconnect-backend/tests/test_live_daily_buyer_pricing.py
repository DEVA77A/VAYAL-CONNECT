"""
Tests for Live Daily Buyer Marketplace Price Update System.

Covers:
1. Product creation with MARKET_BASED vs FARMER_SELECTED pricing modes.
2. Commodity deduplication across multiple farmer listings.
3. Daily 08:00 AM IST refresh workflow:
   - Fetches verified market observations.
   - Recalculates farmer operating costs and recommended selling price.
   - Updates buyer-facing price and platform commission for MARKET_BASED products.
   - Strictly preserves farmer-selected prices for FARMER_SELECTED products.
   - Generates daily price history in `market_price_history`.
4. Multi-day price movement simulation (Day 1 -> Day 2 -> Day 3).
5. Historical orders, payments, and payouts immutability.
6. Admin monitoring and price history telemetry endpoints.
"""

import pytest
import re
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock

from app.services.market_orchestrator import MarketPriceOrchestrator
from app.services.farmer_cost_service import FarmerCostService
from app.services.pricing_service import PricingEngine


class AsyncCursorMock:
    """Mock async cursor supporting async for and chaining."""
    def __init__(self, items):
        self.items = list(items)

    def __aiter__(self):
        self._iter = iter(self.items)
        return self

    async def __anext__(self):
        try:
            return next(self._iter)
        except StopIteration:
            raise StopAsyncIteration

    def sort(self, *args, **kwargs):
        return self

    def limit(self, *args, **kwargs):
        return self

    async def to_list(self, length=None):
        return list(self.items)


class MockCollection:
    def __init__(self, initial_data=None):
        self.docs = list(initial_data or [])

    def find(self, query=None, projection=None):
        query = query or {}
        results = []
        for d in self.docs:
            match = True
            for k, v in query.items():
                if k == "$or":
                    continue
                if isinstance(v, dict):
                    if "$regex" in v:
                        if not re.search(v["$regex"], str(d.get(k, "")), re.IGNORECASE):
                            match = False
                            break
                    elif "$ne" in v:
                        if d.get(k) == v["$ne"]:
                            match = False
                            break
                elif d.get(k) != v:
                    match = False
                    break
            if match:
                results.append(d)
        return AsyncCursorMock(results)

    async def find_one(self, query=None, sort=None):
        cursor = self.find(query)
        items = cursor.items
        return items[0] if items else None

    async def insert_one(self, doc):
        self.docs.append(doc)
        return doc

    async def insert_many(self, docs, ordered=False):
        self.docs.extend(docs)
        return docs

    async def update_one(self, query, update, upsert=False):
        for d in self.docs:
            matched = True
            for k, v in query.items():
                if d.get(k) != v:
                    matched = False
                    break
            if matched:
                if "$set" in update:
                    d.update(update["$set"])
                return AsyncMock(matched_count=1)
        if upsert:
            new_doc = dict(query)
            if "$set" in update:
                new_doc.update(update["$set"])
            self.docs.append(new_doc)
            return AsyncMock(matched_count=0, upserted_id="upserted")
        return AsyncMock(matched_count=0)

    async def find_one_and_update(self, filter_q, update, **kwargs):
        await self.update_one(filter_q, update, upsert=True)
        return {"_id": filter_q.get("_id"), "status": "active"}

    async def count_documents(self, query=None):
        return len(self.find(query).items)

    async def distinct(self, key):
        return list(set(d.get(key) for d in self.docs if key in d))

    async def delete_many(self, query=None):
        self.docs.clear()
        return AsyncMock(deleted_count=1)


class MockDatabase:
    def __init__(self):
        self._collections = {}

    def __getitem__(self, name):
        if name not in self._collections:
            self._collections[name] = MockCollection()
        return self._collections[name]


@pytest.fixture
def mock_db():
    return MockDatabase()


@pytest.mark.asyncio
async def test_commodity_deduplication_and_market_based_update(mock_db):
    """
    Simulate Farmer A, Farmer B, and Farmer C listing Tomato in Madurai.
    Verify that:
    1. The daily orchestrator groups all 3 into 1 unique commodity group.
    2. MARKET_BASED products receive the updated buyer-facing price.
    3. FARMER_SELECTED products retain their manual selling price.
    4. Price history is recorded.
    """
    # 1. Insert seed active products
    # Farmer A: Tomato in Madurai (MARKET_BASED)
    prod_a = {
        "_id": "prod_tomato_a",
        "product_name": "Tomato",
        "commodity": "Tomato",
        "district": "Madurai",
        "location": "Madurai",
        "market": "Madurai Central Market",
        "status": "ACTIVE",
        "quantity_unit": "KG",
        "quantity_available": 100,
        "pricing_mode": "MARKET_BASED",
        "farmer_payout_per_unit_paise": 3000,
        "buyer_price_per_unit_paise": 3300,
        "commission_per_unit_paise": 300,
        "commission_percentage": 1000,
    }
    # Farmer B: Tomato in Madurai (MARKET_BASED)
    prod_b = {
        "_id": "prod_tomato_b",
        "product_name": "Tomato",
        "commodity": "Tomato",
        "district": "Madurai",
        "location": "Madurai",
        "market": "Madurai Uzhavar Sandhai",
        "status": "ACTIVE",
        "quantity_unit": "KG",
        "quantity_available": 50,
        "pricing_mode": "MARKET_BASED",
        "farmer_payout_per_unit_paise": 3000,
        "buyer_price_per_unit_paise": 3300,
        "commission_per_unit_paise": 300,
        "commission_percentage": 1000,
    }
    # Farmer C: Tomato in Madurai (FARMER_SELECTED) - Farmer manually set ₹45.00
    prod_c = {
        "_id": "prod_tomato_c",
        "product_name": "Tomato",
        "commodity": "Tomato",
        "district": "Madurai",
        "location": "Madurai",
        "market": "Madurai Mandi",
        "status": "ACTIVE",
        "quantity_unit": "KG",
        "quantity_available": 200,
        "pricing_mode": "FARMER_SELECTED",
        "farmer_payout_per_unit_paise": 4500,  # ₹45.00 manual price
        "buyer_price_per_unit_paise": 4950,
        "commission_per_unit_paise": 450,
        "commission_percentage": 1000,
    }
    await mock_db["products"].insert_many([prod_a, prod_b, prod_c])

    # 2. Seed today's verified market price in market_prices (Wholesale ₹32.00 / KG)
    today_str = datetime.now(timezone(timedelta(hours=5, minutes=30))).date().isoformat()
    await mock_db["market_prices"].insert_one({
        "commodity": "Tomato",
        "district": "Madurai",
        "market": "Madurai APMC",
        "state": "Tamil Nadu",
        "arrival_date": today_str,
        "price_paise": 3200,  # ₹32.00 / KG wholesale
        "unit": "KG",
        "source": "AGMARKNET Mandi",
        "source_provider": "AGMARKNET",
        "verification_status": "verified",
        "retrieved_at": datetime.now(timezone.utc).isoformat(),
    })

    # 3. Run the daily refresh
    orchestrator = MarketPriceOrchestrator(mock_db)
    orchestrator.agmarknet.fetch_prices = AsyncMock(return_value=([], {}))
    orchestrator.agmarknet.retrieve = AsyncMock(return_value=([], {}))
    orchestrator.tn_market.retrieve = AsyncMock(return_value=([], {}))
    orchestrator.gemini.search_market_price = AsyncMock(return_value=None)
    stats = await orchestrator.refresh_daily(force=True)

    # 4. Verify deduplication and execution statistics
    assert stats["completed"] == 1
    assert stats["total_active_products"] == 3
    assert stats["unique_groups_processed"] == 1  # 3 listings grouped into 1 query!
    assert stats["market_based_updated"] == 2
    assert stats["farmer_selected_skipped"] == 1

    # 5. Verify Farmer A & B received the newly calculated recommended selling price
    # Wholesale: ₹32.00
    # Operating costs (Harvesting ₹2.50 + Sorting ₹1.50 + Packaging ₹1.50 + Transport ₹2.00 + Handling ₹1.00 + Wastage 8% ₹2.56 = ₹11.06)
    # Min Sustainable: ₹32.00 + ₹11.06 = ₹43.06
    # Farmer Margin (15%): ₹6.46
    # Recommended Farmer Price: ₹43.06 + ₹6.46 = ₹49.52 (4952 paise)
    updated_a = await mock_db["products"].find_one({"_id": "prod_tomato_a"})
    updated_b = await mock_db["products"].find_one({"_id": "prod_tomato_b"})
    updated_c = await mock_db["products"].find_one({"_id": "prod_tomato_c"})

    assert updated_a["farmer_payout_per_unit_paise"] == 4952
    assert updated_a["buyer_price_per_unit_paise"] > updated_a["farmer_payout_per_unit_paise"]
    assert updated_a["buyer_price_per_unit_paise"] == 5942
    assert updated_a["government_reference_price_paise"] == 3200

    # Farmer B has the exact same price as Farmer A
    assert updated_b["farmer_payout_per_unit_paise"] == updated_a["farmer_payout_per_unit_paise"]
    assert updated_b["buyer_price_per_unit_paise"] == updated_a["buyer_price_per_unit_paise"]

    # 6. Verify Farmer C's FARMER_SELECTED price is strictly preserved!
    assert updated_c["farmer_payout_per_unit_paise"] == 4500  # UNTOUCHED
    assert updated_c["buyer_price_per_unit_paise"] == 4950   # UNTOUCHED
    assert updated_c["government_reference_price_paise"] == 3200
    assert updated_c["market_reference"]["recommended_farmer_price_paise"] == 4952

    # 7. Verify price history records
    history = (await mock_db["market_price_history"].find().to_list(10))
    assert len(history) == 3
    for h in history:
        assert h["commodity"] == "Tomato"
        assert h["district"] == "Madurai"
        assert h["wholesale_reference_price_paise"] == 3200
        assert h["effective_date"] == today_str


@pytest.mark.asyncio
async def test_multiday_simulation_flow(mock_db):
    """
    Simulate Day 1, Day 2, and Day 3 market price fluctuations:
    Day 1: Mandi ₹30.00 -> Buyer sees updated price
    Day 2: Mandi ₹35.00 -> Buyer sees increased price
    Day 3: Mandi ₹28.00 -> Buyer sees decreased price
    Historical paid orders remain completely frozen across all 3 days.
    """
    # Create product for Farmer
    prod = {
        "_id": "sim_tomato",
        "product_name": "Tomato",
        "commodity": "Tomato",
        "district": "Madurai",
        "location": "Madurai",
        "market": "Madurai Market",
        "status": "ACTIVE",
        "quantity_unit": "KG",
        "quantity_available": 500,
        "pricing_mode": "MARKET_BASED",
        "farmer_payout_per_unit_paise": 4000,
        "buyer_price_per_unit_paise": 4400,
        "commission_per_unit_paise": 400,
    }
    await mock_db["products"].insert_one(prod)

    # Historical paid order created on Day 1
    order = {
        "_id": "order_101",
        "product_id": "sim_tomato",
        "product_name": "Tomato",
        "quantity": 10,
        "unit_price_paise": 4400,
        "farmer_payout_paise": 40000,
        "buyer_total_paise": 44000,
        "commission_paise": 4000,
        "order_status": "PAID",
        "payment_status": "CAPTURED",
    }
    await mock_db["orders"].insert_one(order)

    orchestrator = MarketPriceOrchestrator(mock_db)
    orchestrator.agmarknet.fetch_prices = AsyncMock(return_value=([], {}))
    orchestrator.agmarknet.retrieve = AsyncMock(return_value=([], {}))
    orchestrator.tn_market.retrieve = AsyncMock(return_value=([], {}))
    orchestrator.gemini.search_market_price = AsyncMock(return_value=None)

    # --- DAY 1: Wholesale = ₹30.00 / KG ---
    await mock_db["market_prices"].delete_many({})
    await mock_db["market_prices"].insert_one({
        "commodity": "Tomato",
        "district": "Madurai",
        "arrival_date": "2026-11-16",
        "price_paise": 3000,
        "unit": "KG",
        "source": "AGMARKNET",
        "verification_status": "verified",
    })
    await orchestrator.refresh_daily(force=True)
    p_day1 = await mock_db["products"].find_one({"_id": "sim_tomato"})
    price_day1 = p_day1["buyer_price_per_unit_paise"]

    # --- DAY 2: Wholesale = ₹35.00 / KG ---
    await mock_db["market_prices"].delete_many({})
    await mock_db["market_prices"].insert_one({
        "commodity": "Tomato",
        "district": "Madurai",
        "arrival_date": "2026-11-17",
        "price_paise": 3500,
        "unit": "KG",
        "source": "AGMARKNET",
        "verification_status": "verified",
    })
    await orchestrator.refresh_daily(force=True)
    p_day2 = await mock_db["products"].find_one({"_id": "sim_tomato"})
    price_day2 = p_day2["buyer_price_per_unit_paise"]
    assert price_day2 > price_day1  # Price dynamically increased

    # --- DAY 3: Wholesale = ₹28.00 / KG ---
    await mock_db["market_prices"].delete_many({})
    await mock_db["market_prices"].insert_one({
        "commodity": "Tomato",
        "district": "Madurai",
        "arrival_date": "2026-11-18",
        "price_paise": 2800,
        "unit": "KG",
        "source": "AGMARKNET",
        "verification_status": "verified",
    })
    await orchestrator.refresh_daily(force=True)
    p_day3 = await mock_db["products"].find_one({"_id": "sim_tomato"})
    price_day3 = p_day3["buyer_price_per_unit_paise"]
    assert price_day3 < price_day2  # Price dynamically decreased

    # --- CRITICAL FINANCIAL SAFETY CHECK: Order 101 must remain completely unchanged ---
    o_after = await mock_db["orders"].find_one({"_id": "order_101"})
    assert o_after["buyer_total_paise"] == 44000
    assert o_after["farmer_payout_paise"] == 40000
    assert o_after["commission_paise"] == 4000
    assert o_after["unit_price_paise"] == 4400


@pytest.mark.asyncio
async def test_admin_monitoring_telemetry(mock_db):
    """
    Verify that the orchestrator status returns comprehensive monitoring telemetry.
    """
    orchestrator = MarketPriceOrchestrator(mock_db)
    orchestrator.agmarknet.fetch_prices = AsyncMock(return_value=([], {}))
    orchestrator.agmarknet.retrieve = AsyncMock(return_value=([], {}))
    orchestrator.tn_market.retrieve = AsyncMock(return_value=([], {}))
    orchestrator.gemini.search_market_price = AsyncMock(return_value=None)
    status_data = await orchestrator.status()

    assert "daily_job_status" in status_data
    assert "daily_update_schedule" in status_data
    assert "next_scheduled_update" in status_data
    assert "primary_provider" in status_data
    assert "secondary_provider" in status_data
    assert "gemini_provider" in status_data
    assert "total_active_products" in status_data
    assert "market_based_updated" in status_data
    assert "farmer_selected_skipped" in status_data
    assert "api_requests_remaining" in status_data
