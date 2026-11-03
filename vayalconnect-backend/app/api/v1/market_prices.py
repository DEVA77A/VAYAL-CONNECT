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
from app.services.market_orchestrator import MarketPriceOrchestrator
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
        outcome = await MarketPriceOrchestrator(db).refresh_daily(force=force)
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
        outcome = await MarketPriceOrchestrator(db).refresh_daily(force=force)
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
        data=await MarketPriceOrchestrator(db).status(),
        request_id=get_request_id(request),
    )


# Common commodities & Tamil Nadu districts for client convenience

BILINGUAL_CROPS = {
    "tomato": "Tomato", "thakkali": "Tomato", "\u0ba4\u0b95\u0bcd\u0b95\u0bbe\u0bb3\u0bbf": "Tomato",
    "onion": "Onion", "vengayam": "Onion", "\u0bb5\u0bc6\u0b99\u0bcd\u0b95\u0bbe\u0baf\u0bae\u0bcd": "Onion",
    "potato": "Potato", "urulaikizhangu": "Potato", "\u0b89\u0bb0\u0bc1\u0bb3\u0bc8\u0b95\u0bcd\u0b95\u0bbf\u0bb4\u0b99\u0bcd\u0b95\u0bc1": "Potato",
    "paddy": "Paddy", "nel": "Paddy", "\u0ba8\u0bc6\u0bb2\u0bcd": "Paddy",
    "rice": "Rice", "arisi": "Rice", "\u0b85\u0bb0\u0bbf\u0b9a\u0bbf": "Rice",
    "banana": "Banana (fruit)", "valapazham": "Banana (fruit)", "\u0bb5\u0bbe\u0bb4\u0bc8\u0baa\u0bcd\u0baa\u0bb4\u0bae\u0bcd": "Banana (fruit)",
    "brinjal": "Brinjal", "kathirikai": "Brinjal", "\u0b95\u0ba4\u0bcd\u0ba4\u0bb0\u0bbf\u0b95\u0bcd\u0b95\u0bbe\u0baf\u0bcd": "Brinjal",
    "carrot": "Carrot", "\u0b95\u0bc7\u0bb0\u0b9f\u0bcd": "Carrot",
    "chilli": "Chilli", "milagai": "Chilli", "\u0bae\u0bbf\u0bb3\u0b95\u0bbe\u0baf\u0bcd": "Chilli",
    "coconut": "Coconut", "thengai": "Coconut", "\u0ba4\u0bc7\u0b99\u0bcd\u0b95\u0bbe\u0baf\u0bcd": "Coconut",
    "garlic": "Garlic", "poondu": "Garlic", "\u0baa\u0bc2\u0ba3\u0bcd\u0b9f\u0bc1": "Garlic",
    "ginger": "Ginger", "inji": "Ginger", "\u0b87\u0b9a\u0bbf": "Ginger",
    "cabbage": "Cabbage", "\u0bae\u0bc1\u0b9f\u0bcd\u0b9f\u0bc8\u0b95\u0bcd\u0b95\u0bcb\u0bb8\u0bcd": "Cabbage",
    "drumstick": "Drumstick", "\u0bae\u0bc1\u0bb0\u0bc1\u0b99\u0bcd\u0b95\u0bc8\u0b95\u0bcd\u0b95\u0bbe\u0baf\u0bcd": "Drumstick",
    "jasmine": "Jasmine", "\u0bae\u0bb2\u0bcd\u0bb2\u0bbf\u0b95\u0bc8": "Jasmine",
    "marigold": "Marigold", "\u0b9a\u0bbe\u0bae\u0ba8\u0bcd\u0ba4\u0bbf": "Marigold",
}

DEFAULT_CROPS = [
    "Tomato", "Onion", "Potato", "Paddy", "Rice", "Carrot", "Brinjal",
    "Banana (fruit)", "Chilli", "Coconut", "Garlic", "Ginger", "Cabbage",
    "Drumstick", "Jasmine", "Marigold",
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



@router.get("/search", response_model=APIResponse)
async def search_market_prices(
    request: Request,
    query: str = Query(..., min_length=1, max_length=200, description="Crop name in English or Tamil"),
    state: Optional[str] = Query("Tamil Nadu", max_length=100),
    district: Optional[str] = Query(None, max_length=100),
    market: Optional[str] = Query(None, max_length=100),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """
    Unified market price search across all roles (Admin, Farmer, Buyer).
    Translates bilingual query, ensures today's verified price via orchestrator,
    and returns standardized price per KG.
    """
    q_clean = query.strip()
    canonical = BILINGUAL_CROPS.get(q_clean.lower(), q_clean)

    # 1. On-demand discovery through orchestrator if today's price not in cache
    orchestrator = MarketPriceOrchestrator(db)
    try:
        await orchestrator.get_market_price(
            commodity=canonical,
            state=state or "Tamil Nadu",
            district=district,
            market=market,
            unit="KG",
        )
    except Exception as e:
        logger.info("Search on-demand discovery completed or bypassed: %s", e)

    # 2. Query verified records from repository
    repo = PricingRepository(db)
    records = await repo.list_market_prices(
        commodity=canonical,
        state=state,
        district=district,
        market=market,
        limit=50,
    )
    if not records and canonical != q_clean:
        records = await repo.list_market_prices(
            commodity=q_clean,
            state=state,
            district=district,
            market=market,
            limit=50,
        )

    # Autocomplete suggestions
    suggestions = [c for c in DEFAULT_CROPS if q_clean.lower() in c.lower()]

    if not records:
        return APIResponse(
            success=True,
            data={
                "found": False,
                "query": q_clean,
                "commodity": canonical,
                "message": "No verified price is available for this crop and selection. Enter your own selling price.",
                "records": [],
                "suggestions": suggestions,
            },
            request_id=get_request_id(request),
        )

    # Find the best record (highest arrival_date / retrieved_at)
    best_record = records[0]
    for r in records:
        if str(r.get("arrival_date", "")) > str(best_record.get("arrival_date", "")):
            best_record = r

    from datetime import datetime, timezone, timedelta
    now_ist = datetime.now(timezone(timedelta(hours=5, minutes=30))).date().isoformat()
    is_fresh = (str(best_record.get("arrival_date", ""))[:10] == now_ist) and not best_record.get("stale", False)

    return APIResponse(
        success=True,
        data={
            "found": True,
            "query": q_clean,
            "commodity": best_record.get("commodity", canonical),
            "best_price": {
                **best_record,
                "freshness_status": "fresh" if is_fresh else "cached",
                "is_fresh": is_fresh,
                "is_stale": not is_fresh,
            },
            "records": [
                {
                    **r,
                    "freshness_status": "fresh" if (str(r.get("arrival_date", ""))[:10] == now_ist and not r.get("stale", False)) else "cached",
                }
                for r in records
            ],
            "count": len(records),
            "suggestions": suggestions,
        },
        request_id=get_request_id(request),
    )

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
    if commodity:
        try:
            canonical_c = BILINGUAL_CROPS.get(commodity.strip().lower(), commodity.strip())
            await MarketPriceOrchestrator(db).get_market_price(commodity=canonical_c, state=state or "Tamil Nadu", district=district, market=market)
        except Exception:
            pass
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
    for c in DEFAULT_CROPS:
        commodities.add(c)
    async for mp in db["market_prices"].find({}, {"commodity": 1, "district": 1}).limit(200):
        if mp.get("commodity"):
            commodities.add(str(mp["commodity"]).strip())
        if mp.get("district"):
            districts.add(str(mp["district"]).strip())

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
