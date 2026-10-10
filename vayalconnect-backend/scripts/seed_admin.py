"""
VayalConnect Backend — Admin Seed Script

Creates the initial admin user and default commission config.
Run once during initial deployment:
    python -m scripts.seed_admin
"""

import asyncio
import sys
import os

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.config import settings
from app.core.security import hash_password
from app.core.database import connect_db, close_db, get_database
from app.repositories.users import UserRepository
from app.repositories.pricing import PricingRepository
from datetime import datetime, timezone


async def seed_admin():
    """Create the admin user if it doesn't exist."""
    await connect_db()
    db = get_database()
    user_repo = UserRepository(db)
    pricing_repo = PricingRepository(db)

    # ============================================================
    # 1. Create Admin User
    # ============================================================
    admin_email = settings.ADMIN_EMAIL
    admin_password = settings.ADMIN_PASSWORD

    if not admin_email or not admin_password:
        print("❌ ADMIN_EMAIL and ADMIN_PASSWORD must be set in .env")
        await close_db()
        return

    existing = await user_repo.find_by_email(admin_email)
    if existing:
        print(f"✅ Admin user already exists: {admin_email}")
    else:
        admin_doc = {
            "name": "VayalConnect Admin",
            "email": admin_email,
            "phone": "+919999999999",
            "password_hash": hash_password(admin_password),
            "address": "VayalConnect HQ",
            "area_location": "Chennai",
            "gender": "other",
            "age": 30,
            "role": "ADMIN",
            "email_verified": True,
            "is_active": True,
            "is_approved": True,
            "preferred_language": "en",
        }
        admin_id = await user_repo.create(admin_doc)
        print(f"✅ Admin user created: {admin_email} (ID: {admin_id})")

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
            "created_by": "system",
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

    await close_db()
    print("\n🌾 Seed completed successfully!")


if __name__ == "__main__":
    asyncio.run(seed_admin())
