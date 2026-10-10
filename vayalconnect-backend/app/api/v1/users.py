"""
VayalConnect Backend — Users Router
"""

from fastapi import APIRouter, Depends, Request
from motor.motor_asyncio import AsyncIOMotorDatabase

from app.core.database import get_database
from app.api.deps import get_current_user, get_request_id
from app.repositories.users import UserRepository
from app.services.auth_service import AuthService
from app.schemas.user import UserProfileResponse, UpdateProfileRequest, ChangeLanguageRequest
from app.schemas.auth import ChangePasswordRequest
from app.schemas.common import APIResponse

router = APIRouter(prefix="/users", tags=["Users"])


@router.get("/me", response_model=APIResponse)
async def get_profile(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Get current user profile."""
    return APIResponse(
        success=True,
        data=UserProfileResponse(
            id=current_user["id"],
            name=current_user["name"],
            email=current_user["email"],
            phone=current_user["phone"],
            address=current_user.get("address", ""),
            area_location=current_user.get("area_location", ""),
            gender=current_user.get("gender", ""),
            age=current_user.get("age", 0),
            role=current_user.get("role"),
            email_verified=current_user.get("email_verified", False),
            preferred_language=current_user.get("preferred_language", "en"),
            created_at=current_user.get("created_at"),
        ).model_dump(),
        request_id=get_request_id(request),
    )


@router.put("/me", response_model=APIResponse)
async def update_profile(
    data: UpdateProfileRequest,
    request: Request,
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Update current user profile."""
    user_repo = UserRepository(db)
    update_fields = {k: v for k, v in data.model_dump(exclude_none=True).items()}
    if update_fields:
        await user_repo.update(current_user["id"], update_fields)
    return APIResponse(
        success=True,
        data={"message": "Profile updated successfully."},
        request_id=get_request_id(request),
    )


@router.put("/me/password", response_model=APIResponse)
async def change_password(
    data: ChangePasswordRequest,
    request: Request,
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Change password."""
    service = AuthService(db)
    await service.change_password(
        current_user["id"], data.current_password, data.new_password
    )
    return APIResponse(
        success=True,
        data={"message": "Password changed successfully. Please login again."},
        request_id=get_request_id(request),
    )


@router.put("/me/language", response_model=APIResponse)
async def change_language(
    data: ChangeLanguageRequest,
    request: Request,
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Change language preference."""
    user_repo = UserRepository(db)
    await user_repo.update(current_user["id"], {"preferred_language": data.preferred_language.value})
    return APIResponse(
        success=True,
        data={"message": "Language preference updated."},
        request_id=get_request_id(request),
    )
