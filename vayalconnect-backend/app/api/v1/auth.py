"""
VayalConnect Backend — Auth Router

Registration, login, OTP, role selection, password management.
"""

from fastapi import APIRouter, Depends, Request
from motor.motor_asyncio import AsyncIOMotorDatabase

from app.core.database import get_database
from app.api.deps import get_current_user, get_request_id
from app.services.auth_service import AuthService
from app.schemas.auth import (
    RegisterRequest, RegisterResponse, OTPRequest, OTPVerifyRequest,
    OTPResponse, OTPVerifyResponse, RoleSelectRequest, RoleSelectResponse,
    LoginRequest, LoginResponse, RefreshTokenRequest, RefreshTokenResponse,
    ChangePasswordRequest, ForgotPasswordRequest, ResetPasswordRequest,
)
from app.schemas.common import APIResponse

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/register", response_model=APIResponse, status_code=201)
async def register(
    data: RegisterRequest,
    request: Request,
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Register a new user account."""
    service = AuthService(db)
    result = await service.register(data.model_dump())
    return APIResponse(
        success=True,
        data=RegisterResponse(**result).model_dump(),
        request_id=get_request_id(request),
    )


@router.post("/request-otp", response_model=APIResponse)
async def request_otp(
    data: OTPRequest,
    request: Request,
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Send OTP to email via Brevo."""
    service = AuthService(db)
    result = await service.request_otp(data.email, data.purpose.value)
    return APIResponse(
        success=True,
        data=OTPResponse(message=result["message"]).model_dump(),
        request_id=get_request_id(request),
    )


@router.post("/verify-otp", response_model=APIResponse)
async def verify_otp(
    data: OTPVerifyRequest,
    request: Request,
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Verify email OTP."""
    service = AuthService(db)
    verified = await service.verify_otp(data.email, data.otp, data.purpose.value)
    return APIResponse(
        success=True,
        data=OTPVerifyResponse(verified=verified, message="OTP verified successfully.").model_dump(),
        request_id=get_request_id(request),
    )


@router.post("/select-role", response_model=APIResponse)
async def select_role(
    data: RoleSelectRequest,
    request: Request,
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Select FARMER or BUYER role after email verification."""
    service = AuthService(db)
    result = await service.select_role(current_user["id"], data.role.value)
    return APIResponse(
        success=True,
        data=RoleSelectResponse(**result).model_dump(),
        request_id=get_request_id(request),
    )


@router.post("/login", response_model=APIResponse)
async def login(
    data: LoginRequest,
    request: Request,
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Login with email and password."""
    service = AuthService(db)
    result = await service.login(data.email, data.password)
    return APIResponse(
        success=True,
        data=result,
        request_id=get_request_id(request),
    )


@router.post("/refresh", response_model=APIResponse)
async def refresh_token(
    data: RefreshTokenRequest,
    request: Request,
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Refresh access token using refresh token."""
    service = AuthService(db)
    result = await service.refresh_access_token(data.refresh_token)
    return APIResponse(
        success=True,
        data=result,
        request_id=get_request_id(request),
    )


@router.post("/logout", response_model=APIResponse)
async def logout(
    request: Request,
    current_user: dict = Depends(get_current_user),
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Logout — revoke all refresh tokens."""
    service = AuthService(db)
    await service.logout(current_user["id"])
    return APIResponse(
        success=True,
        data={"message": "Logged out successfully."},
        request_id=get_request_id(request),
    )


@router.post("/forgot-password", response_model=APIResponse)
async def forgot_password(
    data: ForgotPasswordRequest,
    request: Request,
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Request password reset OTP."""
    service = AuthService(db)
    result = await service.request_otp(data.email, "PASSWORD_RESET")
    return APIResponse(
        success=True,
        data={"message": result["message"]},
        request_id=get_request_id(request),
    )


@router.post("/reset-password", response_model=APIResponse)
async def reset_password(
    data: ResetPasswordRequest,
    request: Request,
    db: AsyncIOMotorDatabase = Depends(get_database),
):
    """Reset password using OTP."""
    service = AuthService(db)
    await service.reset_password(data.email, data.otp, data.new_password)
    return APIResponse(
        success=True,
        data={"message": "Password reset successfully."},
        request_id=get_request_id(request),
    )
