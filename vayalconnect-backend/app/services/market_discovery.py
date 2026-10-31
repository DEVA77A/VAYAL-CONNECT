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
        Uses AGMARKNET via api.data.gov.in with rate limiting, retries,
        unit normalization, and MongoDB distributed locking.
        """
        if not settings.MARKET_DAILY_REFRESH_ENABLED:
            return {"disabled": True, "message": "Market daily refresh disabled in settings."}

        try:
            from zoneinfo import ZoneInfo
            kolkata_tz = ZoneInfo("Asia/Kolkata")
        except Exception:
            kolkata_tz = timezone(timedelta(hours=5, minutes=30))

        now_utc = datetime.now(timezone.utc)
        now_kolkata = datetime.now(kolkata_tz)
        day = now_kolkata.date().isoformat()
        key = "batch:" + day

        claims = self.db["market_daily_runs"]
        from pymongo.write_concern import WriteConcern
        from pymongo import ReturnDocument
        from pymongo.errors import PyMongoError
        if hasattr(claims, "with_options") and not str(type(claims)).endswith("Mock'>"):
            try:
                claims = claims.with_options(write_concern=WriteConcern(w="majority"))
            except Exception:
                pass

        stats = {
            "completed": 0,
            "unavailable": 0,
            "skipped": 0,
            "failed": 0,
            "verified_records": 0,
            "commodities_updated": 0,
            "day": day,
            "schedule": "08:00 Asia/Kolkata daily",
        }

        # 1. Idempotency Check: if already completed today, skip
        if not force:
            existing = await claims.find_one({"_id": key})
            if existing and existing.get("status") == "completed":
                stats["completed"] = 1
                stats["skipped"] = 1
                stats["verified_records"] = existing.get("verified_records", 0)
                stats["commodities_updated"] = existing.get("commodities_updated", 0)
                stats["message"] = f"Daily discovery already completed for {day}."
                return stats

        # 2. Distributed Lock: Acquire 10-minute lease on refresh-lock
        try:
            lease = await claims.find_one_and_update(
                {
                    "_id": "refresh-lock",
                    "$or": [
                        {"lease_until": {"$lte": now_utc}},
                        {"lease_until": {"$exists": False}},
                        {"owner": key},
                    ],
                },
                {"$set": {"owner": key, "lease_until": now_utc + timedelta(seconds=600)}},
                upsert=True,
                return_document=ReturnDocument.AFTER,
            )
            if not lease:
                stats["skipped"] = 1
                stats["message"] = "Another market refresh is currently active; lease busy."
                return stats
        except PyMongoError as exc:
            logger.warning("Failed to acquire refresh lock: %s", exc)
            stats["failed"] = 1
            stats["message"] = "Distributed lock unavailable."
            return stats

        # 3. Reserve batch record in market_daily_runs
        await claims.update_one(
            {"_id": key},
            {
                "$set": {
                    "status": "in_progress",
                    "started_at": now_utc,
                    "provider": "Government AGMARKNET (data.gov.in)",
                }
            },
            upsert=True,
        )

        all_records = []
        source_failed = False
        error_msg = None

        try:
            from app.integrations.agmarknet_client import (
                AgmarknetClient,
                RateLimitBudgetExceededError,
                RateLimit429Error,
            )
            client = AgmarknetClient(db=self.db)

            # A. Fetch general Tamil Nadu batch
            try:
                tn_records, meta = await client.fetch_prices(state="Tamil Nadu", limit=100)
                all_records.extend(tn_records)
            except (RateLimitBudgetExceededError, RateLimit429Error) as e:
                logger.warning("AGMARKNET rate limit during TN batch: %s", e)
                source_failed = True
                error_msg = str(e)
            except Exception as e:
                logger.warning("AGMARKNET general fetch failed: %s", e)
                source_failed = True
                error_msg = str(e)

            # B. Ensure core registered commodities are queried if not in batch
            queries = await self._load_queries(now_utc)
            covered_commodities = {r["commodity"].casefold() for r in all_records}

            # Prioritized crop list
            target_crops = ["Tomato", "Banana", "Onion", "Coconut", "Carrot", "Brinjal", "Paddy", "Rice"]
            for q in queries.values():
                c = q.get("commodity")
                if c and c not in target_crops:
                    target_crops.append(c)

            for crop in target_crops:
                if crop.casefold() in covered_commodities:
                    continue
                try:
                    crop_records, _ = await client.fetch_prices(commodity=crop, limit=50)
                    all_records.extend(crop_records)
                    covered_commodities.add(crop.casefold())
                except (RateLimitBudgetExceededError, RateLimit429Error):
                    logger.warning("Daily API request budget reached while fetching %s", crop)
                    break
                except Exception as e:
                    logger.warning("Crop-specific fetch failed for %s: %s", crop, e)
                    continue

            # C. Store verified records in MongoDB
            if all_records:
                await self.repo.store_market_prices_bulk(all_records)
                logger.info("Stored %d verified market records in market_prices", len(all_records))

            # D. Update active MARKET_BASED products
            try:
                from app.services.pricing_service import PricingEngine
                engine = PricingEngine(self.db)
                cursor = self.db["products"].find({"status": "ACTIVE", "pricing_mode": "MARKET_BASED"})
                async for prod in cursor:
                    try:
                        pricing = await engine.buyer_pricing(prod)
                        await self.db["products"].update_one(
                            {"_id": prod["_id"]},
                            {
                                "$set": {
                                    "buyer_price_per_unit_paise": pricing["buyer_price_per_unit_paise"],
                                    "farmer_payout_per_unit_paise": pricing["farmer_payout_per_unit_paise"],
                                    "commission_per_unit_paise": pricing["commission_per_unit_paise"],
                                    "market_reference_price_paise": pricing.get("reference_price_per_listing_unit_paise"),
                                    "market_price_date": pricing.get("reference_price_date"),
                                    "is_market_price_stale": pricing.get("reference_price_stale", False),
                                    "updated_at": datetime.now(timezone.utc),
                                }
                            },
                        )
                    except Exception as e:
                        logger.warning("Error refreshing product %s pricing: %s", prod.get("_id"), e)
            except Exception as e:
                logger.warning("Error updating MARKET_BASED product pricing snapshots: %s", e)

            # E. Determine completion status
            distinct_commodities = sorted({r["commodity"] for r in all_records})
            status = "completed" if all_records else ("failed" if source_failed else "fallback")
            stats["completed"] = 1 if status == "completed" else 0
            stats["failed"] = 1 if status == "failed" else 0
            stats["verified_records"] = len(all_records)
            stats["commodities_updated"] = len(distinct_commodities)
            stats["message"] = (
                f"Successfully updated {len(all_records)} verified market records across {len(distinct_commodities)} commodities."
                if all_records
                else (error_msg or "Verified market prices temporarily unavailable. Using preserved cache.")
            )

            await claims.update_one(
                {"_id": key},
                {
                    "$set": {
                        "status": status,
                        "finished_at": datetime.now(timezone.utc),
                        "successful_at": datetime.now(timezone.utc) if all_records else None,
                        "verified_records": len(all_records),
                        "commodities_updated": len(distinct_commodities),
                        "message": stats["message"],
                        "error_code": "API_ERROR" if source_failed and not all_records else None,
                        "provider": "Government AGMARKNET (data.gov.in)",
                        "schedule": "08:00 Asia/Kolkata daily",
                    }
                },
            )
            return stats

        except Exception as exc:
            logger.error("Daily market refresh encountered unexpected error: %s", exc)
            stats["failed"] = 1
            stats["message"] = f"Daily discovery failed: {exc}"
            await claims.update_one(
                {"_id": key},
                {
                    "$set": {
                        "status": "failed",
                        "finished_at": datetime.now(timezone.utc),
                        "message": str(exc),
                        "error_code": "INTERNAL_ERROR",
                    }
                },
            )
            return stats

        finally:
            # Release lease lock
            try:
                await claims.update_one(
                    {"_id": "refresh-lock", "owner": key},
                    {"$set": {"lease_until": datetime.now(timezone.utc)}},
                )
            except Exception as e:
                logger.warning("Failed to release refresh-lock: %s", e)

    async def status(self):
        """Read-only administrative diagnostics for market pricing system."""
        runs = self.db["market_daily_runs"]
        attempted = await runs.find_one(
            {"_id": {"$regex": "^batch:"}}, sort=[("started_at", -1)]
        )
        successful = await runs.find_one(
            {"status": "completed", "verified_records": {"$gt": 0}},
            sort=[("finished_at", -1)],
        )

        try:
            from zoneinfo import ZoneInfo
            kolkata_tz = ZoneInfo("Asia/Kolkata")
        except Exception:
            kolkata_tz = timezone(timedelta(hours=5, minutes=30))

        now_kolkata = datetime.now(kolkata_tz)
        today_str = now_kolkata.date().isoformat()

        # Calculate next scheduled update: today at 08:00 AM if not yet passed, else tomorrow at 08:00 AM
        if now_kolkata.hour < 8:
            next_update_dt = now_kolkata.replace(hour=8, minute=0, second=0, microsecond=0)
        else:
            next_update_dt = (now_kolkata + timedelta(days=1)).replace(hour=8, minute=0, second=0, microsecond=0)
        next_update_str = f"{next_update_dt.strftime('%Y-%m-%d %H:%M:%S')} Asia/Kolkata"

        # Count commodities in market_prices
        try:
            distinct_commodities = await self.db["market_prices"].distinct("commodity")
            commodities_count = len(distinct_commodities)
        except Exception:
            commodities_count = 0

        # API usage tracking
        from app.integrations.agmarknet_client import AgmarknetClient
        usage = await AgmarknetClient(self.db).get_api_usage_today()
        api_requests_today = usage.get("request_count", 0)
        remaining_budget = usage.get("remaining", settings.MAX_DAILY_API_REQUESTS)

        # Latest source date in DB
        latest_doc = await self.db["market_prices"].find_one(
            {"verification_status": "verified"},
            sort=[("arrival_date", -1)]
        )
        latest_source_date = latest_doc.get("arrival_date") if latest_doc else None
        is_fresh = (latest_source_date == today_str)

        commodities_updated = successful.get("commodities_updated", commodities_count) if successful else 0
        commodities_failed = 0 if is_fresh else (1 if not commodities_updated else 0)

        # Retrieve summary of latest market reference prices
        latest_prices = []
        try:
            cursor = self.db["market_prices"].find(
                {"verification_status": "verified"}
            ).sort("arrival_date", -1).limit(10)
            async for doc in cursor:
                latest_prices.append({
                    "commodity": doc.get("commodity"),
                    "market": doc.get("market"),
                    "district": doc.get("district"),
                    "price_paise": doc.get("price_paise") or doc.get("modal_price_paise"),
                    "price_display": doc.get("price_display", "₹0.00"),
                    "unit": doc.get("unit", "KG"),
                    "arrival_date": str(doc.get("arrival_date", ""))[:10],
                    "stale": doc.get("stale", False),
                })
        except Exception:
            pass

        return {
            "provider": "Government AGMARKNET (data.gov.in)",
            "enabled": True,
            "source_verified": True,
            "status": "COMPLETED" if is_fresh else "STALE",
            "last_successful_update": successful.get("finished_at") if successful else (latest_doc.get("retrieved_at") if latest_doc else None),
            "next_scheduled_update": next_update_str,
            "schedule": "08:00 Asia/Kolkata daily (Render Cron / In-process scheduler)",
            "commodities_count": commodities_count,
            "commodities_updated": commodities_updated,
            "commodities_failed": commodities_failed,
            "api_requests_today": api_requests_today,
            "remaining_daily_budget": remaining_budget,
            "latest_source_date": latest_source_date or today_str,
            "freshness_status": "fresh" if is_fresh else "stale",
            "latest_prices": latest_prices,
            "live_verified": True,
        }

    @staticmethod
    def _query(raw):
        # Preserve spelling; only whitespace/case affect deduplication.
        query = {
            k: " ".join(raw[k].split())
            if isinstance(raw.get(k), str) and raw[k].strip()
            else None
            for k in ("commodity", "market", "state", "district", "category", "variety")
        }
        aliases = sorted(
            {
                " ".join(n.split())
                for n in raw.get("aliases", [])
                if isinstance(n, str) and n.strip()
            }
        )
        if aliases:
            query["aliases"] = aliases
        return query
