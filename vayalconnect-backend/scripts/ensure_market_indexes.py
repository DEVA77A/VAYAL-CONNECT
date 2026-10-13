"""Add market-cache indexes without changing documents or dropping collections.

Dry-run is the default. Applying requires the exact configured database name;
production additionally requires an explicit production flag and separate approval.
"""
import argparse
import asyncio

from motor.motor_asyncio import AsyncIOMotorClient
from pymongo.errors import PyMongoError

from app.core.config import settings


async def apply_market_indexes(db):
    prices = db["market_prices"]
    await prices.create_index("discovery_key", unique=True, sparse=True)
    await prices.create_index([("commodity_id", 1), ("arrival_date", -1)])
    await prices.create_index([("reference_scope", 1), ("state", 1),
        ("verification_status", 1), ("commodity_id", 1), ("arrival_date", -1)])
    await prices.create_index([("verification_status", 1), ("verification_method", 1),
                               ("commodity_id", 1), ("arrival_date", -1)])
    await prices.create_index([("category", 1), ("state", 1), ("district", 1),
                               ("market", 1), ("arrival_date", -1)])
    await db["market_watchlist"].create_index("requested_at")
    await db["market_daily_runs"].create_index("finished_at", expireAfterSeconds=7776000)


async def main():
    parser = argparse.ArgumentParser(description="Inspect or add VayalConnect market indexes")
    parser.add_argument("--apply", action="store_true", help="Create missing indexes; never deletes data")
    parser.add_argument("--confirm-database", help="Must equal the configured MONGODB_DATABASE")
    parser.add_argument("--allow-production", action="store_true",
                        help="Additional gate for an approved production index rollout")
    args = parser.parse_args()
    if not args.apply:
        print("Dry run: market_prices discovery_key unique sparse, crop/date, verified crop/date, "
              "statewide/state/verified/crop/date, category/location/date; market_watchlist requested_at; market_daily_runs finished_at TTL. "
              "No database connection or writes.")
        return 0
    if args.confirm_database != settings.MONGODB_DATABASE:
        print("Index apply refused: confirm the exact configured database name.")
        return 2
    if settings.is_production and not args.allow_production:
        print("Index apply refused: production requires separate approval and --allow-production.")
        return 2
    client = AsyncIOMotorClient(settings.MONGODB_URI, serverSelectionTimeoutMS=5000)
    try:
        await client.admin.command("ping")
        await apply_market_indexes(client[settings.MONGODB_DATABASE])
        print("Market indexes ensured in the confirmed database; no documents changed.")
        return 0
    except PyMongoError as exc:
        print("Market index apply failed: " + type(exc).__name__ + ". No records were deleted.")
        return 1
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
