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

router = APIRouter(prefix="/products", tags=["Products"])


@router.post("/", response_model=APIResponse, status_code=201)
async def create_product(
    data: CreateProductRequest,
    request: Request,
    current_user: dict = Depends(get_approved_farmer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """
    Farmer creates a product.
    Backend fetches Government price and calculates pricing.
    Response shows ONLY farmer payout — no buyer price, no commission.
    """
    pricing_engine = PricingEngine(db)
    product_repo = ProductRepository(db)
    audit = AuditService(db)

    # Calculate pricing from Government data
    pricing = await pricing_engine.calculate_pricing(
        product_name=data.product_name,
        category=data.category,
        quantity=data.quantity,
        unit=data.quantity_unit.value,
        quality_grade=data.quality_grade.value,
        location=data.location,
        market=data.market,
        farmer_id=current_user["id"],
    )

    # Build product document
    product_doc = {
        "farmer_id": current_user["id"],
        "product_name": data.product_name,
        "category": data.category,
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
            product_id=p["id"],
            product_name=p.get("product_name", ""),
            category=p.get("category", ""),
            quantity_available=p.get("quantity_available", 0),
            quantity_unit=p.get("quantity_unit", ""),
            quality_grade=p.get("quality_grade", ""),
            image_url=p.get("image_url"),
            location=p.get("location", ""),
            market=p.get("market", ""),
            harvest_date=p.get("harvest_date"),
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
        products, total = await product_repo.list_active(category, location, page, limit)

    items = []
    for p in products:
        if role == "BUYER":
            farmer = await user_repo.find_by_id(p.get("farmer_id", ""))
            items.append(BuyerProductResponse(
                product_id=p["id"],
                product_name=p.get("product_name", ""),
                category=p.get("category", ""),
                quantity_available=p.get("quantity_available", 0),
                quantity_unit=p.get("quantity_unit", ""),
                quality_grade=p.get("quality_grade", ""),
                image_url=p.get("image_url"),
                location=p.get("location", ""),
                farmer_name=farmer["name"] if farmer else None,
                buyer_price_per_unit_paise=p.get("buyer_price_per_unit_paise", 0),
                buyer_price_per_unit_display=format_rupees(p.get("buyer_price_per_unit_paise", 0)),
                harvest_date=p.get("harvest_date"),
            ).model_dump())
        elif role == "ADMIN":
            farmer = await user_repo.find_by_id(p.get("farmer_id", ""))
            items.append(AdminProductResponse(
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
            product_id=product["id"],
            product_name=product.get("product_name", ""),
            category=product.get("category", ""),
            quantity_available=product.get("quantity_available", 0),
            quantity_unit=product.get("quantity_unit", ""),
            quality_grade=product.get("quality_grade", ""),
            image_url=product.get("image_url"),
            location=product.get("location", ""),
            market=product.get("market", ""),
            harvest_date=product.get("harvest_date"),
            farmer_payout_per_unit_paise=product.get("farmer_payout_per_unit_paise", 0),
            farmer_payout_per_unit_display=format_rupees(product.get("farmer_payout_per_unit_paise", 0)),
            status=product.get("status", ""),
            created_at=product.get("created_at"),
            updated_at=product.get("updated_at"),
        ).model_dump()
    elif role == "BUYER":
        farmer = await user_repo.find_by_id(product.get("farmer_id", ""))
        data = BuyerProductResponse(
            product_id=product["id"],
            product_name=product.get("product_name", ""),
            category=product.get("category", ""),
            quantity_available=product.get("quantity_available", 0),
            quantity_unit=product.get("quantity_unit", ""),
            quality_grade=product.get("quality_grade", ""),
            image_url=product.get("image_url"),
            location=product.get("location", ""),
            farmer_name=farmer["name"] if farmer else None,
            buyer_price_per_unit_paise=product.get("buyer_price_per_unit_paise", 0),
            buyer_price_per_unit_display=format_rupees(product.get("buyer_price_per_unit_paise", 0)),
            harvest_date=product.get("harvest_date"),
        ).model_dump()
    else:
        # ADMIN
        farmer = await user_repo.find_by_id(product.get("farmer_id", ""))
        data = AdminProductResponse(
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

    update_fields = {k: v.value if hasattr(v, 'value') else v for k, v in data.model_dump(exclude_none=True).items()}
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
