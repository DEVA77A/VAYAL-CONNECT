"""
VayalConnect Backend — AGMARKNET / data.gov.in Direct Integration Client

Provides resilient, rate-limited, and validated market price fetching
directly from Government of India AGMARKNET via api.data.gov.in.

Strict Rules:
1. All requests respect MAX_DAILY_API_REQUESTS budget tracked in MongoDB.
2. Exponential backoff with jitter on transient failures.
3. Respect HTTP 429 Retry-After headers.
4. Never retry permanent client errors (401, 403, 404).
5. AGMARKNET modal prices default to "Quintal" when unit column is omitted.
6. Integer paise throughout for all financial calculations.
"""

import asyncio
import logging
import random
from datetime import datetime, timezone, timedelta
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from typing import Dict, Any, List, Optional, Tuple

import httpx
from pymongo import ReturnDocument
from pymongo.errors import PyMongoError

from app.core.config import settings

logger = logging.getLogger(__name__)

# Fallback-safe Asia/Kolkata timezone
try:
    from zoneinfo import ZoneInfo
    KOLKATA_TZ = ZoneInfo("Asia/Kolkata")
except Exception:
    KOLKATA_TZ = timezone(timedelta(hours=5, minutes=30))


class RateLimitBudgetExceededError(Exception):
    """Raised when the configured daily API request budget is exhausted."""
    pass


class RateLimit429Error(Exception):
    """Raised when external API responds with HTTP 429 Too Many Requests."""
    def __init__(self, message: str, retry_after: Optional[int] = None):
        super().__init__(message)
        self.retry_after = retry_after


class AgmarknetClientError(Exception):
    """Base error for AGMARKNET client issues."""
    pass


def get_today_kolkata_str() -> str:
    """Returns today's date formatted as YYYY-MM-DD in Asia/Kolkata timezone."""
    return datetime.now(KOLKATA_TZ).date().isoformat()


class AgmarknetClient:
    """
    Direct client for fetching agricultural market prices from data.gov.in.
    Manages rate limits, retries, unit normalization, and response validation.
    """

    def __init__(self, db=None, http_client: Optional[httpx.AsyncClient] = None):
        self.db = db
        self._custom_client = http_client

    async def get_api_usage_today(self) -> Dict[str, Any]:
        """Retrieve today's persistent API usage count from MongoDB."""
        if self.db is None:
            return {"request_count": 0, "remaining": settings.MAX_DAILY_API_REQUESTS}
        today_str = get_today_kolkata_str()
        try:
            doc = await self.db["market_api_usage"].find_one({"_id": f"usage:{today_str}"})
            count = doc.get("request_count", 0) if doc else 0
            remaining = max(0, settings.MAX_DAILY_API_REQUESTS - count)
            return {
                "request_count": count,
                "max_requests": settings.MAX_DAILY_API_REQUESTS,
                "remaining": remaining,
                "date": today_str,
            }
        except Exception as e:
            logger.warning("Failed to read market_api_usage: %s", e)
            return {"request_count": 0, "remaining": settings.MAX_DAILY_API_REQUESTS}

    async def _check_and_increment_budget(self) -> int:
        """Atomically checks and increments the persistent daily request budget in MongoDB."""
        if self.db is None:
            return 1
        today_str = get_today_kolkata_str()
        now_utc = datetime.now(timezone.utc)
        usage_col = self.db["market_api_usage"]

        # Pre-check if budget is already exhausted
        try:
            existing = await usage_col.find_one({"_id": f"usage:{today_str}"})
            if existing and isinstance(existing, dict) and existing.get("request_count", 0) >= settings.MAX_DAILY_API_REQUESTS:
                raise RateLimitBudgetExceededError(
                    f"Daily API request limit reached ({settings.MAX_DAILY_API_REQUESTS} requests)."
                )
        except RateLimitBudgetExceededError:
            raise
        except Exception:
            pass

        # Atomic increment
        doc = await usage_col.find_one_and_update(
            {"_id": f"usage:{today_str}"},
            {
                "$inc": {"request_count": 1},
                "$set": {
                    "last_request_at": now_utc,
                    "max_requests": settings.MAX_DAILY_API_REQUESTS,
                },
                "$setOnInsert": {
                    "created_at": now_utc,
                    "date": today_str,
                },
            },
            upsert=True,
            return_document=ReturnDocument.AFTER,
        )
        count = int(doc.get("request_count", 1)) if (doc and isinstance(doc, dict)) else 1
        if count > settings.MAX_DAILY_API_REQUESTS:
            logger.warning(
                "Daily market API request budget exceeded (%d / %d) for %s",
                count, settings.MAX_DAILY_API_REQUESTS, today_str
            )
            raise RateLimitBudgetExceededError(
                f"Daily API request limit reached ({settings.MAX_DAILY_API_REQUESTS} requests)."
            )
        return count

    async def fetch_prices(
        self,
        commodity: Optional[str] = None,
        district: Optional[str] = None,
        state: str = "Tamil Nadu",
        limit: int = 100,
        offset: int = 0,
    ) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        """
        Fetches agricultural mandi prices for Tamil Nadu from data.gov.in.
        Returns (parsed_records, metadata).
        """
        api_key = settings.active_market_api_key
        if not api_key:
            logger.warning("No API key configured for data.gov.in (DATA_GOV_IN_API_KEY).")
            return [], {"status": "error", "error_code": "API_KEY_MISSING", "message": "API key missing"}

        resource_id = settings.active_market_resource_id
        url = f"https://api.data.gov.in/resource/{resource_id}"

        params = {
            "api-key": api_key,
            "format": "json",
            "filters[state]": state,
            "limit": limit,
            "offset": offset,
        }
        if commodity:
            params["filters[commodity]"] = commodity
        if district:
            params["filters[district]"] = district

        headers = {
            "User-Agent": "VayalConnect/1.1 (Agricultural Marketplace Backend)",
            "Accept": "application/json",
        }

        attempts = 0
        max_attempts = settings.MAX_RETRY_ATTEMPTS
        base_timeout = settings.API_TIMEOUT_SECONDS

        while attempts < max_attempts:
            attempts += 1
            # Check and record daily budget
            await self._check_and_increment_budget()

            try:
                if self._custom_client:
                    response = await self._custom_client.get(url, params=params, headers=headers)
                else:
                    async with httpx.AsyncClient(timeout=base_timeout, follow_redirects=False) as client:
                        response = await client.get(url, params=params, headers=headers)

                status_code = response.status_code

                if status_code == 200:
                    data = response.json()
                    records = data.get("records", [])
                    total = data.get("total", len(records))
                    parsed = self._parse_records(records, resource_id)
                    return parsed, {
                        "status": "success",
                        "total": total,
                        "returned": len(parsed),
                        "offset": offset,
                        "limit": limit,
                        "attempts": attempts,
                    }

                elif status_code == 429:
                    retry_after_hdr = response.headers.get("Retry-After")
                    retry_seconds = 5
                    if retry_after_hdr and retry_after_hdr.isdigit():
                        retry_seconds = int(retry_after_hdr)
                    logger.warning("data.gov.in returned HTTP 429 Too Many Requests. Retry-After: %s", retry_after_hdr)
                    if attempts < max_attempts and retry_seconds <= 10:
                        await asyncio.sleep(retry_seconds)
                        continue
                    raise RateLimit429Error("data.gov.in rate limit exceeded (HTTP 429).", retry_after=retry_seconds)

                elif status_code in (401, 403):
                    logger.error("data.gov.in authentication rejected (HTTP %d). Invalid API key.", status_code)
                    return [], {
                        "status": "error",
                        "error_code": "INVALID_API_KEY",
                        "message": f"API key rejected with HTTP {status_code}.",
                        "status_code": status_code,
                    }

                elif status_code == 404:
                    logger.error("data.gov.in resource not found (HTTP 404) for resource %s", resource_id)
                    return [], {
                        "status": "error",
                        "error_code": "RESOURCE_NOT_FOUND",
                        "message": "AGMARKNET resource ID not found.",
                        "status_code": 404,
                    }

                else:
                    # Server error (500, 502, 503, 504)
                    logger.warning("data.gov.in returned HTTP %d on attempt %d", status_code, attempts)
                    if attempts < max_attempts:
                        backoff = (2 ** attempts) + random.uniform(0.1, 0.5)
                        await asyncio.sleep(backoff)
                        continue
                    return [], {
                        "status": "error",
                        "error_code": f"HTTP_{status_code}",
                        "message": f"Server error HTTP {status_code}",
                        "status_code": status_code,
                    }

            except httpx.TimeoutException:
                logger.warning("Timeout connecting to data.gov.in on attempt %d", attempts)
                if attempts < max_attempts:
                    backoff = (2 ** attempts) + random.uniform(0.1, 0.5)
                    await asyncio.sleep(backoff)
                    continue
                return [], {"status": "error", "error_code": "TIMEOUT", "message": "Request timed out"}

            except RateLimitBudgetExceededError:
                raise
            except RateLimit429Error:
                raise
            except Exception as e:
                logger.warning("Request to data.gov.in failed on attempt %d: %s", attempts, e)
                if attempts < max_attempts:
                    backoff = (2 ** attempts) + random.uniform(0.1, 0.5)
                    await asyncio.sleep(backoff)
                    continue
                return [], {"status": "error", "error_code": "CONNECTION_ERROR", "message": str(e)}

        return [], {"status": "error", "error_code": "MAX_RETRIES_EXCEEDED", "message": "Retries exhausted"}

    def _parse_records(self, raw_rows: List[Dict[str, Any]], resource_id: str) -> List[Dict[str, Any]]:
        """Parses and validates raw AGMARKNET rows into normalized VayalConnect market records."""
        parsed = []
        today_kolkata = get_today_kolkata_str()
        now_utc = datetime.now(timezone.utc)

        for row in raw_rows:
            try:
                commodity = str(row.get("commodity", "")).strip()
                market = str(row.get("market", "")).strip()
                district = str(row.get("district", "")).strip()
                state = str(row.get("state", "Tamil Nadu")).strip()
                variety = str(row.get("variety", "")).strip() or None
                grade = str(row.get("grade", "FAQ")).strip()

                if not commodity or not market:
                    continue

                # Parse arrival date: AGMARKNET format is DD/MM/YYYY
                arr_raw = str(row.get("arrival_date", "")).strip()
                try:
                    dt = datetime.strptime(arr_raw, "%d/%m/%Y").date()
                    arrival_iso = dt.isoformat()
                except (ValueError, TypeError):
                    arrival_iso = today_kolkata

                # Parse modal price
                modal_val = row.get("modal_price")
                if modal_val is None or modal_val == "":
                    continue
                modal_num = Decimal(str(modal_val))
                if modal_num <= 0:
                    continue

                modal_paise = int((modal_num * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))

                # Parse min and max prices
                min_paise = None
                max_paise = None
                if row.get("min_price") is not None and str(row.get("min_price")).strip() != "":
                    try:
                        min_paise = int((Decimal(str(row["min_price"])) * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
                    except Exception:
                        min_paise = modal_paise

                if row.get("max_price") is not None and str(row.get("max_price")).strip() != "":
                    try:
                        max_paise = int((Decimal(str(row["max_price"])) * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
                    except Exception:
                        max_paise = modal_paise

                # Unit: Official AGMARKNET wholesale standard is Quintal (100 KG) when omitted.
                raw_unit = row.get("unit")
                unit = "Quintal"
                if raw_unit and str(raw_unit).strip() and str(raw_unit).strip().lower() not in ("none", "null"):
                    unit = str(raw_unit).strip()

                is_stale = (arrival_iso != today_kolkata)

                record = {
                    "commodity": commodity,
                    "market": market,
                    "district": district,
                    "state": state,
                    "variety": variety,
                    "grade": grade,
                    "unit": unit,
                    "currency": "INR",
                    "price_paise": modal_paise,
                    "modal_price_paise": modal_paise,
                    "min_price_paise": min_paise,
                    "max_price_paise": max_paise,
                    "price_display": f"₹{modal_paise / 100:,.2f}",
                    "arrival_date": arrival_iso,
                    "observation_date": arrival_iso,
                    "source": "data.gov.in AGMARKNET",
                    "source_url": f"https://api.data.gov.in/resource/{resource_id}",
                    "source_record_id": f"{commodity}:{market}:{arrival_iso}",
                    "verification_status": "verified",
                    "verification_method": "primary_source_api",
                    "stale": is_stale,
                    "freshness_status": "stale" if is_stale else "fresh",
                    "retrieved_at": now_utc.isoformat(),
                    "updated_at": now_utc,
                }
                parsed.append(record)

            except (ValueError, TypeError, InvalidOperation) as e:
                logger.debug("Skipping invalid AGMARKNET row: %s (%s)", row, e)
                continue

        return parsed
