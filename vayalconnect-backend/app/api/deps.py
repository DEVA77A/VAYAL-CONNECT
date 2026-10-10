"""
VayalConnect Backend — API Dependencies

Authentication and RBAC dependencies for FastAPI routes.
Every protected endpoint uses these dependencies.
"""

from typing import Optional, List
from fastapi import Depends, Header, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError
from motor.motor_asyncio import AsyncIOMotorDatabase

from app.core.security import decode_token
from app.core.database import get_database
from app.core.exceptions import (
    UnauthorizedError, ForbiddenError, InsufficientRoleError,
    InvalidTokenError, TokenExpiredError,
)
from app.repositories.users import UserRepository

security_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security_scheme),
    db: AsyncIOMotorDatabase = Depends(get_database),
) -> dict:
    """
    Extract and validate JWT token. Returns the full user document.
    Used as dependency on all protected endpoints.
    """
    if not credentials:
        raise UnauthorizedError("Authentication required.")

    token = credentials.credentials
    try:
        payload = decode_token(token)
    except JWTError:
        raise InvalidTokenError()

    if payload.get("type") != "access":
        raise InvalidTokenError()

    user_id = payload.get("sub")
    if not user_id:
        raise InvalidTokenError()

    user_repo = UserRepository(db)
    user = await user_repo.find_by_id(user_id)

    if not user:
        raise InvalidTokenError()

    if not user.get("is_active"):
        raise ForbiddenError("Account is deactivated.")

    return user


def require_role(*allowed_roles: str):
    """
    Dependency factory that enforces role-based access control.

    Usage:
        @router.get("/admin-only", dependencies=[Depends(require_role("ADMIN"))])
    """
    async def role_checker(
        current_user: dict = Depends(get_current_user),
    ) -> dict:
        user_role = current_user.get("role")
        if not user_role or user_role not in allowed_roles:
            raise InsufficientRoleError(", ".join(allowed_roles))
        return current_user

    return role_checker


async def get_current_farmer(
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Ensure current user is a FARMER."""
    if current_user.get("role") != "FARMER":
        raise InsufficientRoleError("FARMER")
    return current_user


async def get_current_buyer(
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Ensure current user is a BUYER."""
    if current_user.get("role") != "BUYER":
        raise InsufficientRoleError("BUYER")
    return current_user


async def get_current_admin(
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Ensure current user is an ADMIN."""
    if current_user.get("role") != "ADMIN":
        raise InsufficientRoleError("ADMIN")
    return current_user


def get_request_id(request: Request) -> Optional[str]:
    """Get request ID from middleware."""
    return getattr(request.state, "request_id", None)
