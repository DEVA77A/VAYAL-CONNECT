"""Shared synthetic cache fixtures; no source retrieval or generation dependency."""
from types import SimpleNamespace as NS
from unittest.mock import AsyncMock, MagicMock
from pymongo.errors import DuplicateKeyError

def discovery(records, live=True):
    return dict(records=records, live=live, count=len(records), source="Gemini grounded discovery", message="Verified test fixture")

def db_fixture():
    db = MagicMock()
    collections = {}
    def get(name):
        if name not in collections:
            collections[name] = NS(update_one=AsyncMock(return_value=NS(modified_count=1, upserted_id=None)))
        return collections[name]
    db.__getitem__.side_effect = get
    return db

def daily_db(queries, products=None):
    db = db_fixture()
    async def iterate(items):
        for item in items:
            yield item
    db["products"].find = lambda *args: iterate(products or [])
    db["farmer_profiles"].find = lambda *args: iterate([])
    db["market_watchlist"].find = lambda *args: iterate([{"query": q} for q in queries])
    claims = NS(update_one=AsyncMock(), insert_one=AsyncMock(), find_one_and_update=AsyncMock(return_value={"_id": "refresh-lock"}))
    claims.with_options = MagicMock(return_value=claims)
    runs = {}
    async def update(query, change, **kwargs):
        if query.get("_id") in runs:
            runs[query["_id"]].update(change.get("$set", {}))
    claims.update_one.side_effect = update
    async def insert(doc):
        if doc["_id"] in runs:
            raise DuplicateKeyError("already reserved")
        runs[doc["_id"]] = dict(doc)
    claims.insert_one.side_effect = insert
    db["market_daily_runs"].with_options = claims.with_options
    return db, claims, runs
