"""
VayalConnect Backend — Market Prices Router

Provides validated, source-reported market prices from the daily cache.
Serves the daily verified cache, registers future contexts, and filters by
state, district, market, and commodity.
"""

from typing import Optional, List
from fastapi import APIRouter, Depends, Query, Request, HTTPException, status
from motor.motor_asyncio import AsyncIOMotorDatabase
import logging

from app.core.database import get_database
from app.api.deps import get_request_id, get_current_admin
from app.repositories.pricing import PricingRepository
from app.services.pricing_service import PricingEngine
from app.integrations.groq_market import market_price_provider
from app.services.market_discovery import MarketDiscoveryService
from app.schemas.market_price import (
    MarketPriceItem,
    MarketPriceListResponse,
)
from app.schemas.common import APIResponse

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/market-prices", tags=["Market Prices"])


@router.post("/refresh", response_model=APIResponse)
async def manual_refresh(
    request: Request,
    force: bool = Query(True, description="Force refresh when admin explicitly requests"),
    db: AsyncIOMotorDatabase = Depends(get_database),
    admin: dict = Depends(get_current_admin),
):
    """Manual administrative refresh with distributed locking."""
    from pymongo.errors import PyMongoError

    try:
        outcome = await MarketDiscoveryService(db).refresh_daily(force=force)
    except PyMongoError:
        raise HTTPException(
            status_code=503, detail="Market cache unavailable; no retry."
        ) from None
    return APIResponse(
        success=not bool(outcome.get("failed") or outcome.get("unavailable")),
        data=outcome,
        request_id=get_request_id(request),
    )


@router.post("/cron-daily-update", response_model=APIResponse)
async def cron_daily_update(
    request: Request,
    force: bool = Query(False, description="Force refresh even if already completed today"),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """
    Render-compatible webhook or external cron trigger for 08:00 AM IST daily refresh.
    Protected by CRON_SECRET_TOKEN.
    """
    from app.core.config import settings
    from pymongo.errors import PyMongoError

    token = (
        request.headers.get("X-Cron-Secret")
        or request.query_params.get("token")
        or request.headers.get("Authorization", "").replace("Bearer ", "").strip()
    )
    if settings.CRON_SECRET_TOKEN and token != settings.CRON_SECRET_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized cron trigger. Valid X-Cron-Secret or token required.",
        )

    try:
        outcome = await MarketDiscoveryService(db).refresh_daily(force=force)
    except PyMongoError:
        raise HTTPException(
            status_code=503, detail="Market database unavailable."
        ) from None

    return APIResponse(
        success=not bool(outcome.get("failed")),
        data=outcome,
        request_id=get_request_id(request),
    )


@router.get("/status", response_model=APIResponse)
async def market_refresh_status(
    request: Request,
    db: AsyncIOMotorDatabase = Depends(get_database),
    admin: dict = Depends(get_current_admin),
):
    """Administrative cache/refresh status. This route never refreshes prices."""
    return APIResponse(
        success=True,
        data=await MarketDiscoveryService(db).status(),
        request_id=get_request_id(request),
    )


# Common commodities & Tamil Nadu districts for client convenience
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
    commodity: Optional[str] = Query(
        None,
        min_length=2,
        max_length=200,
        description="Commodity name, e.g. Paddy, Tomato, Onion",
    ),
    state: Optional[str] = Query(
        None, min_length=2, max_length=200, description="State name, e.g. Tamil Nadu"
    ),
    district: Optional[str] = Query(
        None, min_length=2, max_length=200, description="District name, e.g. Madurai"
    ),
    market: Optional[str] = Query(
        None, min_length=2, max_length=200, description="Market name, e.g. Madurai"
    ),
    limit: int = Query(20, ge=1, le=100, description="Number of records to retrieve"),
    offset: int = Query(0, ge=0, description="Offset for pagination"),
    db: AsyncIOMotorDatabase = Depends(get_database),
    category: Optional[str] = Query(None, max_length=100),
    variety: Optional[str] = Query(None, max_length=100),
    commodity_id: Optional[str] = Query(None, min_length=2, max_length=100),
    scope: str = Query("market", pattern="^(statewide|market)$"),
):
    """
    Read source-verified cached prices; this route never calls Gemini.
    """
    result = await MarketDiscoveryService(db).lookup(
        commodity=commodity,
        state=state,
        district=district,
        market=market,
        category=category,
        variety=variety,
        commodity_id=commodity_id,
        limit=limit,
        offset=offset,
        scope=scope,
    )
    if result.get("error_code") == "MARKET_CACHE_UNAVAILABLE":
        from fastapi.responses import JSONResponse

        return JSONResponse(
            status_code=503,
            content={
                "success": False,
                "data": result,
                "error": {"code": result["error_code"], "message": result["message"]},
                "request_id": get_request_id(request),
            },
        )
    items = [MarketPriceItem(**r) for r in result["records"]]
    return APIResponse(
        success=True,
        data=MarketPriceListResponse(
            records=items,
            count=len(items),
            live=result["live"],
            source=result["source"],
            message=result["message"],
        ).model_dump(mode="json"),
        request_id=get_request_id(request),
    )


@router.get("/latest", response_model=APIResponse)
async def get_latest_market_price(
    request: Request,
    commodity: str = Query(
        ..., min_length=2, max_length=200, description="Commodity name"
    ),
    market: Optional[str] = Query(
        None, min_length=2, max_length=200, description="Market name"
    ),
    state: Optional[str] = Query(
        None, min_length=2, max_length=200, description="State name"
    ),
    district: Optional[str] = Query(
        None, min_length=2, max_length=200, description="District name"
    ),
    db: AsyncIOMotorDatabase = Depends(get_database),
    scope: str = Query("market", pattern="^(statewide|market)$"),
):
    """
    Get the single latest market price for a commodity.
    """
    result = await list_market_prices(
        request, commodity, state, district, market, 100, 0, db, None, None, None, scope
    )
    if not isinstance(result, APIResponse):
        return result
    records = result.data["records"]
    if not records:
        raise HTTPException(
            status_code=404, detail="No matching verified market price found."
        )
    item = max(records, key=lambda r: str(r.get("arrival_date", "")))
    return APIResponse(success=True, data=item, request_id=get_request_id(request))


@router.get("/filter-options", response_model=APIResponse)
async def get_filter_options(
    request: Request, db: AsyncIOMotorDatabase = Depends(get_database)
):
    """
    Get recommended commodities and districts for filtering in client applications.
    """
    commodities, categories, districts = set(), set(), set()
    async for product in db["products"].find(
        {}, {"product_name": 1, "category": 1, "district": 1}
    ):
        for field, values in (
            ("product_name", commodities),
            ("category", categories),
            ("district", districts),
        ):
            value = product.get(field)
            if isinstance(value, str) and value.strip():
                values.add(value.strip())
    return APIResponse(
        success=True,
        data={
            "commodities": sorted(commodities),
            "categories": sorted(categories),
            "districts": sorted(districts) or DEFAULT_DISTRICTS,
            "default_state": "Tamil Nadu",
        },
        request_id=get_request_id(request),
    )
