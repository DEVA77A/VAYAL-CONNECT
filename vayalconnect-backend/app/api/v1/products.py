from app.core.transactions import transactional_endpoint, collection
"""
VayalConnect Backend — Products Router

Role-filtered product responses:
- Farmer: sees payout ONLY
- Buyer: sees price ONLY
- Admin: sees complete financial breakdown
"""

from fastapi import APIRouter, Depends, Request, Query
from motor.motor_asyncio import AsyncIOMotorDatabase

from app.core.database import get_database
from app.api.deps import get_current_user, get_current_farmer, get_approved_farmer, get_request_id
from app.repositories.products import ProductRepository
from app.repositories.users import UserRepository
from app.services.pricing_service import PricingEngine
from app.services.audit_service import AuditService
from app.schemas.product import (
    CreateProductRequest, UpdateProductRequest,
    FarmerProductResponse, BuyerProductResponse, AdminProductResponse,
)
from app.schemas.common import APIResponse
from app.core.exceptions import NotFoundError, ForbiddenError
from app.utils.money import format_rupees, percentage_bps_to_display

from app.repositories.farmers import FarmerRepository
from app.api.v1.media import validate_owned_image
from datetime import datetime, timezone, date, timedelta
from app.core.config import settings

def reference_view(product):
    fields = ("reference_price_available", "reference_price_message", "government_reference_price_paise", "reference_price_per_listing_unit_paise", "reference_price_unit", "reference_listing_unit", "reference_price_date", "reference_price_source", "reference_price_cached", "reference_price_stale", "reference_price_retrieved_at", "reference_commodity", "reference_market", "reference_min_paise", "reference_max_paise", "reference_state", "reference_source_url", "reference_records", "reference_price_type", "reference_verification_status", "reference_district", "reference_verification_method", "reference_quote_type", "reference_currency")
    if product.get("pricing_mode") != "FARMER_SELECTED": return None
    fields += ("reference_scope", "reference_label", "reference_aggregation_method", "reference_observation_count", "reference_observation_dates")
    result = {k: product.get(k) for k in fields}
    try:
        today = datetime.now(timezone(timedelta(hours=5, minutes=30))).date()
        result["reference_price_stale"] = bool(product.get("reference_price_stale")) or date.fromisoformat(str(product.get("reference_price_date"))[:10]) != today
        result["reference_records"] = [{**record, "stale": bool(record.get("stale")) or
            date.fromisoformat(str(record.get("arrival_date"))[:10]) != today}
            for record in (product.get("reference_records") or [])]
    except (TypeError, ValueError):
        result["reference_price_stale"] = True
    return result


router = APIRouter(prefix="/products", tags=["Products"])


@router.get("/price-reference", response_model=APIResponse)
async def price_reference(request: Request, commodity: str = Query(..., min_length=2, max_length=200),
                          market: str | None = Query(None, min_length=2, max_length=200),
                          unit: str = Query(..., pattern="^(KG|QUINTAL|TON|PIECE|DOZEN|BUNCH|BUNDLE|COUNT)$"),
                          state: str = Query("Tamil Nadu", min_length=2, max_length=100),
                          district: str | None = Query(None, min_length=2, max_length=100),
                          category: str | None = Query(None, max_length=100),
                          variety: str | None = Query(None, max_length=100),
                          current_user: dict = Depends(get_current_farmer),
                          db: AsyncIOMotorDatabase = Depends(get_database)):
    reference = await PricingEngine(db).get_verified_reference(commodity, market, unit, state=state, district=district, category=category, variety=variety)
    return APIResponse(success=True, data=reference, request_id=get_request_id(request))


@router.post("/", response_model=APIResponse, status_code=201)
@transactional_endpoint
async def create_product(
    data: CreateProductRequest,
    request: Request,
    current_user: dict = Depends(get_approved_farmer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """
    Farmer creates a product.
    Backend validates an official reference and adds commission to the selected payout.
    Response shows ONLY farmer payout — no buyer price, no commission.
    """
    await validate_owned_image(db, data.image_url, current_user["id"])
    pricing_engine = PricingEngine(db)
    product_repo = ProductRepository(db)
    audit = AuditService(db)

    # The reference is advisory; the farmer selects only their payout, never buyer totals.
    pricing = await pricing_engine.calculate_pricing(
        product_name=data.product_name,
        category=data.category,
        quantity=data.quantity,
        unit=data.quantity_unit.value,
        quality_grade=data.quality_grade.value,
        location=data.location,
        market=data.market,
        farmer_id=current_user["id"],
        selling_price_per_unit_paise=data.selling_price_per_unit_paise,
        state=data.state, district=data.district, variety=data.variety,
    )

    # Build product document
    product_doc = {
        "farmer_id": current_user["id"],
        "product_name": data.product_name,
        "description": data.description,
        "category": data.category,
        "state": data.state, "district": data.district, "variety": data.variety,
        "quantity_available": data.quantity,
        "quantity_unit": data.quantity_unit.value,
        "quality_grade": data.quality_grade.value,
        "image_url": data.image_url,
        "location": data.location,
        "market": data.market,
        "harvest_date": data.harvest_date,
        # Pricing from engine — NOT from client
        "government_reference_price_paise": pricing["government_reference_price_paise"],
        "reference_price_date": pricing.get("reference_price_date"),
        "reference_price_source": pricing.get("reference_price_source", ""),
        "farmer_payout_per_unit_paise": pricing["farmer_payout_per_unit_paise"],
        "buyer_price_per_unit_paise": pricing["buyer_price_per_unit_paise"],
        "commission_percentage": pricing["commission_percentage_bps"],
        "commission_per_unit_paise": pricing["commission_per_unit_paise"],
        "pricing_policy_id": pricing.get("pricing_policy_id"),
        "pricing_policy_version": pricing.get("pricing_policy_version", 0),
    }

    product_doc.update(reference_view({**pricing, "pricing_mode": "FARMER_SELECTED"}) or {})
    product_doc["pricing_mode"] = "FARMER_SELECTED"
    product_id = await product_repo.create(product_doc)

    # Create immutable pricing snapshot
    snapshot_id = await pricing_engine.create_snapshot(product_id, pricing)

    # Update product with snapshot reference
    await product_repo.update(product_id, {"pricing_snapshot_id": snapshot_id})

    await audit.log(
        actor_id=current_user["id"],
        actor_role="FARMER",
        action="PRODUCT_CREATED",
        entity_type="product",
        entity_id=product_id,
        details={"product_name": data.product_name, "quantity": data.quantity},
    )

    # FARMER-SAFE response — NO buyer price, NO commission, NO gov price
    return APIResponse(
        success=True,
        data=FarmerProductResponse(
            description=data.description,
            product_id=product_id,
            product_name=data.product_name,
            category=data.category,
            quantity_available=data.quantity,
            quantity_unit=data.quantity_unit.value,
            quality_grade=data.quality_grade.value,
            image_url=data.image_url,
            location=data.location,
            market=data.market,
            harvest_date=data.harvest_date,
            market_reference=reference_view({**pricing, "pricing_mode": "FARMER_SELECTED"}),
            farmer_payout_per_unit_paise=pricing["farmer_payout_per_unit_paise"],
            farmer_payout_per_unit_display=format_rupees(pricing["farmer_payout_per_unit_paise"]),
            status="ACTIVE",
        ).model_dump(),
        request_id=get_request_id(request),
    )


@router.get("/my", response_model=APIResponse)
async def list_my_products(
    request: Request,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    current_user: dict = Depends(get_current_farmer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """List farmer's own products."""
    product_repo = ProductRepository(db)
    products, total = await product_repo.list_by_farmer(current_user["id"], page, limit)

    items = [
        FarmerProductResponse(
            description=p.get("description", ""),
            product_id=p["id"],
            product_name=p.get("product_name", ""),
            category=p.get("category", ""),
            state=p.get("state"), district=p.get("district"), variety=p.get("variety"),
            quantity_available=p.get("quantity_available", 0),
            quantity_unit=p.get("quantity_unit", ""),
            quality_grade=p.get("quality_grade", ""),
            image_url=p.get("image_url"),
            location=p.get("location", ""),
            market=p.get("market", ""),
            harvest_date=p.get("harvest_date"),
            market_reference=reference_view(p),
            farmer_payout_per_unit_paise=p.get("farmer_payout_per_unit_paise", 0),
            farmer_payout_per_unit_display=format_rupees(p.get("farmer_payout_per_unit_paise", 0)),
            status=p.get("status", ""),
            created_at=p.get("created_at"),
            updated_at=p.get("updated_at"),
        ).model_dump()
        for p in products
    ]

    return APIResponse(
        success=True,
        data={"items": items, "total": total, "page": page, "limit": limit},
        request_id=get_request_id(request),
    )


@router.get("/", response_model=APIResponse)
async def list_products(
    request: Request,
    search: str = Query(None, max_length=200),
    sort: str = Query("newest", pattern="^(newest|price_asc|price_desc)$"),
    category: str = Query(None),
    location: str = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """List active products. Response filtered by role."""
    product_repo = ProductRepository(db)
    user_repo = UserRepository(db)
    role = current_user.get("role", "")

    if role == "ADMIN":
        products, total = await product_repo.list_all(page, limit)
    else:
        products, total = await product_repo.list_active(category, location, page, limit, search=search, sort=sort)

    items = []
    pricing_engine = PricingEngine(db)
    for p in products:
        if role == "BUYER":
            p = await pricing_engine.buyer_pricing(p)
            farm = await FarmerRepository(db).find_by_user_id(p.get("farmer_id", ""))
            application = (farm or {}).get("application") or {}
            farmer = await user_repo.find_by_id(p.get("farmer_id", ""))
            items.append(BuyerProductResponse(
                description=p.get("description", ""),
            product_id=p["id"],
                product_name=p.get("product_name", ""),
                category=p.get("category", ""),
                quantity_available=p.get("quantity_available", 0),
                quantity_unit=p.get("quantity_unit", ""),
                quality_grade=p.get("quality_grade", ""),
                image_url=p.get("image_url"),
                location=p.get("location", ""),
                farmer_name=farmer["name"] if farmer else None,
                pickup_address=application.get("pickup_address", p.get("location")),
                delivery_available=application.get("delivery_available", False),
                farmer_base_price_paise=p.get("farmer_payout_per_unit_paise", 0),
                commission_per_unit_paise=p.get("commission_per_unit_paise", 0),
                commission_percentage_bps=p.get("commission_percentage", 0),
                farm_coordinates=application.get("coordinates"), market_reference=reference_view(p),
                buyer_price_per_unit_paise=p.get("buyer_price_per_unit_paise", 0),
                buyer_price_per_unit_display=format_rupees(p.get("buyer_price_per_unit_paise", 0)),
                harvest_date=p.get("harvest_date"),
            ).model_dump())
        elif role == "ADMIN":
            farmer = await user_repo.find_by_id(p.get("farmer_id", ""))
            items.append(AdminProductResponse(
                description=p.get("description", ""),
            product_id=p["id"],
                product_name=p.get("product_name", ""),
                category=p.get("category", ""),
                farmer_id=p.get("farmer_id", ""),
                farmer_name=farmer["name"] if farmer else "",
                quantity_available=p.get("quantity_available", 0),
                quantity_unit=p.get("quantity_unit", ""),
                quality_grade=p.get("quality_grade", ""),
                image_url=p.get("image_url"),
                location=p.get("location", ""),
                market=p.get("market", ""),
                harvest_date=p.get("harvest_date"),
                government_reference_price_paise=p.get("government_reference_price_paise", 0),
                government_reference_price_display=format_rupees(p.get("government_reference_price_paise", 0)),
                reference_price_date=p.get("reference_price_date"),
                reference_price_source=p.get("reference_price_source"),
                farmer_payout_per_unit_paise=p.get("farmer_payout_per_unit_paise", 0),
                farmer_payout_per_unit_display=format_rupees(p.get("farmer_payout_per_unit_paise", 0)),
                buyer_price_per_unit_paise=p.get("buyer_price_per_unit_paise", 0),
                buyer_price_per_unit_display=format_rupees(p.get("buyer_price_per_unit_paise", 0)),
                commission_percentage_bps=p.get("commission_percentage", 0),
                commission_percentage_display=percentage_bps_to_display(p.get("commission_percentage", 0)),
                commission_per_unit_paise=p.get("commission_per_unit_paise", 0),
                commission_per_unit_display=format_rupees(p.get("commission_per_unit_paise", 0)),
                pricing_policy_id=p.get("pricing_policy_id"),
                pricing_policy_version=p.get("pricing_policy_version"),
                status=p.get("status", ""),
                created_at=p.get("created_at"),
                updated_at=p.get("updated_at"),
            ).model_dump())

    return APIResponse(
        success=True,
        data={"items": items, "total": total, "page": page, "limit": limit},
        request_id=get_request_id(request),
    )


@router.get("/{product_id}", response_model=APIResponse)
async def get_product(
    product_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Get product detail. Response filtered by role."""
    product_repo = ProductRepository(db)
    user_repo = UserRepository(db)

    product = (await product_repo.find_active_by_id(product_id)
               if current_user.get("role") == "BUYER"
               else await product_repo.find_by_id(product_id))
    if not product:
        raise NotFoundError("Product")

    role = current_user.get("role", "")

    if role == "FARMER":
        # Only own products
        if product["farmer_id"] != current_user["id"]:
            raise ForbiddenError("You can only view your own products.")
        data = FarmerProductResponse(
            description=product.get("description", ""),
            product_id=product["id"],
            product_name=product.get("product_name", ""),
            category=product.get("category", ""),
            state=product.get("state"), district=product.get("district"), variety=product.get("variety"),
            quantity_available=product.get("quantity_available", 0),
            quantity_unit=product.get("quantity_unit", ""),
            quality_grade=product.get("quality_grade", ""),
            image_url=product.get("image_url"),
            location=product.get("location", ""),
            market=product.get("market", ""),
            harvest_date=product.get("harvest_date"),
            market_reference=reference_view(product),
            farmer_payout_per_unit_paise=product.get("farmer_payout_per_unit_paise", 0),
            farmer_payout_per_unit_display=format_rupees(product.get("farmer_payout_per_unit_paise", 0)),
            status=product.get("status", ""),
            created_at=product.get("created_at"),
            updated_at=product.get("updated_at"),
        ).model_dump()
    elif role == "BUYER":
        product = await PricingEngine(db).buyer_pricing(product)
        farm = await FarmerRepository(db).find_by_user_id(product.get("farmer_id", ""))
        application = (farm or {}).get("application") or {}
        farmer = await user_repo.find_by_id(product.get("farmer_id", ""))
        data = BuyerProductResponse(
            description=product.get("description", ""),
            product_id=product["id"],
            product_name=product.get("product_name", ""),
            category=product.get("category", ""),
            quantity_available=product.get("quantity_available", 0),
            quantity_unit=product.get("quantity_unit", ""),
            quality_grade=product.get("quality_grade", ""),
            image_url=product.get("image_url"),
            location=product.get("location", ""),
            farmer_name=farmer["name"] if farmer else None,
            pickup_address=application.get("pickup_address", product.get("location")),
            delivery_available=application.get("delivery_available", False),
            farmer_base_price_paise=product.get("farmer_payout_per_unit_paise", 0),
            commission_per_unit_paise=product.get("commission_per_unit_paise", 0),
            commission_percentage_bps=product.get("commission_percentage", 0),
            farm_coordinates=application.get("coordinates"), market_reference=reference_view(product),
            buyer_price_per_unit_paise=product.get("buyer_price_per_unit_paise", 0),
            buyer_price_per_unit_display=format_rupees(product.get("buyer_price_per_unit_paise", 0)),
            harvest_date=product.get("harvest_date"),
        ).model_dump()
    else:
        # ADMIN
        farmer = await user_repo.find_by_id(product.get("farmer_id", ""))
        data = AdminProductResponse(
            description=product.get("description", ""),
            product_id=product["id"],
            product_name=product.get("product_name", ""),
            category=product.get("category", ""),
            farmer_id=product.get("farmer_id", ""),
            farmer_name=farmer["name"] if farmer else "",
            quantity_available=product.get("quantity_available", 0),
            quantity_unit=product.get("quantity_unit", ""),
            quality_grade=product.get("quality_grade", ""),
            image_url=product.get("image_url"),
            location=product.get("location", ""),
            market=product.get("market", ""),
            harvest_date=product.get("harvest_date"),
            government_reference_price_paise=product.get("government_reference_price_paise", 0),
            government_reference_price_display=format_rupees(product.get("government_reference_price_paise", 0)),
            reference_price_date=product.get("reference_price_date"),
            reference_price_source=product.get("reference_price_source"),
            farmer_payout_per_unit_paise=product.get("farmer_payout_per_unit_paise", 0),
            farmer_payout_per_unit_display=format_rupees(product.get("farmer_payout_per_unit_paise", 0)),
            buyer_price_per_unit_paise=product.get("buyer_price_per_unit_paise", 0),
            buyer_price_per_unit_display=format_rupees(product.get("buyer_price_per_unit_paise", 0)),
            commission_percentage_bps=product.get("commission_percentage", 0),
            commission_percentage_display=percentage_bps_to_display(product.get("commission_percentage", 0)),
            commission_per_unit_paise=product.get("commission_per_unit_paise", 0),
            commission_per_unit_display=format_rupees(product.get("commission_per_unit_paise", 0)),
            pricing_policy_id=product.get("pricing_policy_id"),
            pricing_policy_version=product.get("pricing_policy_version"),
            status=product.get("status", ""),
            created_at=product.get("created_at"),
            updated_at=product.get("updated_at"),
        ).model_dump()

    return APIResponse(success=True, data=data, request_id=get_request_id(request))


@router.put("/{product_id}", response_model=APIResponse)
@transactional_endpoint
async def update_product(
    product_id: str,
    data: UpdateProductRequest,
    request: Request,
    current_user: dict = Depends(get_approved_farmer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Update own product (limited fields)."""
    product_repo = ProductRepository(db)
    product = await product_repo.find_by_id(product_id)
    if not product:
        raise NotFoundError("Product")
    if product["farmer_id"] != current_user["id"]:
        raise ForbiddenError("You can only update your own products.")

    if data.image_url is not None and data.image_url != product.get("image_url"):
        await validate_owned_image(db, data.image_url, current_user["id"])
    update_fields = {k: v.value if hasattr(v, 'value') else v for k, v in data.model_dump(exclude_none=True).items()}
    if "quantity" in update_fields:
        from app.core.exceptions import ValidationError
        raise ValidationError("Use stock_adjustment to add or remove available units safely.")
    price = update_fields.pop("selling_price_per_unit_paise", None)
    if price is not None:
        amounts = await PricingEngine(db).selling_amounts(price)
        update_fields.update({**amounts, "commission_percentage": amounts["commission_percentage_bps"], "pricing_mode": "FARMER_SELECTED"})
    adjustment = update_fields.pop("stock_adjustment", None)
    if adjustment is not None:
        from bson import ObjectId
        result = await collection(db, "products").update_one({"_id": ObjectId(product_id), "quantity_available": {"$gte": max(0, -adjustment)}}, {"$inc": {"quantity_available": adjustment}})
        if not result.matched_count:
            from app.core.exceptions import ValidationError
            raise ValidationError("Stock adjustment would make available inventory negative.")
    if "status" in update_fields:
        if update_fields["status"] not in ("ACTIVE", "INACTIVE"):
            from app.core.exceptions import ValidationError
            raise ValidationError("Farmer availability must be ACTIVE or INACTIVE.")
        update_fields["is_active"] = update_fields["status"] == "ACTIVE"
    if update_fields:
        await product_repo.update(product_id, update_fields)

    return APIResponse(
        success=True,
        data={"message": "Product updated successfully."},
        request_id=get_request_id(request),
    )


@router.delete("/{product_id}", response_model=APIResponse)
async def deactivate_product(
    product_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Deactivate a product. Farmer can deactivate own; Admin can deactivate any."""
    product_repo = ProductRepository(db)
    product = await product_repo.find_by_id(product_id)
    if not product:
        raise NotFoundError("Product")

    role = current_user.get("role", "")
    if role == "FARMER" and product["farmer_id"] != current_user["id"]:
        raise ForbiddenError("You can only deactivate your own products.")
    if role not in ("FARMER", "ADMIN"):
        raise ForbiddenError("Insufficient permissions.")

    await product_repo.deactivate(product_id)

    return APIResponse(
        success=True,
        data={"message": "Product deactivated."},
        request_id=get_request_id(request),
    )
