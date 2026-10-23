"""Read-only cache probe. Never calls Gemini or creates daily reservations."""
import argparse
import asyncio
import json
from motor.motor_asyncio import AsyncIOMotorClient
from app.core.config import settings
from app.integrations.groq_market import market_price_provider
from app.repositories.pricing import PricingRepository
from app.services.market_discovery import MarketDiscoveryService
from datetime import datetime, timezone, timedelta


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--commodity", default="Tomato")
    parser.add_argument("--state", default="Tamil Nadu")
    parser.add_argument("--district")
    parser.add_argument("--market")
    args = parser.parse_args()
    client = AsyncIOMotorClient(settings.MONGODB_URI)
    try:
        db = client[settings.MONGODB_DATABASE]
        records = await PricingRepository(db).list_market_prices(commodity=args.commodity,
            state=args.state, district=args.district, market=args.market, limit=100)
        now = datetime.now(timezone.utc)
        valid = []
        for r in records:
            if not market_price_provider.matches(r, args.commodity, args.market, args.state, args.district):
                continue
            try:
                stamp = r["retrieved_at"]
                if isinstance(stamp, str):
                    stamp = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
                if stamp.tzinfo is None:
                    stamp = stamp.replace(tzinfo=timezone.utc)
                if timedelta(0) <= now - stamp <= timedelta(days=settings.MARKET_CACHE_MAX_DAYS):
                    valid.append(r)
            except (KeyError, AttributeError, TypeError, ValueError):
                continue
        print(json.dumps({"available": bool(valid), "cache_only": True,
            "verified_record_count": len(valid),
            "records": [{**{k: str(r.get(k)) for k in ("commodity", "market", "unit", "arrival_date", "source")},
                "stale": not MarketDiscoveryService._current(r, now)} for r in valid]}))
    finally:
        client.close()


if __name__ == "__main__":
    asyncio.run(main())
