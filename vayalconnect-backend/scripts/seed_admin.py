"""
VayalConnect Backend — Admin Seed Script

Creates the initial admin user and default commission config.
Run once during initial deployment:
    python -m scripts.seed_admin --email <administrator-email> --phone <administrator-phone>
"""

import asyncio
import sys
import os
import argparse
from getpass import getpass

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.config import settings
from app.core.security import hash_password
from app.core.database import connect_db, close_db, get_database
from app.repositories.users import UserRepository
from app.repositories.pricing import PricingRepository
from datetime import datetime, timezone


async def seed_admin(admin_email=None, admin_password=None, admin_phone=None):
    """Create the admin user if it doesn't exist."""
    await connect_db()
    try:
        await _provision_admin(admin_email, admin_password, admin_phone)
    finally:
        await close_db()


async def _provision_admin(admin_email, admin_password, admin_phone):
    db = get_database()
    user_repo = UserRepository(db)
    pricing_repo = PricingRepository(db)

    # ============================================================
    # 1. Create Admin User
    # ============================================================
    admin_email = (admin_email or settings.ADMIN_EMAIL).strip().lower()
    admin_password = admin_password or settings.ADMIN_PASSWORD
    from app.utils.validators import is_valid_email, is_valid_phone
    from app.core.exceptions import ValidationError
    from app.services.audit_service import AuditService

    if not is_valid_email(admin_email) or not admin_phone or not is_valid_phone(admin_phone):
        raise ValidationError("Supply a valid administrator email and phone.")
    if (not admin_password or len(admin_password) < 16 or len(admin_password.encode("utf-8")) > 72
            or not any(c.isupper() for c in admin_password) or not any(c.isdigit() for c in admin_password)):
        raise ValidationError("Use a password of 16-72 bytes including uppercase and a digit.")
    existing = await user_repo.find_by_email(admin_email)
    if existing:
        if existing.get("role") != "ADMIN":
            raise ValidationError("Existing non-administrator account cannot be promoted by provisioning.")
        admin_id = str(existing["_id"])
        print("Administrator already exists; password and account were not changed.")
    else:
        if await user_repo.find_by_phone(admin_phone):
            raise ValidationError("Phone is already registered; provisioning did not change it.")
        admin_id = await user_repo.create({
            "name": "VayalConnect Admin", "email": admin_email, "phone": admin_phone,
            "password_hash": hash_password(admin_password), "address": "VayalConnect administration",
            "area_location": "Administration", "gender": "other", "age": 18,
            "role": "ADMIN", "email_verified": True, "is_active": True,
            "is_approved": True, "preferred_language": "en",
        })
        await AuditService(db).log(actor_id=admin_id, actor_role="ADMIN",
            action="ADMIN_PROVISIONED", entity_type="user", entity_id=admin_id)
        print("Administrator created. Sign in with the email and password you supplied securely.")

    # ============================================================
    # 2. Create Default Commission Config
    # ============================================================
    existing_commission = await pricing_repo.get_active_commission()
    if existing_commission:
        print(f"✅ Commission config already exists: {existing_commission['commission_percentage_bps']} bps")
    else:
        config = {
            "commission_percentage_bps": 2000,  # 20%
            "effective_from": datetime.now(timezone.utc),
            "effective_until": None,
            "created_by": admin_id,
            "status": "ACTIVE",
            "version": 1,
        }
        config_id = await pricing_repo.create_commission_config(config)
        print(f"✅ Default commission config created: 20% (ID: {config_id})")

    # ============================================================
    # 3. Create Default Pricing Policy
    # ============================================================
    existing_policy = await pricing_repo.get_active_policy()
    if existing_policy:
        print(f"✅ Pricing policy already exists: {existing_policy['name']}")
    else:
        policy = {
            "name": "Default Policy",
            "description": "Default pricing policy: Farmer gets 70% of govt price, Buyer pays 90%",
            "farmer_payout_percentage_bps": 7000,   # 70%
            "buyer_price_percentage_bps": 9000,      # 90%
            "is_active": True,
            "version": 1,
        }
        policy_id = await pricing_repo.create_policy(policy)
        print(f"✅ Default pricing policy created (ID: {policy_id})")

    print("\n🌾 Seed completed successfully!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="One-time administrator provisioning; never promotes existing ordinary users.")
    parser.add_argument("--email", required=True)
    parser.add_argument("--phone", required=True)
    args = parser.parse_args()
    password = getpass("Administrator password (16-72 bytes; hidden): ")
    confirmation = getpass("Confirm password (hidden): ")
    if password != confirmation:
        raise SystemExit("Passwords differ; no database changes made.")
    asyncio.run(seed_admin(args.email, password, args.phone))
