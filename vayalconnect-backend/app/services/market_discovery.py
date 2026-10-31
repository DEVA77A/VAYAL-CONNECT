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

    async def refresh_daily(self):
        """Reserve the whole IST day before one request; never reopen after failure.

        A crash between reservation and dispatch can lose that day's request.
        This conservative at-most-once guarantee prevents ambiguous timeout retries.
        """
        if not settings.MARKET_DAILY_REFRESH_ENABLED:
            return {"disabled": True}
        now = datetime.now(timezone.utc)
        day = (
            now.astimezone(timezone(timedelta(hours=5, minutes=30))).date().isoformat()
        )
        stats = {
            "completed": 0,
            "unavailable": 0,
            "skipped": 0,
            "failed": 0,
            "contexts": 0,
            "day": day,
        }
        claims = self.db["market_daily_runs"]
        key = "batch:" + day
        try:
            # _id's unique index is built into MongoDB. Majority acknowledgement
            # prevents a failover from forgetting a dispatched day's reservation.
            from pymongo.write_concern import WriteConcern

            claims = claims.with_options(write_concern=WriteConcern(w="majority"))
            await claims.insert_one(
                {
                    "_id": key,
                    "status": "reserved",
                    "started_at": now,
                    "provider": getattr(
                        self.provider, "name", type(self.provider).__name__
                    ),
                }
            )
        except DuplicateKeyError:
            return {
                **stats,
                "skipped": 1,
                "message": "Daily discovery already reserved; no additional request.",
            }
        # A separate persistent lease prevents overlap across date boundaries.
        # Ten minutes exceeds the bounded retrieval + inference budget.
        from pymongo import ReturnDocument

        try:
            lease = await claims.find_one_and_update(
                {
                    "_id": "refresh-lock",
                    "$or": [
                        {"lease_until": {"$lte": now}},
                        {"lease_until": {"$exists": False}},
                    ],
                },
                {"$set": {"owner": key, "lease_until": now + timedelta(seconds=600)}},
                upsert=True,
                return_document=ReturnDocument.AFTER,
            )
            if not lease:
                return {
                    **stats,
                    "skipped": 1,
                    "message": "Refresh lease was not acknowledged; no request sent.",
                }
        except DuplicateKeyError:
            await claims.update_one(
                {"_id": key}, {"$set": {"status": "busy", "finished_at": now}}
            )
            return {
                **stats,
                "skipped": 1,
                "message": "Another market refresh is active; no request sent.",
            }
        except PyMongoError as exc:
            logger.warning(
                "daily_market_lease_failed day=%s category=%s", day, type(exc).__name__
            )
            try:
                await claims.update_one(
                    {"_id": key},
                    {
                        "$set": {
                            "status": "failed",
                            "error_code": "LEASE_UNAVAILABLE",
                            "finished_at": datetime.now(timezone.utc),
                        }
                    },
                )
            except PyMongoError:
                logger.warning("daily_market_status_write_failed day=%s", day)
            return {
                **stats,
                "failed": 1,
                "message": "Daily discovery lock unavailable; no provider request sent.",
            }
        try:
            queries = await self._load_queries(now)
            stats["contexts"] = len(queries)
            stats["contexts_missing_market_or_state"] = sum(
                not q.get("market") or not q.get("state") for q in queries.values()
            )
            await claims.update_one(
                {"_id": key}, {"$set": {"contexts": list(queries.values())}}
            )
            # Loading a large catalog can outlive the original lease. An expired
            # owner must never dispatch; a newer day's worker may already own it.
            refreshed_now = datetime.now(timezone.utc)
            lease = await claims.find_one_and_update(
                {
                    "_id": "refresh-lock",
                    "owner": key,
                    "lease_until": {"$gt": refreshed_now},
                },
                {"$set": {"lease_until": refreshed_now + timedelta(seconds=600)}},
                return_document=ReturnDocument.AFTER,
            )
            if not lease:
                stats["skipped"] = 1
                stats["message"] = (
                    "Refresh lease expired before discovery; no request sent."
                )
                await claims.update_one(
                    {"_id": key},
                    {"$set": {"status": "lease_expired", "finished_at": refreshed_now}},
                )
                return stats
            if not queries:
                outcome = {
                    "records": [],
                    "message": "No registered crops; no discovery request sent.",
                }
            else:
                outcome = await self.provider.discover_daily(list(queries.values()))
            stats["groq_requests"] = outcome.get("groq_requests", 0)
            stats["estimated_input_token_upper_bound"] = outcome.get(
                "estimated_input_token_upper_bound"
            )
            if outcome.get("error_code") and outcome.get("records"):
                raise ValueError("Provider returned records together with an error")
            records = [
                r for r in outcome.get("records", []) if self.provider.matches(r)
            ]
            observations = [
                r for r in outcome.get("observations", []) if self.provider.matches(r)
            ]
            if observations:
                await self.repo.store_market_prices_bulk(observations)
            if records:
                await self.repo.store_market_prices_bulk(records)
            source_failed = any(
                code in (outcome.get("diagnostics") or [])
                for code in ("OGD_SOURCE_UNAVAILABLE", "REVIEWED_SOURCE_UNAVAILABLE")
            )
            source_failed = source_failed or any(
                code.startswith(("TN_HTTP_", "TN_SOURCE_UNAVAILABLE_"))
                for code in (outcome.get("diagnostics") or [])
            )
            status = (
                "completed"
                if records
                else "failed"
                if (
                    source_failed
                    or outcome.get("error_code") not in (None, "NO_CURRENT_EVIDENCE")
                )
                else "unavailable"
            )
            stats[status] = 1
            stats["verified_records"] = len(records)
            stats["covered_contexts"] = sum(
                any(
                    self.provider.matches(
                        r,
                        q["commodity"],
                        q.get("market"),
                        q.get("state"),
                        q.get("district"),
                    )
                    and (
                        not q.get("variety")
                        or str(r.get("variety", "")).casefold()
                        == q["variety"].casefold()
                    )
                    for r in records
                )
                for q in queries.values()
            )
            stats["unavailable_contexts"] = len(queries) - stats["covered_contexts"]
            stats["diagnostics"] = outcome.get("diagnostics", [])
            stats["partial"] = bool(
                records and (source_failed or stats["unavailable_contexts"])
            )
            stats["message"] = outcome.get("message", "Verified prices unavailable.")
            stats["error_code"] = outcome.get("error_code")
            await claims.update_one(
                {"_id": key},
                {
                    "$set": {
                        "status": status,
                        "finished_at": datetime.now(timezone.utc),
                        "message": stats["message"],
                        "error_code": stats["error_code"],
                        "verified_records": len(records),
                        "provider": getattr(
                            self.provider, "name", type(self.provider).__name__
                        ),
                        "successful_at": datetime.now(timezone.utc)
                        if records
                        else None,
                        "context_statuses": outcome.get("context_statuses", []),
                        "partial": stats["partial"],
                        "groq_requests": outcome.get("groq_requests", 0),
                        "estimated_input_token_upper_bound": outcome.get(
                            "estimated_input_token_upper_bound"
                        ),
                        "diagnostics": outcome.get("diagnostics"),
                        "model": outcome.get("model"),
                    }
                },
            )
        except BatchLimitError:
            stats["failed"] = 1
            stats["message"] = (
                "Registered market batch exceeds the safe 10000-context limit; no request sent."
            )
            await claims.update_one(
                {"_id": key},
                {
                    "$set": {
                        "status": "failed",
                        "finished_at": datetime.now(timezone.utc),
                        "error_code": "BATCH_LIMIT",
                    }
                },
            )
        except Exception as exc:
            logger.warning(
                "daily_market_refresh_failed day=%s category=%s",
                day,
                type(exc).__name__,
            )
            stats["completed"] = 0
            stats["failed"] = 1
            # Reservation remains consumed even if persistence or status update fails.
            stats["message"] = (
                "Daily discovery failed; cache preserved and today's attempt will not repeat."
            )
            try:
                await claims.update_one(
                    {"_id": key},
                    {
                        "$set": {
                            "status": "failed",
                            "finished_at": datetime.now(timezone.utc),
                        }
                    },
                )
            except PyMongoError:
                logger.warning("daily_market_status_write_failed day=%s", day)
        finally:
            try:
                await claims.update_one(
                    {"_id": "refresh-lock", "owner": key},
                    {"$set": {"lease_until": datetime.now(timezone.utc)}},
                )
            except PyMongoError:
                logger.warning("daily_market_lease_release_failed day=%s", day)
        logger.info("daily_market_refresh_finished stats=%s", stats)
        return stats

    async def _load_queries(self, now):
        queries = {}
        # Verified source coverage must not depend on a farmer publishing first.
        from app.integrations.tn_market import CROPS
        from app.integrations.statewide_market import StatewideMarketProvider

        if isinstance(self.provider, StatewideMarketProvider):
            for name, aliases in CROPS.values():
                query = self._query(
                    {"commodity": name, "aliases": list(aliases), "state": "Tamil Nadu"}
                )
                queries[query_id(query)] = query
        async for target in self.db["market_watchlist"].find({}):
            query = self._query(target.get("query", {}))
            if query["commodity"]:
                queries.setdefault(query_id(query), query)
                if len(queries) > 10000:
                    raise BatchLimitError(
                        "Registered market batch exceeds 10000 contexts"
                    )
        async for product in self.db["products"].find({}):
            query = self._query(
                dict(
                    commodity=product.get("product_name"),
                    market=product.get("market"),
                    state=product.get("state"),
                    district=product.get("district"),
                    category=product.get("category"),
                    variety=product.get("variety"),
                    aliases=[
                        product.get("product_name_en"),
                        product.get("product_name_ta"),
                    ],
                )
            )
            if query["commodity"]:
                key = query_id(query)
                queries.setdefault(key, query)
                if len(queries) > 10000:
                    raise BatchLimitError(
                        "Registered market batch exceeds 10000 contexts"
                    )
                await self.db["market_watchlist"].update_one(
                    {"_id": key},
                    {"$set": {"query": query, "requested_at": now}},
                    upsert=True,
                )
        # Farmer onboarding stores free-text crop names, not a separate crop catalog.
        # Split only explicit delimiters. Never infer markets from a postal address.
        import re

        async for profile in self.db["farmer_profiles"].find({}):
            application = profile.get("application") or {}
            crops = application.get("crops")
            names = (
                re.split(r"[,;\n]", crops)
                if isinstance(crops, str)
                else crops
                if isinstance(crops, list)
                else []
            )
            for name in names:
                query = self._query(
                    dict(
                        commodity=name,
                        category=application.get("category"),
                        market=application.get("market"),
                        district=application.get("district"),
                        state=application.get("state"),
                    )
                )
                if query["commodity"]:
                    queries.setdefault(query_id(query), query)
                    if len(queries) > 10000:
                        raise BatchLimitError(
                            "Registered market batch exceeds 10000 contexts"
                        )
        return queries

    async def status(self):
        """Read-only administrative diagnostics; no secrets or upstream requests."""
        runs = self.db["market_daily_runs"]
        attempted = await runs.find_one(
            {"_id": {"$regex": "^batch:"}}, sort=[("started_at", -1)]
        )
        successful = await runs.find_one(
            {"status": "completed", "verified_records": {"$gt": 0}},
            sort=[("finished_at", -1)],
        )

        now = datetime.now(timezone.utc)
        ist_tz = timezone(timedelta(hours=5, minutes=30))
        now_ist = now.astimezone(ist_tz)
        next_update_date = now_ist.date() if now_ist.hour < 6 else now_ist.date() + timedelta(days=1)
        next_update_str = f"{next_update_date.isoformat()} 06:00:00 IST"

        # Count commodities in market_prices
        try:
            distinct_commodities = await self.db["market_prices"].distinct("commodity")
            commodities_count = len(distinct_commodities)
        except Exception:
            commodities_count = 0

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
            "provider": getattr(self.provider, "name", "Government AGMARKNET & TN Mandis"),
            "enabled": settings.MARKET_STATEWIDE_ENABLED,
            "source_verified": settings.MARKET_SOURCE_VERIFIED,
            "groq_enabled": settings.GROQ_MARKET_ENABLED,
            "last_attempted_at": attempted.get("started_at") if attempted else None,
            "last_attempt_status": attempted.get("status") if attempted else None,
            "last_attempt_partial": attempted.get("partial", False) if attempted else False,
            "last_attempt_diagnostics": attempted.get("diagnostics", []) if attempted else [],
            "daily_refresh_enabled": settings.MARKET_DAILY_REFRESH_ENABLED,
            "last_successful_at": successful.get("finished_at") if successful else (attempted.get("finished_at") if attempted and attempted.get("status") == "completed" else None),
            "next_scheduled_update": next_update_str,
            "schedule": "06:00 Asia/Kolkata daily (Render Cron / In-process scheduler)",
            "commodities_count": commodities_count,
            "verified_records_count": attempted.get("verified_records", 0) if attempted else len(latest_prices),
            "failed_records_count": 1 if attempted and attempted.get("status") in ("failed", "unavailable") else 0,
            "latest_prices": latest_prices,
            "live_verified": False,
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
