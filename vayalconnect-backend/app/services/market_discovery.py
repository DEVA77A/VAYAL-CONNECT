"""Cache-only application reads and one shared provider attempt per IST day."""

import hashlib
import json
import logging
from datetime import datetime, timedelta, timezone
from pymongo.errors import DuplicateKeyError
from pymongo.errors import PyMongoError
from app.core.config import settings
from app.integrations.statewide_market import market_price_provider
from app.repositories.pricing import PricingRepository
from app.core.transactions import current_session

logger = logging.getLogger(__name__)


class BatchLimitError(ValueError):
    pass


def query_id(query):
    return hashlib.sha256(
        json.dumps(
            {
                k: (v.strip().casefold() if isinstance(v, str) else v)
                for k, v in query.items()
            },
            sort_keys=True,
        ).encode()
    ).hexdigest()


class MarketDiscoveryService:
    def __init__(self, db, provider=None):
        self.db = db
        self.repo = PricingRepository(db)
        self.provider = provider or market_price_provider

    async def lookup(self, **query):
        # Advisory reads/registration stay outside financial transactions.
        token = current_session.set(None)
        try:
            return await self._lookup(**query)
        except PyMongoError as exc:
            logger.warning("market_cache_failed category=%s", type(exc).__name__)
            return {
                "records": [],
                "count": 0,
                "live": False,
                "source": "Market cache",
                "error_code": "MARKET_CACHE_UNAVAILABLE",
                "message": "Verified market cache temporarily unavailable. Please retry.",
            }
        finally:
            current_session.reset(token)

    async def _lookup(
        self,
        commodity=None,
        state=None,
        district=None,
        market=None,
        category=None,
        variety=None,
        limit=20,
        offset=0,
        refresh=False,
        commodity_id=None,
        scope=None,
    ):
        if scope == "statewide":
            market = district = None
            state = "Tamil Nadu"
        cached = await self.repo.list_market_prices(
            commodity=commodity,
            state=state,
            district=district,
            market=market,
            category=category,
            commodity_id=commodity_id,
            limit=limit,
            offset=offset,
            scope=scope,
        )
        now = datetime.now(timezone.utc)
        valid = []
        for record in cached:
            if (
                scope == "statewide"
                and record.get("verification_method") != "statewide_source_median"
            ):
                continue
            if not self.provider.matches(record, commodity, market, state, district):
                continue
            if (
                variety
                and str(record.get("variety", "")).casefold() != variety.casefold()
            ):
                continue
            if (
                category
                and record.get("category")
                and str(record["category"]).casefold() != category.casefold()
            ):
                continue
            try:
                retrieved = record["retrieved_at"]
                if isinstance(retrieved, str):
                    retrieved = datetime.fromisoformat(retrieved.replace("Z", "+00:00"))
                if retrieved.tzinfo is None:
                    retrieved = retrieved.replace(tzinfo=timezone.utc)
                if timedelta(0) <= now - retrieved:
                    valid.append(record)
            except (KeyError, AttributeError, TypeError, ValueError):
                continue
        if not commodity:
            return self._result(
                valid,
                False,
                "Verified cached records from daily discovery; check observation dates.",
                now,
            )
        recent = [r for r in valid if self._current(r, now)]
        if recent:
            return self._result(
                recent, False, "Verified cached reference; check observation date.", now
            )
        # refresh is retained for backward compatibility, but cannot trigger HTTP.
        message = (
            "Current verified price unavailable; historical verified cache."
            if valid
            else "No verified price is available for this crop and selection. Enter your own selling price."
        )
        return self._result(valid, False, message, now)

    @staticmethod
    def _current(record, now):
        observed = datetime.fromisoformat(str(record["arrival_date"])[:10]).date()
        today = now.astimezone(timezone(timedelta(hours=5, minutes=30))).date()
        retrieved = record["retrieved_at"]
        if isinstance(retrieved, str):
            retrieved = datetime.fromisoformat(retrieved.replace("Z", "+00:00"))
        if retrieved.tzinfo is None:
            retrieved = retrieved.replace(tzinfo=timezone.utc)
        return observed == today and timedelta(0) <= now - retrieved < timedelta(
            hours=24
        )

    def _result(self, records, live, message, now, force_stale=False):
        return {
            "records": [
                {
                    **r,
                    "stale": force_stale or not self._current(r, now),
                    "freshness_status": "stale"
                    if force_stale or not self._current(r, now)
                    else "fresh",
                    "cached": not live,
                }
                for r in records
            ],
            "count": len(records),
            "live": live,
            "source": (
                ", ".join(sorted({r.get("source", "Unknown source") for r in records}))
                + " (Cached)"
            )
            if records
            else "Market cache",
            "message": message,
        }

    async def _load_queries(self, now_utc=None):
        queries = {}
        try:
            cursor = self.db["products"].find({"status": "ACTIVE"}, {"product_name": 1, "commodity": 1, "district": 1, "state": 1})
            async for p in cursor:
                c = p.get("product_name") or p.get("commodity")
                if c:
                    queries[c.casefold()] = {"commodity": c, "district": p.get("district"), "state": p.get("state")}
        except Exception:
            pass
        return queries

    async def refresh_daily(self, force: bool = False):
        """
        Executes daily market price update at 08:00 AM Asia/Kolkata.
        Delegates to centralized multi-provider MarketPriceOrchestrator.
        """
        from app.services.market_orchestrator import MarketPriceOrchestrator
        orchestrator = MarketPriceOrchestrator(self.db)
        return await orchestrator.refresh_daily(force=force)

    async def status(self):
        """Read-only administrative diagnostics for market pricing system."""
        from app.services.market_orchestrator import MarketPriceOrchestrator
        orchestrator = MarketPriceOrchestrator(self.db)
        return await orchestrator.status()
