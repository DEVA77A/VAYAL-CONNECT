"""Run with python -m scripts.refresh_market_prices; Render cron owns scheduling."""
import asyncio
import logging
from app.core.config import settings
from app.core.database import connect_db, close_db, get_database
from app.core.logging_config import setup_logging
from app.services.market_discovery import MarketDiscoveryService


async def main():
    setup_logging()
    if not settings.MARKET_STATEWIDE_ENABLED or not settings.MARKET_SOURCE_VERIFIED or not settings.MARKET_DAILY_REFRESH_ENABLED:
        logging.getLogger(__name__).warning("Statewide refresh disabled or source unverified. No database or provider request.")
        return 0
    try:
        await connect_db()
        stats = await MarketDiscoveryService(get_database()).refresh_daily()
        if stats.get("failed") or stats.get("unavailable"):
            logging.getLogger(__name__).error("Daily discovery unavailable or failed; cache preserved. Inspect structured job logs.")
            return 1
        return 0
    except Exception as exc:
        logging.getLogger(__name__).error("Market refresh failed category=%s; no retry.", type(exc).__name__)
        return 1
    finally:
        await close_db()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
