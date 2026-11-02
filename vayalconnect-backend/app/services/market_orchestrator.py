"""
VayalConnect Backend — Centralized Multi-Provider Market Price Orchestrator

Manages agricultural market price discovery, validation, and storage
across the defined multi-provider hierarchy:
  1. Primary Provider: Government AGMARKNET / data.gov.in (with daily 100-request quota)
  2. Secondary Provider: Tamil Nadu Agricultural Marketing Department — Uzhavar Santhai
  3. Tertiary Provider: Gemini AI Grounded Market Data Provider (strictly verified web evidence)
  4. Final Fallback: MongoDB Last Valid Market Price (marked stale)

Strict Principles:
- Never fabricate, generate, or guess agricultural prices with AI.
- Only accept Gemini results backed by verified external web sources.
- No repeated polling loops every minute after quota exhaustion.
- Atomic MongoDB budget tracking and distributed lease locking.
- All monetary values in integer paise; 1 Quintal = 100 Kilograms.
"""

import asyncio
import logging
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from typing import Any, Dict, List, Optional, Tuple

from pymongo import ReturnDocument
from pymongo.errors import PyMongoError

from app.core.config import settings
from app.integrations.agmarknet_client import (
    AgmarknetClient,
    RateLimit429Error,
    RateLimitBudgetExceededError,
    get_today_kolkata_str,
)
from app.integrations.gemini_market import (
    GeminiMarketPriceProvider,
    market_price_provider as default_gemini_provider,
)
from app.integrations.tn_market import TamilNaduMarketRetriever, crop_mapping
from app.repositories.pricing import PricingRepository

logger = logging.getLogger(__name__)

try:
    from zoneinfo import ZoneInfo
    KOLKATA_TZ = ZoneInfo("Asia/Kolkata")
except Exception:
    KOLKATA_TZ = timezone(timedelta(hours=5, minutes=30))


def normalize_unit(unit_str: Optional[str]) -> str:
    """Normalize unit string to standard uppercase code."""
    if not unit_str:
        return "KG"
    u = unit_str.strip().upper()
    if u in ("KG", "KILOGRAM", "KGS"):
        return "KG"
    if u in ("QUINTAL", "QUI", "QTL"):
        return "QUINTAL"
    if u in ("GRAM", "GM", "G"):
        return "GRAM"
    if u in ("TONNE", "TON"):
        return "TONNE"
    if u in ("PIECE", "PC", "PCS", "COUNT", "NOS"):
        return "PIECE"
    if u in ("DOZEN", "DZ"):
        return "DOZEN"
    if u in ("BUNCH", "BUNDLE"):
        return "BUNCH"
    if u in ("LITRE", "LITER", "L"):
        return "LITRE"
    return u


def convert_price_unit(price_paise: int, source_unit: str, target_unit: str) -> int:
    """Convert price between standard units using Decimal arithmetic and integer paise."""
    src = normalize_unit(source_unit)
    tgt = normalize_unit(target_unit)
    if src == tgt:
        return price_paise

    factors_to_kg = {
        "QUINTAL": Decimal("100"),
        "TONNE": Decimal("1000"),
        "KG": Decimal("1"),
        "GRAM": Decimal("0.001"),
    }

    if src in factors_to_kg and tgt in factors_to_kg:
        price_per_kg = Decimal(price_paise) / factors_to_kg[src]
        target_price = price_per_kg * factors_to_kg[tgt]
        return int(target_price.quantize(Decimal("1"), rounding=ROUND_HALF_UP))

    # Units that cannot be safely converted (e.g. piece vs kg) remain unconverted
    return price_paise


class MarketPriceOrchestrator:
    """
    Central orchestrator coordinating multi-provider agricultural market prices.
    """

    def __init__(self, db, http_client=None):
        self.db = db
        self.repo = PricingRepository(db) if db is not None else None
        self.agmarknet = AgmarknetClient(db=db, http_client=http_client)
        self.tn_market = TamilNaduMarketRetriever()
        self.gemini = default_gemini_provider or GeminiMarketPriceProvider()

    async def get_market_price(
        self,
        commodity: str,
        state: str = "Tamil Nadu",
        district: Optional[str] = None,
        market: Optional[str] = None,
        unit: str = "KG",
    ) -> Dict[str, Any]:
        """
        Retrieves the latest verified market price for a given commodity following the provider hierarchy.
        1. Checks whether a fresh verified price exists in MongoDB for today.
        2. Tries AGMARKNET / data.gov.in (if daily budget allows).
        3. Tries Secondary Provider (Uzhavar Santhai).
        4. Tries Tertiary Provider (Gemini Grounded).
        5. Falls back to last known valid MongoDB cached price (marked stale).
        """
        today_str = get_today_kolkata_str()
        target_unit = normalize_unit(unit)

        # -----------------------------------------------------------------
        # STEP 1: Check if fresh verified price already in MongoDB for today
        # -----------------------------------------------------------------
        if self.db is not None:
            try:
                query: Dict[str, Any] = {
                    "commodity": {"$regex": f"^{commodity.strip()}$", "$options": "i"},
                    "verification_status": "verified",
                    "arrival_date": today_str,
                }
                if district:
                    query["district"] = {"$regex": f"^{district.strip()}$", "$options": "i"}
                doc = await self.db["market_prices"].find_one(query, sort=[("retrieved_at", -1)])
                if not doc and district:
                    # Fallback to statewide for this commodity today
                    doc = await self.db["market_prices"].find_one(
                        {"commodity": {"$regex": f"^{commodity.strip()}$", "$options": "i"}, "arrival_date": today_str},
                        sort=[("retrieved_at", -1)],
                    )
                if doc:
                    raw_paise = doc.get("price_paise", 0)
                    src_unit = doc.get("unit", "KG")
                    converted_paise = convert_price_unit(raw_paise, src_unit, target_unit)
                    return {
                        "reference_price_available": True,
                        "government_reference_price_paise": raw_paise,
                        "reference_price_per_listing_unit_paise": converted_paise,
                        "reference_price_unit": src_unit,
                        "reference_listing_unit": target_unit,
                        "reference_price_date": today_str,
                        "reference_price_source": doc.get("source_name") or doc.get("source", "Government Mandi Data"),
                        "reference_price_source_url": doc.get("source_url"),
                        "source_provider": doc.get("source_provider", "AGMARKNET"),
                        "reference_price_stale": False,
                        "is_fallback": False,
                        "reference_commodity": doc.get("commodity", commodity),
                        "reference_market": doc.get("market", market or "Tamil Nadu"),
                        "reference_district": doc.get("district", district),
                        "reference_state": doc.get("state", state),
                        "market_price_status_message": "Updated today from official agricultural market data.",
                    }
            except Exception as e:
                logger.warning("Error checking today's cached market price: %s", e)

        # -----------------------------------------------------------------
        # STEP 2: Primary Provider — AGMARKNET (if daily budget allows)
        # -----------------------------------------------------------------
        agmarknet_exhausted = await self.agmarknet.is_exhausted_today()
        if not agmarknet_exhausted:
            try:
                records, meta = await self.agmarknet.fetch_prices(
                    commodity=commodity,
                    district=district,
                    state=state,
                    limit=50,
                )
                if records:
                    if self.repo:
                        await self.repo.store_market_prices_bulk(records)
                    best = records[0]
                    raw_paise = best.get("price_paise", 0)
                    src_unit = best.get("unit", "KG")
                    converted_paise = convert_price_unit(raw_paise, src_unit, target_unit)
                    return {
                        "reference_price_available": True,
                        "government_reference_price_paise": raw_paise,
                        "reference_price_per_listing_unit_paise": converted_paise,
                        "reference_price_unit": src_unit,
                        "reference_listing_unit": target_unit,
                        "reference_price_date": best.get("arrival_date", today_str),
                        "reference_price_source": "Government AGMARKNET (data.gov.in)",
                        "reference_price_source_url": f"https://api.data.gov.in/resource/{settings.active_market_resource_id}",
                        "source_provider": "AGMARKNET",
                        "reference_price_stale": False,
                        "is_fallback": False,
                        "reference_commodity": best.get("commodity", commodity),
                        "reference_market": best.get("market", market or "Tamil Nadu"),
                        "reference_district": best.get("district", district),
                        "reference_state": best.get("state", state),
                        "market_price_status_message": "Updated today from Government AGMARKNET data.",
                    }
            except (RateLimitBudgetExceededError, RateLimit429Error) as e:
                logger.info("AGMARKNET budget exhausted or rate limited: %s. Transitioning to secondary provider.", e)
            except Exception as e:
                logger.warning("AGMARKNET request failed: %s. Transitioning to secondary provider.", e)

        # -----------------------------------------------------------------
        # STEP 3: Secondary Provider — Tamil Nadu Uzhavar Santhai
        # -----------------------------------------------------------------
        try:
            if crop_mapping({"commodity": commodity}) is not None:
                quotes, diagnostics = await self.tn_market.retrieve([{"commodity": commodity, "state": state, "district": district}])
                if quotes:
                    best_q = quotes[0]
                    parsed_records = []
                    for q in quotes:
                        parsed_records.append({
                            "commodity": q.commodity,
                            "market": q.market,
                            "district": q.district,
                            "state": q.state,
                            "arrival_date": q.observation_date.isoformat(),
                            "unit": q.unit.upper(),
                            "price_paise": q.price_paise,
                            "min_price_paise": q.min_price_paise,
                            "max_price_paise": q.max_price_paise,
                            "modal_price_paise": q.price_paise,
                            "price_type": "modal",
                            "source": q.source,
                            "source_name": q.source,
                            "source_url": q.source_url,
                            "source_provider": "UZHAVAR_SANTHAI",
                            "verification_status": "verified",
                            "verification_method": q.calculation_method,
                            "retrieved_at": datetime.now(timezone.utc).isoformat(),
                        })
                    if self.repo:
                        await self.repo.store_market_prices_bulk(parsed_records)

                    raw_paise = best_q.price_paise
                    src_unit = best_q.unit.upper()
                    converted_paise = convert_price_unit(raw_paise, src_unit, target_unit)
                    return {
                        "reference_price_available": True,
                        "government_reference_price_paise": raw_paise,
                        "reference_price_per_listing_unit_paise": converted_paise,
                        "reference_price_unit": src_unit,
                        "reference_listing_unit": target_unit,
                        "reference_price_date": best_q.observation_date.isoformat(),
                        "reference_price_source": best_q.source,
                        "reference_price_source_url": best_q.source_url,
                        "source_provider": "UZHAVAR_SANTHAI",
                        "reference_price_stale": False,
                        "is_fallback": True,
                        "fallback_reason": "AGMARKNET_UNAVAILABLE_UZHAVAR_SANTHAI_VERIFIED",
                        "reference_commodity": best_q.commodity,
                        "reference_market": best_q.market,
                        "reference_district": best_q.district,
                        "reference_state": best_q.state,
                        "market_price_status_message": "Updated today from Tamil Nadu Uzhavar Santhai.",
                    }
        except Exception as e:
            logger.warning("Secondary provider Uzhavar Santhai failed for %s: %s", commodity, e)

        # -----------------------------------------------------------------
        # STEP 4: Tertiary Provider — Gemini Grounded Market Data
        # -----------------------------------------------------------------
        try:
            if settings.GEMINI_API_KEY.strip() and not await self.gemini.is_exhausted_today(self.db):
                gemini_res = await self.gemini._run_discovery(
                    [{"commodity": commodity, "state": state, "district": district, "market": market}],
                    db=self.db,
                )
                records = gemini_res.get("records", [])
                if records:
                    best_g = records[0]
                    # Ensure records are stored in MongoDB with full transparency
                    for r in records:
                        r["source_provider"] = "GEMINI_GROUNDED"
                        r["verification_status"] = "verified"
                        r["retrieved_at"] = datetime.now(timezone.utc).isoformat()
                    if self.repo:
                        await self.repo.store_market_prices_bulk(records)

                    raw_paise = best_g.get("price_paise", 0)
                    src_unit = best_g.get("unit", "KG").upper()
                    converted_paise = convert_price_unit(raw_paise, src_unit, target_unit)
                    return {
                        "reference_price_available": True,
                        "government_reference_price_paise": raw_paise,
                        "reference_price_per_listing_unit_paise": converted_paise,
                        "reference_price_unit": src_unit,
                        "reference_listing_unit": target_unit,
                        "reference_price_date": best_g.get("arrival_date", today_str),
                        "reference_price_source": best_g.get("source_name") or f"Grounded Web: {best_g.get('source', 'Gemini Verified')}",
                        "reference_price_source_url": best_g.get("source_url"),
                        "source_provider": "GEMINI_GROUNDED",
                        "reference_price_stale": False,
                        "is_fallback": True,
                        "fallback_reason": "AGMARKNET_UNAVAILABLE_GEMINI_GROUNDED_VERIFIED",
                        "reference_commodity": best_g.get("commodity", commodity),
                        "reference_market": best_g.get("market", market or "Tamil Nadu"),
                        "reference_district": best_g.get("district", district),
                        "reference_state": best_g.get("state", state),
                        "market_price_status_message": "Updated today from verified web source via Gemini Search Grounding.",
                    }
        except Exception as e:
            logger.warning("Tertiary provider Gemini Grounding failed for %s: %s", commodity, e)

        # -----------------------------------------------------------------
        # STEP 5: Final Fallback — MongoDB Last Valid Cached Market Price
        # -----------------------------------------------------------------
        if self.db is not None:
            try:
                cached_doc = await self.db["market_prices"].find_one(
                    {"commodity": {"$regex": f"^{commodity.strip()}$", "$options": "i"}, "verification_status": "verified"},
                    sort=[("arrival_date", -1), ("retrieved_at", -1)],
                )
                if cached_doc:
                    raw_paise = cached_doc.get("price_paise", 0)
                    src_unit = cached_doc.get("unit", "KG").upper()
                    converted_paise = convert_price_unit(raw_paise, src_unit, target_unit)
                    obs_date = str(cached_doc.get("arrival_date") or cached_doc.get("observation_date") or "")[:10]
                    return {
                        "reference_price_available": True,
                        "government_reference_price_paise": raw_paise,
                        "reference_price_per_listing_unit_paise": converted_paise,
                        "reference_price_unit": src_unit,
                        "reference_listing_unit": target_unit,
                        "reference_price_date": obs_date or today_str,
                        "reference_price_source": cached_doc.get("source_name") or cached_doc.get("source", "Preserved Mandi Cache"),
                        "reference_price_source_url": cached_doc.get("source_url"),
                        "source_provider": "DATABASE_CACHE",
                        "reference_price_stale": True,
                        "is_fallback": True,
                        "fallback_reason": "ALL_EXTERNAL_PROVIDERS_UNAVAILABLE",
                        "reference_commodity": cached_doc.get("commodity", commodity),
                        "reference_market": cached_doc.get("market", market or "Tamil Nadu"),
                        "reference_district": cached_doc.get("district", district),
                        "reference_state": cached_doc.get("state", state),
                        "market_price_status_message": "Market price update unavailable. Showing the last available price.",
                    }
            except Exception as e:
                logger.warning("Failed to read last known MongoDB price for %s: %s", commodity, e)

        # Ultimate fallback when no records ever recorded
        return {
            "reference_price_available": False,
            "government_reference_price_paise": 0,
            "reference_price_per_listing_unit_paise": 0,
            "reference_price_unit": target_unit,
            "reference_listing_unit": target_unit,
            "reference_price_date": today_str,
            "reference_price_source": "None",
            "reference_price_source_url": None,
            "source_provider": "NONE",
            "reference_price_stale": True,
            "is_fallback": True,
            "fallback_reason": "NO_VERIFIED_DATA",
            "reference_commodity": commodity,
            "reference_market": market or "Tamil Nadu",
            "reference_district": district,
            "reference_state": state,
            "market_price_status_message": "Market price update unavailable. Showing the last available price.",
        }

    async def refresh_daily(self, force: bool = False) -> Dict[str, Any]:
        """
        Executes daily multi-provider market price update for 08:00 AM Asia/Kolkata.
        Includes MongoDB distributed locking, idempotency check, provider fallback,
        unit normalization, and active MARKET_BASED product updating.
        """
        if not settings.MARKET_DAILY_REFRESH_ENABLED:
            return {"disabled": True, "message": "Market daily refresh disabled in settings."}

        now_utc = datetime.now(timezone.utc)
        now_kolkata = datetime.now(KOLKATA_TZ)
        day = now_kolkata.date().isoformat()
        key = f"batch:{day}"

        claims = self.db["market_daily_runs"] if self.db is not None else None
        stats = {
            "completed": 0,
            "unavailable": 0,
            "skipped": 0,
            "failed": 0,
            "verified_records": 0,
            "commodities_updated": 0,
            "day": day,
            "schedule": "08:00 Asia/Kolkata daily",
            "primary_provider": "AGMARKNET (data.gov.in)",
            "primary_records": 0,
            "secondary_records": 0,
            "gemini_records": 0,
            "fallback_records": 0,
        }

        if claims is None:
            return stats

        # 1. Idempotency Check: if today's batch already completed or fallback_completed, skip
        if not force:
            existing = await claims.find_one({"_id": key})
            if existing and existing.get("status") in ("completed", "fallback_completed"):
                stats["completed"] = 1
                stats["skipped"] = 1
                stats["verified_records"] = existing.get("verified_records", 0)
                stats["commodities_updated"] = existing.get("commodities_updated", 0)
                stats["message"] = f"Daily discovery already completed for {day}."
                return stats

        # 2. Distributed Lock Lease
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

        # 3. Mark batch run in_progress
        await claims.update_one(
            {"_id": key},
            {
                "$set": {
                    "status": "in_progress",
                    "started_at": now_utc,
                    "schedule": "08:00 Asia/Kolkata daily",
                }
            },
            upsert=True,
        )

        all_records: List[Dict[str, Any]] = []
        covered_commodities = set()
        primary_failed = False
        primary_exhausted = False

        # Gather target commodities from products collection
        target_crops = ["Tomato", "Banana", "Onion", "Coconut", "Carrot", "Brinjal", "Paddy", "Rice"]
        try:
            cursor = self.db["products"].find({"status": "ACTIVE"}, {"product_name": 1, "commodity": 1})
            async for p in cursor:
                c = p.get("product_name") or p.get("commodity")
                if c and c not in target_crops:
                    target_crops.append(c)
        except Exception:
            pass

        # -------------------------------------------------------------
        # STAGE 1: Primary Provider (AGMARKNET data.gov.in)
        # -------------------------------------------------------------
        if not await self.agmarknet.is_exhausted_today():
            try:
                tn_records, _ = await self.agmarknet.fetch_prices(state="Tamil Nadu", limit=100)
                all_records.extend(tn_records)
                stats["primary_records"] += len(tn_records)
                for r in tn_records:
                    covered_commodities.add(r["commodity"].casefold())
            except (RateLimitBudgetExceededError, RateLimit429Error) as e:
                logger.info("AGMARKNET daily quota exhausted during batch: %s. Switching to secondary provider.", e)
                primary_exhausted = True
                primary_failed = True
            except Exception as e:
                logger.warning("AGMARKNET batch fetch failed: %s", e)
                primary_failed = True

            # If primary is not exhausted, fetch missing specific crops
            if not primary_exhausted and not primary_failed:
                for crop in target_crops:
                    if crop.casefold() in covered_commodities:
                        continue
                    try:
                        crop_records, _ = await self.agmarknet.fetch_prices(commodity=crop, limit=50)
                        all_records.extend(crop_records)
                        stats["primary_records"] += len(crop_records)
                        covered_commodities.add(crop.casefold())
                    except (RateLimitBudgetExceededError, RateLimit429Error):
                        logger.info("AGMARKNET budget exhausted while querying %s. Breaking primary loop.", crop)
                        primary_exhausted = True
                        break
                    except Exception as e:
                        logger.warning("AGMARKNET crop fetch failed for %s: %s", crop, e)
                        continue

        # -------------------------------------------------------------
        # STAGE 2: Secondary Provider (Uzhavar Santhai)
        # -------------------------------------------------------------
        missing_for_secondary = [
            {"commodity": crop, "state": "Tamil Nadu"}
            for crop in target_crops
            if crop.casefold() not in covered_commodities and crop_mapping({"commodity": crop}) is not None
        ]
        if missing_for_secondary:
            try:
                sec_quotes, _ = await self.tn_market.retrieve(missing_for_secondary)
                for q in sec_quotes:
                    all_records.append({
                        "commodity": q.commodity,
                        "market": q.market,
                        "district": q.district,
                        "state": q.state,
                        "arrival_date": q.observation_date.isoformat(),
                        "unit": q.unit.upper(),
                        "price_paise": q.price_paise,
                        "min_price_paise": q.min_price_paise,
                        "max_price_paise": q.max_price_paise,
                        "modal_price_paise": q.price_paise,
                        "price_type": "modal",
                        "source": q.source,
                        "source_name": q.source,
                        "source_url": q.source_url,
                        "source_provider": "UZHAVAR_SANTHAI",
                        "verification_status": "verified",
                        "verification_method": q.calculation_method,
                        "retrieved_at": now_utc.isoformat(),
                    })
                    covered_commodities.add(q.commodity.casefold())
                stats["secondary_records"] = len(sec_quotes)
            except Exception as e:
                logger.warning("Secondary provider Uzhavar Santhai failed during daily refresh: %s", e)

        # -------------------------------------------------------------
        # STAGE 3: Tertiary Provider (Gemini Grounded Market Data)
        # -------------------------------------------------------------
        missing_for_gemini = [
            {"commodity": crop, "state": "Tamil Nadu"}
            for crop in target_crops
            if crop.casefold() not in covered_commodities
        ]
        if missing_for_gemini and settings.GEMINI_API_KEY.strip() and not await self.gemini.is_exhausted_today(self.db):
            try:
                gemini_res = await self.gemini._run_discovery(missing_for_gemini, db=self.db)
                gem_records = gemini_res.get("records", [])
                for r in gem_records:
                    r["source_provider"] = "GEMINI_GROUNDED"
                    r["verification_status"] = "verified"
                    r["retrieved_at"] = now_utc.isoformat()
                    all_records.append(r)
                    covered_commodities.add(r["commodity"].casefold())
                stats["gemini_records"] = len(gem_records)
            except Exception as e:
                logger.warning("Tertiary provider Gemini Grounding failed during daily refresh: %s", e)

        # -------------------------------------------------------------
        # STAGE 4: Store verified records in MongoDB
        # -------------------------------------------------------------
        if all_records and self.repo:
            await self.repo.store_market_prices_bulk(all_records)
            logger.info("Stored %d verified multi-provider records in market_prices", len(all_records))

        # -------------------------------------------------------------
        # STAGE 5: Update active MARKET_BASED products
        # -------------------------------------------------------------
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
                                "source_provider": pricing.get("source_provider", "AGMARKNET"),
                                "updated_at": datetime.now(timezone.utc),
                            }
                        },
                    )
                except Exception as e:
                    logger.warning("Error refreshing product %s pricing snapshot: %s", prod.get("_id"), e)
        except Exception as e:
            logger.warning("Error updating active MARKET_BASED products: %s", e)

        # -------------------------------------------------------------
        # STAGE 6: Finalize batch run outcome
        # -------------------------------------------------------------
        distinct_commodities = sorted({r["commodity"] for r in all_records})
        # If at least some fresh records were fetched -> "completed"
        # If no fresh records fetched but fallbacks preserved -> "fallback_completed" (prevents repeating loops!)
        status_code = "completed" if all_records else "fallback_completed"
        stats["completed"] = 1
        stats["verified_records"] = len(all_records)
        stats["commodities_updated"] = len(distinct_commodities)
        stats["message"] = (
            f"Daily market update finished ({len(all_records)} verified records across {len(distinct_commodities)} commodities)."
            if all_records
            else "Daily market update completed using preserved verified cache."
        )

        # Determine last successful provider
        last_provider = "AGMARKNET (data.gov.in)"
        if stats["secondary_records"] > 0 and stats["primary_records"] == 0:
            last_provider = "Tamil Nadu Uzhavar Santhai"
        elif stats["gemini_records"] > 0 and stats["primary_records"] == 0 and stats["secondary_records"] == 0:
            last_provider = "Gemini Grounded Discovery"
        elif not all_records:
            last_provider = "MongoDB Verified Cache"

        await claims.update_one(
            {"_id": key},
            {
                "$set": {
                    "status": status_code,
                    "finished_at": datetime.now(timezone.utc),
                    "successful_at": datetime.now(timezone.utc),
                    "verified_records": len(all_records),
                    "commodities_updated": len(distinct_commodities),
                    "primary_records": stats["primary_records"],
                    "secondary_records": stats["secondary_records"],
                    "gemini_records": stats["gemini_records"],
                    "last_successful_provider": last_provider,
                    "message": stats["message"],
                    "schedule": "08:00 Asia/Kolkata daily",
                }
            },
        )
        return stats

    async def status(self) -> Dict[str, Any]:
        """
        Read-only administrative monitoring status for the Admin Dashboard.
        Returns comprehensive health, usage, and provider telemetry without exposing secrets.
        """
        runs = self.db["market_daily_runs"] if self.db is not None else None
        attempted = None
        successful = None
        if runs is not None:
            attempted = await runs.find_one({"_id": {"$regex": "^batch:"}}, sort=[("started_at", -1)])
            successful = await runs.find_one(
                {"status": {"$in": ["completed", "fallback_completed"]}},
                sort=[("finished_at", -1)],
            )

        now_kolkata = datetime.now(KOLKATA_TZ)
        today_str = now_kolkata.date().isoformat()

        # Calculate next scheduled update: today at 08:00 AM if not passed, else tomorrow at 08:00 AM
        if now_kolkata.hour < 8:
            next_update_dt = now_kolkata.replace(hour=8, minute=0, second=0, microsecond=0)
        else:
            next_update_dt = (now_kolkata + timedelta(days=1)).replace(hour=8, minute=0, second=0, microsecond=0)
        next_update_str = f"{next_update_dt.strftime('%Y-%m-%d %H:%M:%S')} Asia/Kolkata"

        # Provider usages
        agmarknet_usage = await self.agmarknet.get_api_usage_today()
        gemini_usage = await self.gemini.get_api_usage_today(self.db)

        # Provider health statuses
        ag_exhausted = agmarknet_usage.get("is_exhausted", False)
        primary_status = "budget_exhausted" if ag_exhausted else ("active" if agmarknet_usage.get("request_count", 0) > 0 else "standby")

        gem_exhausted = gemini_usage.get("is_exhausted", False)
        gemini_status = (
            "missing_key" if not settings.GEMINI_API_KEY.strip()
            else ("quota_exhausted" if gem_exhausted else ("active" if gemini_usage.get("request_count", 0) > 0 else "ready"))
        )

        secondary_status = "active"

        # Distinct commodities in DB
        commodities_count = 0
        fresh_count = 0
        stale_count = 0
        fallback_count = 0
        latest_source_date = None

        if self.db is not None:
            try:
                distinct_commodities = await self.db["market_prices"].distinct("commodity")
                commodities_count = len(distinct_commodities)
                latest_doc = await self.db["market_prices"].find_one(
                    {"verification_status": "verified"},
                    sort=[("arrival_date", -1)],
                )
                if latest_doc:
                    latest_source_date = latest_doc.get("arrival_date")

                fresh_count = await self.db["market_prices"].count_documents(
                    {"arrival_date": today_str, "verification_status": "verified"}
                )
                stale_count = await self.db["market_prices"].count_documents(
                    {"arrival_date": {"$ne": today_str}, "verification_status": "verified"}
                )
                fallback_count = await self.db["market_prices"].count_documents(
                    {"source_provider": {"$ne": "AGMARKNET"}}
                )
            except Exception:
                pass

        commodities_updated = successful.get("commodities_updated", commodities_count) if successful else 0
        commodities_failed = max(0, commodities_count - commodities_updated)

        last_successful_provider = (
            successful.get("last_successful_provider") or "AGMARKNET (data.gov.in)"
            if successful
            else "None"
        )

        return {
            "status": "ready",
            "daily_update_schedule": "08:00 Asia/Kolkata daily",
            "next_scheduled_update": next_update_str,
            "last_attempted_update": attempted.get("started_at").isoformat() if attempted and attempted.get("started_at") else None,
            "last_successful_update": successful.get("successful_at").isoformat() if successful and successful.get("successful_at") else None,
            "last_successful_provider": last_successful_provider,
            "primary_provider": "Government AGMARKNET (data.gov.in)",
            "primary_provider_status": primary_status,
            "secondary_provider": "Tamil Nadu Uzhavar Santhai",
            "secondary_provider_status": secondary_status,
            "gemini_provider": "Gemini Grounded Search",
            "gemini_provider_status": gemini_status,
            "api_requests_today": agmarknet_usage.get("request_count", 0),
            "api_requests_remaining": agmarknet_usage.get("remaining", settings.MAX_DAILY_API_REQUESTS),
            "remaining_daily_budget": agmarknet_usage.get("remaining", settings.MAX_DAILY_API_REQUESTS),
            "gemini_requests_today": gemini_usage.get("request_count", 0),
            "commodities_tracked": commodities_count,
            "commodities_updated": commodities_updated,
            "commodities_failed": commodities_failed,
            "fresh_prices_count": fresh_count,
            "stale_prices_count": stale_count,
            "fallback_prices_count": fallback_count,
            "latest_source_date": latest_source_date or today_str,
            "is_fresh": latest_source_date == today_str,
        }

