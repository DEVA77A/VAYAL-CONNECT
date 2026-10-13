"""Real local Mongo cache/claim tests; provider mocked and Atlas never used."""
import asyncio
import os
import uuid
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from motor.motor_asyncio import AsyncIOMotorClient
from app.integrations.groq_market import matches, normalized_record
from app.integrations.market_evidence import SourceQuote, IST
from app.services.market_discovery import MarketDiscoveryService
from app.core.database import Database
from scripts.ensure_market_indexes import apply_market_indexes

pytestmark = [pytest.mark.asyncio, pytest.mark.skipif(
    os.environ.get("VAYALCONNECT_RUN_MONGO_TESTS") != "1",
    reason="Opt-in isolated local Mongo replica set")]


@pytest.fixture
async def isolated_market_db():
    uri = os.environ.get("VAYALCONNECT_TEST_MONGO_URI", "mongodb://127.0.0.1:27019/?replicaSet=vayal_verification")
    assert uri == "mongodb://127.0.0.1:27019/?replicaSet=vayal_verification", "Audit tests must use the isolated loopback replica set."
    client = AsyncIOMotorClient(uri, tz_aware=True, serverSelectionTimeoutMS=5000)
    name = "vayal_market_audit_" + uuid.uuid4().hex
    db = client[name]
    try:
        await db.market_prices.create_index("discovery_key", unique=True, sparse=True)
        yield db
    finally:
        # This generated database exists only on the exact loopback URI above.
        await client.drop_database(name)
        client.close()


def synthetic_record():
    query = dict(commodity="Audit flower", category="Novel flowers", market="Audit market",
                 state="Tamil Nadu", district="Madurai", variety=None)
    quote = SourceQuote(commodity=query["commodity"], market=query["market"], state=query["state"],
        district=query["district"], unit="bunch", currency="INR", price_paise=12500,
        observation_date=datetime.now(IST).date(), source="Synthetic audit feed",
        source_url="https://example.org/prices.json")
    return query, normalized_record(quote, query, datetime.now(timezone.utc))


async def test_real_cache_upsert_history_staleness_and_unverified_exclusion(isolated_market_db):
    db = isolated_market_db
    query, row = synthetic_record()
    service = MarketDiscoveryService(db)
    await service.repo.store_market_prices_bulk([row, row])
    assert await db.market_prices.count_documents({}) == 1
    stored = await db.market_prices.find_one({})
    created = stored["created_at"]
    await service.repo.store_market_prices_bulk([row])
    assert (await db.market_prices.find_one({}))["created_at"] == created
    current = await service.lookup(commodity=query["commodity"], category=query["category"], market=query["market"])
    assert current["count"] == 1 and not current["records"][0]["stale"]
    old = {**row, "source_record": dict(row["source_record"])}
    old_date = (datetime.now(IST).date() - timedelta(days=3)).isoformat()
    old["arrival_date"] = old["observation_date"] = old["source_record"]["observation_date"] = old_date
    await service.repo.store_market_prices_bulk([old])
    assert await db.market_prices.count_documents({}) == 2
    all_rows = await service.lookup(category=query["category"])
    assert sum(r["stale"] for r in all_rows["records"]) == 1
    await db.market_prices.update_many({}, {"$set": {"verification_status": "unverified"}})
    assert (await service.lookup(commodity=query["commodity"]))["records"] == []
    assert await db.market_watchlist.count_documents({}) == 0 # GET reads only.


async def test_real_concurrent_daily_claim_and_farmer_price_independence(isolated_market_db):
    db = isolated_market_db
    query, row = synthetic_record()
    product = {"product_name": query["commodity"], "category": query["category"],
        "market": query["market"], "district": query["district"], "state": query["state"],
        "status": "ACTIVE", "farmer_payout_per_unit_paise": 9999}
    product_id = (await db.products.insert_one(product)).inserted_id
    async def discover(contexts):
        await asyncio.sleep(.05)
        return {"records": [row], "groq_requests": 1, "message": "Synthetic mocked provider only"}
    provider = SimpleNamespace(name="Mock audit provider", matches=matches, discover_daily=AsyncMock(side_effect=discover))
    workers = [MarketDiscoveryService(db, provider), MarketDiscoveryService(db, provider)]
    outcomes = await asyncio.gather(*(worker.refresh_daily() for worker in workers))
    assert sum(r["completed"] for r in outcomes) == 1
    assert sum(r["skipped"] for r in outcomes) == 1
    provider.discover_daily.assert_awaited_once()
    assert len(provider.discover_daily.call_args.args[0]) == 1
    assert await db.market_prices.count_documents({}) == 1
    assert await db.market_daily_runs.count_documents({"_id": {"$regex": "^batch:"}}) == 1
    assert (await workers[0].refresh_daily())["skipped"] == 1
    assert (await db.products.find_one({"_id": product_id}))["farmer_payout_per_unit_paise"] == 9999


async def test_market_indexes_are_additive_and_repeatable(isolated_market_db):
    db = isolated_market_db
    _, row = synthetic_record()
    await db.market_prices.insert_one(dict(row))
    adapter = Database()
    adapter.db = db
    await apply_market_indexes(db)
    await adapter.create_indexes()
    await apply_market_indexes(db)
    indexes = await db.market_prices.index_information()
    assert any(spec["key"] == [
        ("verification_status", 1), ("verification_method", 1),
        ("commodity_id", 1), ("arrival_date", -1)] for spec in indexes.values())
    assert any(spec["key"] == [("discovery_key", 1)] and spec.get("unique")
               for spec in indexes.values())
    assert any(spec["key"] == [("reference_scope", 1), ("state", 1),
        ("verification_status", 1), ("commodity_id", 1), ("arrival_date", -1)]
        for spec in indexes.values())
    assert await db.market_prices.count_documents({}) == 1


async def test_statewide_cache_raw_audit_idempotency_and_failure_preserves_price(isolated_market_db, monkeypatch):
    from app.core.config import settings
    from app.integrations.statewide_market import StatewideMarketProvider
    from tests.test_statewide_market import observations, reference_fixture
    db = isolated_market_db
    monkeypatch.setattr(settings, "MARKET_STATEWIDE_ENABLED", True)
    monkeypatch.setattr(settings, "MARKET_SOURCE_VERIFIED", True)
    monkeypatch.setattr(settings, "GOVERNMENT_MARKET_API_KEY", "synthetic-key")
    await db.products.insert_one({"product_name": "Paddy", "category": "Grains", "market": "civai",
        "farmer_payout_per_unit_paise": 4321})
    retrieve = AsyncMock(return_value=(observations("Paddy"), []))
    provider = StatewideMarketProvider(SimpleNamespace(retrieve=retrieve))
    services = [MarketDiscoveryService(db, provider), MarketDiscoveryService(db, provider)]
    results = await asyncio.gather(*(s.refresh_daily() for s in services))
    assert sum(r["completed"] for r in results) == 1 and sum(r["skipped"] for r in results) == 1
    retrieve.assert_awaited_once()
    assert all(r.get("groq_requests", 0) == 0 for r in results)
    assert await db.market_prices.count_documents({"verification_method": "retrieved_source_record"}) == 3
    assert await db.market_prices.count_documents({"verification_method": "statewide_source_median"}) == 1
    result = await services[0].lookup(commodity="Paddy", scope="statewide", market="civai")
    row = result["records"][0]
    assert row["observation_count"] == 3 and row["price_paise"] == 20000
    await services[0].repo.store_market_prices_bulk([row, row])
    assert await db.market_prices.count_documents({"verification_method": "statewide_source_median"}) == 1
    assert (await db.products.find_one({}))["farmer_payout_per_unit_paise"] == 4321
    # A fresh generated database runs a source failure with an existing valid cache.
    other_name = db.name + "_failure"
    other = db.client[other_name]
    try:
        failing = MarketDiscoveryService(other, StatewideMarketProvider(SimpleNamespace(
            retrieve=AsyncMock(side_effect=TimeoutError("private")))))
        await other.products.insert_one({"product_name": "Paddy"})
        await failing.repo.store_market_prices_bulk([row])
        failure = await failing.refresh_daily()
        assert failure["failed"] == 1
        assert await other.market_prices.count_documents({}) == 1
        assert (await other.market_daily_runs.find_one({"_id": {"$regex": "^batch:"}}))["status"] == "failed"
    finally:
        await db.client.drop_database(other_name)
