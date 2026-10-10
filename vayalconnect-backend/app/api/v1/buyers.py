"""
VayalConnect Backend — Buyers Router
"""

from fastapi import APIRouter, Depends, Request
from motor.motor_asyncio import AsyncIOMotorDatabase

from app.core.database import get_database
from app.api.deps import get_current_buyer, get_request_id
from app.repositories.buyers import BuyerRepository
from app.schemas.buyer import BuyerProfileResponse, UpdateBuyerProfileRequest
from app.schemas.common import APIResponse

router = APIRouter(prefix="/buyers", tags=["Buyer"])


@router.get("/me/profile", response_model=APIResponse)
async def get_buyer_profile(
    request: Request,
    current_user: dict = Depends(get_current_buyer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Get buyer profile."""
    buyer_repo = BuyerRepository(db)
    profile = await buyer_repo.find_by_user_id(current_user["id"])

    return APIResponse(
        success=True,
        data=BuyerProfileResponse(
            user_id=current_user["id"],
            name=current_user["name"],
            email=current_user["email"],
            phone=current_user["phone"],
            address=current_user.get("address", ""),
            area_location=current_user.get("area_location", ""),
            gender=current_user.get("gender", ""),
            age=current_user.get("age", 0),
            business_name=profile.get("business_name") if profile else None,
            created_at=current_user.get("created_at"),
        ).model_dump(),
        request_id=get_request_id(request),
    )


@router.put("/me/profile", response_model=APIResponse)
async def update_buyer_profile(
    data: UpdateBuyerProfileRequest,
    request: Request,
    current_user: dict = Depends(get_current_buyer),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Update buyer profile."""
    buyer_repo = BuyerRepository(db)
    update_fields = {k: v for k, v in data.model_dump(exclude_none=True).items()}
    if update_fields:
        await buyer_repo.update(current_user["id"], update_fields)
    return APIResponse(
        success=True,
        data={"message": "Profile updated successfully."},
        request_id=get_request_id(request),
    )
