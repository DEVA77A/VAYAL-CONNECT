"""
VayalConnect Backend — Market Prices Router

Provides official Government AGMARKNET market prices from data.gov.in.
Supports live querying, caching, resilient fallback, and filtering by
state, district, market, and commodity.
"""

from typing import Optional, List
from fastapi import APIRouter, Depends, Query, Request, HTTPException, status
from motor.motor_asyncio import AsyncIOMotorDatabase
import logging

from app.core.database import get_database
from app.api.deps import get_request_id
from app.repositories.pricing import PricingRepository
from app.services.pricing_service import PricingEngine
from app.integrations.government_market import market_price_provider
from app.schemas.market_price import (
    MarketPriceItem,
    MarketPriceListResponse,
)
from app.schemas.common import APIResponse

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/market-prices", tags=["Market Prices"])

# Common commodities & Tamil Nadu districts for client convenience
DEFAULT_COMMODITIES = [
    "Paddy",
    "Wheat",
    "Rice",
    "Tomato",
    "Onion",
    "Potato",
    "Brinjal",
    "Banana",
    "Coconut",
    "Cotton",
    "Turmeric",
    "Maize",
    "Sugarcane",
    "Groundnut",
    "Chilli",
    "Black Gram",
    "Green Gram",
]

DEFAULT_DISTRICTS = [
    "Madurai",
    "Coimbatore",
    "Salem",
    "Tiruchirappalli",
    "Dindigul",
    "Thanjavur",
    "Erode",
    "Tirunelveli",
    "Vellore",
    "Theni",
    "Virudhunagar",
    "Tirupur",
    "Karur",
    "Namakkal",
    "Cuddalore",
]


@router.get("", response_model=APIResponse)
@router.get("/", response_model=APIResponse, include_in_schema=False)
async def list_market_prices(
    request: Request,
    commodity: Optional[str] = Query(None, description="Commodity name, e.g. Paddy, Tomato, Onion"),
    state: Optional[str] = Query(None, description="State name, e.g. Tamil Nadu"),
    district: Optional[str] = Query(None, description="District name, e.g. Madurai"),
    market: Optional[str] = Query(None, description="Market name, e.g. Madurai"),
    limit: int = Query(20, ge=1, le=100, description="Number of records to retrieve"),
    offset: int = Query(0, ge=0, description="Offset for pagination"),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """
    Retrieve real mandi market prices.
    Attempts live lookup from data.gov.in AGMARKNET. If live API is unreachable,
    falls back gracefully to recent cached mandi prices stored in the database.
    """
    pricing_repo = PricingRepository(db)

    live_result = await market_price_provider.search_prices(
        commodity=commodity, state=state, district=district, market=market, limit=limit, offset=offset)
    def valid(r):
        return market_price_provider.matches(r, commodity, market, state, district)
    records = [r for r in live_result.get("records", []) if valid(r)]
    live = bool(live_result.get("live"))
    source = "data.gov.in AGMARKNET"
    message = live_result.get("message") or "Official market source unavailable."
    if live:
        if records:
            try:
                await pricing_repo.store_market_prices_bulk(records)
            except Exception as exc:
                logger.warning("Market cache write failed category=%s", type(exc).__name__)
    else:
        from datetime import datetime, timezone, timedelta
        cached = await pricing_repo.list_market_prices(commodity=commodity, state=state,
                    district=district, market=market, limit=limit, offset=offset)
        cutoff = datetime.now(timezone.utc) - timedelta(days=7)
        records = []
        for record in cached:
            try:
                retrieved = record.get("retrieved_at")
                if isinstance(retrieved, str):
                    retrieved = datetime.fromisoformat(retrieved.replace("Z", "+00:00"))
                if retrieved.tzinfo is None:
                    retrieved = retrieved.replace(tzinfo=timezone.utc)
                if valid(record) and cutoff <= retrieved <= datetime.now(timezone.utc):
                    records.append({**record, "stale": True})
            except (AttributeError, ValueError, TypeError):
                continue
        if records:
            source += " (Cached)"
            message = "Live source unavailable. Historical cached records (maximum cache age 7 days). " + message
        else:
            from fastapi.responses import JSONResponse
            return JSONResponse(status_code=503, content={"success": False, "data": {
                "records": [], "count": 0, "live": False, "source": source, "message": message},
                "error": {"code": "MARKET_SOURCE_UNAVAILABLE", "message": message},
                "request_id": get_request_id(request)})
    items = [MarketPriceItem(**r) for r in records]
    return APIResponse(success=True, data=MarketPriceListResponse(records=items, count=len(items),
        live=live, source=source, message=message).model_dump(), request_id=get_request_id(request))


@router.get("/latest", response_model=APIResponse)
async def get_latest_market_price(
    request: Request,
    commodity: str = Query(..., description="Commodity name"),
    market: Optional[str] = Query(None, description="Market name"),
    state: Optional[str] = Query(None, description="State name"),
    district: Optional[str] = Query(None, description="District name"),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """
    Get the single latest market price for a commodity.
    """
    result = await list_market_prices(request, commodity, state, district, market, 100, 0, db)
    if not isinstance(result, APIResponse):
        return result
    records = result.data["records"]
    if not records:
        raise HTTPException(status_code=404, detail="No matching official market price found.")
    item = max(records, key=lambda r: str(r.get("arrival_date", "")))
    if not result.data["live"]:
        item["source"] = result.data["source"]
    return APIResponse(success=True, data=item, request_id=get_request_id(request))


@router.get("/filter-options", response_model=APIResponse)
async def get_filter_options(request: Request):
    """
    Get recommended commodities and districts for filtering in client applications.
    """
    return APIResponse(
        success=True,
        data={
            "commodities": DEFAULT_COMMODITIES,
            "districts": DEFAULT_DISTRICTS,
            "default_state": "Tamil Nadu",
        },
        request_id=get_request_id(request),
    )
