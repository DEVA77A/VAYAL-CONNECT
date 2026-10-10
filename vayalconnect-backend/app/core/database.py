"""
VayalConnect Backend — Database Connection

Async MongoDB connection via Motor.
Manages connection lifecycle and provides collection access.
"""

from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from typing import Optional
import logging

from app.core.config import settings

logger = logging.getLogger(__name__)


class Database:
    """MongoDB connection manager."""

    client: Optional[AsyncIOMotorClient] = None
    db: Optional[AsyncIOMotorDatabase] = None

    async def connect(self):
        """Establish MongoDB connection."""
        logger.info("Connecting to MongoDB Atlas...")
        self.client = AsyncIOMotorClient(
            settings.MONGODB_URI,
            tz_aware=True,
            maxPoolSize=50,
            minPoolSize=10,
            serverSelectionTimeoutMS=5000,
            connectTimeoutMS=10000,
        )
        self.db = self.client[settings.MONGODB_DATABASE]

        # Verify connection
        try:
            await self.client.admin.command("ping")
            logger.info("MongoDB connection established successfully.")
        except Exception as e:
            logger.error(f"MongoDB connection failed: {e}")
            raise

    async def disconnect(self):
        """Close MongoDB connection."""
        if self.client is not None:
            self.client.close()
            logger.info("MongoDB connection closed.")

    async def is_connected(self) -> bool:
        """Check if MongoDB is reachable."""
        try:
            if self.client is not None:
                await self.client.admin.command("ping")
                return True
        except Exception:
            pass
        return False

    async def create_indexes(self):
        """Create all required indexes."""
        if self.db is None:
            raise RuntimeError("Database not connected")

        logger.info("Creating database indexes...")

        # Users
        users = self.db["users"]
        await users.create_index("email", unique=True)
        await users.create_index("phone", unique=True)
        await users.create_index("role")
        await users.create_index("is_active")

        # Farmer Profiles
        farmer_profiles = self.db["farmer_profiles"]
        await farmer_profiles.create_index("user_id", unique=True)
        await farmer_profiles.create_index("approval_status")

        # Buyer Profiles
        buyer_profiles = self.db["buyer_profiles"]
        await buyer_profiles.create_index("user_id", unique=True)

        # Products
        products = self.db["products"]
        await products.create_index("farmer_id")
        await products.create_index("product_name")
        await products.create_index("category")
        await products.create_index("status")
        await products.create_index("is_active")
        await products.create_index("location")

        # Market Prices
        market_prices = self.db["market_prices"]
        await market_prices.create_index(
            [("commodity", 1), ("market", 1), ("arrival_date", -1)]
        )
        await market_prices.create_index("commodity")
        await market_prices.create_index("arrival_date")

        # Pricing Policies
        pricing_policies = self.db["pricing_policies"]
        await pricing_policies.create_index("is_active")

        # Commission Configs
        commission_configs = self.db["commission_configs"]
        await commission_configs.create_index("status")
        await commission_configs.create_index("effective_from")

        # Pricing Snapshots
        pricing_snapshots = self.db["pricing_snapshots"]
        await pricing_snapshots.create_index("product_id")
        await pricing_snapshots.create_index("farmer_id")
        await pricing_snapshots.create_index("created_at")

        # Orders
        orders = self.db["orders"]
        await orders.create_index("buyer_id")
        await orders.create_index("farmer_id")
        await orders.create_index("product_id")
        await orders.create_index("order_number", unique=True)
        await orders.create_index("order_status")
        await orders.create_index("payment_status")
        await orders.create_index("payout_status")
        await orders.create_index("idempotency_key", unique=True, sparse=True)
        await orders.create_index("created_at")

        # Payments
        payments = self.db["payments"]
        await payments.create_index("order_id")
        await payments.create_index("buyer_id")
        await payments.create_index("razorpay_order_id", unique=True)
        await payments.create_index("razorpay_payment_id", sparse=True)
        await payments.create_index("payment_status")
        await payments.create_index("idempotency_key", unique=True, sparse=True)

        # Payouts
        payouts = self.db["payouts"]
        await payouts.create_index("order_id")
        await payouts.create_index("farmer_id")
        await payouts.create_index("status")
        await payouts.create_index("payout_number", unique=True)
        await payouts.create_index("idempotency_key", unique=True, sparse=True)

        # OTP Verifications
        otp_verifications = self.db["otp_verifications"]
        await otp_verifications.create_index([("email", 1), ("purpose", 1)])
        await otp_verifications.create_index(
            "expires_at", expireAfterSeconds=0
        )  # TTL index

        # Refresh Tokens
        refresh_tokens = self.db["refresh_tokens"]
        await refresh_tokens.create_index("user_id")
        await refresh_tokens.create_index("token_hash", unique=True)
        await refresh_tokens.create_index(
            "expires_at", expireAfterSeconds=0
        )  # TTL index

        # Audit Logs
        audit_logs = self.db["audit_logs"]
        await audit_logs.create_index("actor_id")
        await audit_logs.create_index("action")
        await audit_logs.create_index("entity_type")
        await audit_logs.create_index("timestamp")
        await audit_logs.create_index([("entity_type", 1), ("entity_id", 1)])

        # Admin Actions
        admin_actions = self.db["admin_actions"]
        await admin_actions.create_index("admin_id")
        await admin_actions.create_index("action_type")
        await admin_actions.create_index("created_at")

        logger.info("All database indexes created successfully.")


# Global database instance
database = Database()


async def connect_db():
    """Connect to MongoDB."""
    await database.connect()


async def close_db():
    """Disconnect from MongoDB."""
    await database.disconnect()


async def create_indexes():
    """Create all indexes."""
    await database.create_indexes()


def get_database() -> AsyncIOMotorDatabase:
    """Get the database instance. Used as FastAPI dependency."""
    if database.db is None:
        raise RuntimeError("Database not initialized. Call database.connect() first.")
    return database.db
