"""
Unit tests for Role-Based Access Control (RBAC) and route protection.
Verifies role enforcement: Farmer, Buyer, Admin, and unauthorized rejections.
"""

import pytest
from app.api.deps import require_role, get_current_farmer, get_current_buyer, get_current_admin
from app.core.exceptions import InsufficientRoleError


@pytest.mark.asyncio
async def test_require_role_matching():
    admin_user = {"id": "1", "role": "ADMIN"}
    role_checker = require_role("ADMIN")
    result = await role_checker(current_user=admin_user)
    assert result == admin_user


@pytest.mark.asyncio
async def test_require_role_forbidden():
    farmer_user = {"id": "2", "role": "FARMER"}
    role_checker = require_role("ADMIN")
    with pytest.raises(InsufficientRoleError):
        await role_checker(current_user=farmer_user)


@pytest.mark.asyncio
async def test_get_current_farmer():
    farmer_user = {"id": "2", "role": "FARMER"}
    buyer_user = {"id": "3", "role": "BUYER"}

    # Farmer succeeds
    result = await get_current_farmer(current_user=farmer_user)
    assert result["role"] == "FARMER"

    # Buyer fails with InsufficientRoleError
    with pytest.raises(InsufficientRoleError):
        await get_current_farmer(current_user=buyer_user)


@pytest.mark.asyncio
async def test_get_current_buyer():
    farmer_user = {"id": "2", "role": "FARMER"}
    buyer_user = {"id": "3", "role": "BUYER"}

    # Buyer succeeds
    result = await get_current_buyer(current_user=buyer_user)
    assert result["role"] == "BUYER"

    # Farmer fails with InsufficientRoleError
    with pytest.raises(InsufficientRoleError):
        await get_current_buyer(current_user=farmer_user)


@pytest.mark.asyncio
async def test_get_current_admin():
    admin_user = {"id": "1", "role": "ADMIN"}
    buyer_user = {"id": "3", "role": "BUYER"}

    # Admin succeeds
    result = await get_current_admin(current_user=admin_user)
    assert result["role"] == "ADMIN"

    # Buyer fails with InsufficientRoleError
    with pytest.raises(InsufficientRoleError):
        await get_current_admin(current_user=buyer_user)
