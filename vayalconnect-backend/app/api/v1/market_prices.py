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

    # Step 1: Try live fetch from data.gov.in
    live_result = await market_price_provider.search_prices(
        commodity=commodity,
        state=state,
        district=district,
        market=market,
        limit=limit,
        offset=offset,
    )

    records = live_result.get("records", [])

    if live_result.get("live") and records:
        # Cache live records asynchronously to MongoDB for resilience
        try:
            await pricing_repo.store_market_prices_bulk(records)
        except Exception as e:
            logger.warning(f"Could not cache market prices: {e}")

        items = [MarketPriceItem(**r) for r in records]
        response_data = MarketPriceListResponse(
            records=items,
            count=len(items),
            live=True,
            source="data.gov.in AGMARKNET",
            message="Live government mandi rates retrieved successfully.",
        )
        return APIResponse(
            success=True,
            data=response_data.model_dump(),
            request_id=get_request_id(request),
        )

    # Step 2: Fallback to cached records if live API failed or is not reachable
    cached_docs = await pricing_repo.list_market_prices(
        commodity=commodity,
        state=state,
        district=district,
        market=market,
        limit=limit,
        offset=offset,
    )

    if cached_docs:
        cached_items = []
        for doc in cached_docs:
            try:
                # Ensure fields are present
                item_dict = {
                    "price_id": doc.get("price_id") or doc.get("id"),
                    "commodity": doc.get("commodity", ""),
                    "market": doc.get("market", ""),
                    "state": doc.get("state", ""),
                    "district": doc.get("district", ""),
                    "variety": doc.get("variety", "Common"),
                    "grade": doc.get("grade", "FAQ"),
                    "min_price_paise": doc.get("min_price_paise", 0),
                    "max_price_paise": doc.get("max_price_paise", 0),
                    "modal_price_paise": doc.get("modal_price_paise", 0),
                    "min_price_display": doc.get("min_price_display", "₹0.00"),
                    "max_price_display": doc.get("max_price_display", "₹0.00"),
                    "modal_price_display": doc.get("modal_price_display", "₹0.00"),
                    "price_per_kg_paise": doc.get("price_per_kg_paise", 0),
                    "price_per_kg_display": doc.get("price_per_kg_display", "₹0.00 / kg"),
                    "unit": doc.get("unit", "Quintal"),
                    "arrival_date": doc.get("arrival_date"),
                    "source": "data.gov.in AGMARKNET (Cached)",
                    "retrieved_at": doc.get("retrieved_at"),
                }
                cached_items.append(MarketPriceItem(**item_dict))
            except Exception as e:
                logger.warning(f"Error parsing cached market price record: {e}")

        upstream_reason = live_result.get("message") or "Upstream service unreachable"
        response_data = MarketPriceListResponse(
            records=cached_items,
            count=len(cached_items),
            live=False,
            source="data.gov.in AGMARKNET (Cached)",
            message=f"Live government API unavailable ({upstream_reason}). Displaying cached mandi prices.",
        )
        return APIResponse(
            success=True,
            data=response_data.model_dump(),
            request_id=get_request_id(request),
        )

    # Step 3: Neither live nor cached records available
    msg = live_result.get("message") or "No market price data available for the specified criteria."
    response_data = MarketPriceListResponse(
        records=[],
        count=0,
        live=False,
        source="data.gov.in AGMARKNET",
        message=msg,
    )
    return APIResponse(
        success=True,
        data=response_data.model_dump(),
        request_id=get_request_id(request),
    )


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
    pricing_repo = PricingRepository(db)

    # Try live fetch
    price_record = await market_price_provider.get_market_price(
        commodity=commodity,
        market=market,
        state=state,
        district=district,
    )

    if price_record:
        # Cache to db
        try:
            await pricing_repo.store_market_price(price_record)
        except Exception as e:
            logger.warning(f"Could not cache market price: {e}")

        item = MarketPriceItem(**price_record)
        return APIResponse(
            success=True,
            data=item.model_dump(),
            request_id=get_request_id(request),
        )

    # Fallback to database
    cached = await pricing_repo.get_latest_market_price(
        commodity=commodity,
        market=market,
        state=state,
        district=district,
    )

    if cached:
        cached["source"] = "data.gov.in AGMARKNET (Cached)"
        item = MarketPriceItem(
            price_id=cached.get("price_id") or cached.get("id"),
            commodity=cached.get("commodity", commodity),
            market=cached.get("market", market or "Unknown"),
            state=cached.get("state", state or "Tamil Nadu"),
            district=cached.get("district", district or "Unknown"),
            variety=cached.get("variety", "Common"),
            grade=cached.get("grade", "FAQ"),
            min_price_paise=cached.get("min_price_paise", 0),
            max_price_paise=cached.get("max_price_paise", 0),
            modal_price_paise=cached.get("modal_price_paise", 0),
            min_price_display=cached.get("min_price_display", "₹0.00"),
            max_price_display=cached.get("max_price_display", "₹0.00"),
            modal_price_display=cached.get("modal_price_display", "₹0.00"),
            price_per_kg_paise=cached.get("price_per_kg_paise", 0),
            price_per_kg_display=cached.get("price_per_kg_display", "₹0.00 / kg"),
            unit=cached.get("unit", "Quintal"),
            arrival_date=cached.get("arrival_date"),
            source="data.gov.in AGMARKNET (Cached)",
            retrieved_at=cached.get("retrieved_at"),
        )
        return APIResponse(
            success=True,
            data=item.model_dump(),
            request_id=get_request_id(request),
        )

    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail=f"Market price unavailable for '{commodity}'. Neither live nor cached data could be found.",
    )


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
