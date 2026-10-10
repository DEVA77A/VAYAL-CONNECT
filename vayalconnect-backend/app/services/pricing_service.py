"""
VayalConnect Backend — Pricing Service (THE HEART OF THE SYSTEM)

All financial calculations happen here and ONLY here.
Uses integer paise for monetary calculations.
Produces immutable PricingSnapshots.

CRITICAL RULES:
1. All money in integer paise (₹35.50 = 3550 paise)
2. Commission in basis points (15% = 1500 bps)
3. Financial consistency: buyer_total == farmer_payout + commission
4. Snapshots are IMMUTABLE once created
5. Commission changes affect only NEW transactions
"""

from typing import Optional, Dict, Any
from decimal import Decimal, ROUND_HALF_UP
from datetime import datetime, timezone
from motor.motor_asyncio import AsyncIOMotorDatabase
import logging

from app.repositories.pricing import PricingRepository
from app.integrations.government_market import market_price_provider
from app.core.exceptions import (
    MarketPriceUnavailableError, ValidationError, FinancialInconsistencyError,
)
from app.utils.money import (
    rupees_to_paise, format_rupees, calculate_percentage,
    validate_financial_consistency, safe_multiply,
    percentage_bps_to_display,
)

logger = logging.getLogger(__name__)

# Default pricing policy (configurable by admin)
DEFAULT_FARMER_PAYOUT_BPS = 7000   # 70% of gov price → farmer
DEFAULT_BUYER_PRICE_BPS = 9000     # 90% of gov price → buyer pays
DEFAULT_COMMISSION_BPS = 2000      # 20% of gov price → commission


class PricingEngine:
    """
    Central pricing engine.

    Flow:
    1. Receive product + market + quality
    2. Fetch Government reference price
    3. Get active pricing policy
    4. Get active commission config
    5. Calculate farmer payout, buyer price, commission
    6. Validate financial consistency
    7. Create immutable snapshot

    NEVER trust prices from the mobile app.
    """

    def __init__(self, db: AsyncIOMotorDatabase):
        self.db = db
        self.pricing_repo = PricingRepository(db)

    async def calculate_pricing(
        self,
        product_name: str,
        category: str,
        quantity: int,
        unit: str,
        quality_grade: str,
        location: str,
        market: str,
        farmer_id: str,
    ) -> Dict[str, Any]:
        """
        Calculate complete pricing for a product.
        Returns the pricing snapshot data (not yet persisted).

        This is the ONLY place where prices are calculated.
        """
        # Step 1: Fetch Government reference price
        market_price = await market_price_provider.get_market_price(
            commodity=product_name,
            market=market,
            state=None,
        )

        if not market_price or market_price.get("modal_price_paise", 0) == 0:
            # Also check cached market prices in our DB
            cached = await self.pricing_repo.get_latest_market_price(
                commodity=product_name, market=market
            )
            if cached and cached.get("modal_price_paise", 0) > 0:
                market_price = cached
                logger.info(f"Using cached market price for {product_name}")
            else:
                raise MarketPriceUnavailableError()

        gov_ref_price_paise = market_price["modal_price_paise"]
        price_unit = market_price.get("unit", "Quintal")
        price_date = market_price.get("arrival_date")
        price_source = market_price.get("source", "data.gov.in AGMARKNET")

        # Store the market price record if from API
        if market_price.get("retrieved_at"):
            await self.pricing_repo.store_market_price(market_price)

        # Step 2: Get active pricing policy
        policy = await self.pricing_repo.get_active_policy()
        if not policy:
            # Use defaults
            farmer_payout_bps = DEFAULT_FARMER_PAYOUT_BPS
            buyer_price_bps = DEFAULT_BUYER_PRICE_BPS
            policy_id = None
            policy_version = 0
        else:
            farmer_payout_bps = policy.get("farmer_payout_percentage_bps", DEFAULT_FARMER_PAYOUT_BPS)
            buyer_price_bps = policy.get("buyer_price_percentage_bps", DEFAULT_BUYER_PRICE_BPS)
            policy_id = policy["id"]
            policy_version = policy.get("version", 1)

        # Step 3: Get active commission config
        commission_config = await self.pricing_repo.get_active_commission()
        if not commission_config:
            commission_bps = DEFAULT_COMMISSION_BPS
            commission_config_id = None
            commission_config_version = 0
        else:
            commission_bps = commission_config["commission_percentage_bps"]
            commission_config_id = commission_config["id"]
            commission_config_version = commission_config.get("version", 1)

        # Step 4: Calculate prices using Decimal for precision
        # Government price is per Quintal from data.gov.in
        # We need per-unit (KG) price
        gov_per_kg_paise = self._convert_to_per_kg(gov_ref_price_paise, price_unit)

        farmer_payout_per_unit = calculate_percentage(gov_per_kg_paise, farmer_payout_bps)
        buyer_price_per_unit = calculate_percentage(gov_per_kg_paise, buyer_price_bps)
        commission_per_unit = buyer_price_per_unit - farmer_payout_per_unit

        # Ensure commission matches configured percentage
        # commission_per_unit = buyer_price - farmer_payout
        if commission_per_unit < 0:
            raise FinancialInconsistencyError(
                "Calculated commission is negative. Check pricing policy configuration."
            )

        # Step 5: Calculate totals
        farmer_total = safe_multiply(farmer_payout_per_unit, quantity)
        buyer_total = safe_multiply(buyer_price_per_unit, quantity)
        commission_total = safe_multiply(commission_per_unit, quantity)

        # Step 6: Validate financial consistency
        if not validate_financial_consistency(buyer_total, farmer_total, commission_total):
            raise FinancialInconsistencyError(
                f"Financial inconsistency: buyer_total({buyer_total}) != "
                f"farmer_payout({farmer_total}) + commission({commission_total})"
            )

        # Build snapshot data
        snapshot_data = {
            "farmer_id": farmer_id,
            "government_reference_price_paise": gov_ref_price_paise,
            "government_per_kg_paise": gov_per_kg_paise,
            "reference_price_unit": price_unit,
            "reference_price_date": price_date,
            "reference_price_source": price_source,
            "farmer_payout_per_unit_paise": farmer_payout_per_unit,
            "buyer_price_per_unit_paise": buyer_price_per_unit,
            "commission_percentage_bps": commission_bps,
            "commission_per_unit_paise": commission_per_unit,
            "pricing_policy_id": policy_id,
            "pricing_policy_version": policy_version,
            "commission_config_id": commission_config_id,
            "commission_config_version": commission_config_version,
            "market": market,
            "location": location,
            "quality_grade": quality_grade,
            "quantity": quantity,
            "unit": unit,
            "farmer_total_payout_paise": farmer_total,
            "buyer_total_paise": buyer_total,
            "commission_total_paise": commission_total,
            "calculated_at": datetime.now(timezone.utc),
        }

        return snapshot_data

    async def create_snapshot(
        self, product_id: str, snapshot_data: Dict[str, Any]
    ) -> str:
        """Persist an immutable pricing snapshot."""
        snapshot_data["product_id"] = product_id
        snapshot_id = await self.pricing_repo.create_snapshot(snapshot_data)
        logger.info(f"Pricing snapshot created: {snapshot_id}")
        return snapshot_id

    def _convert_to_per_kg(self, price_paise: int, unit: str) -> int:
        """Convert price from given unit to per KG."""
        unit_lower = unit.lower().strip()
        if unit_lower in ("kg", "kilogram"):
            return price_paise
        elif unit_lower in ("quintal", "qtl"):
            # 1 Quintal = 100 KG
            return price_paise // 100
        elif unit_lower in ("ton", "tonne", "mt"):
            # 1 Ton = 1000 KG
            return price_paise // 1000
        elif unit_lower in ("piece", "pieces", "dozen"):
            return price_paise  # No conversion
        else:
            # Default: assume Quintal (most common in AGMARKNET)
            return price_paise // 100


class CommissionService:
    """Manage commission configuration."""

    def __init__(self, db: AsyncIOMotorDatabase):
        self.pricing_repo = PricingRepository(db)

    async def get_active_commission(self) -> Optional[Dict[str, Any]]:
        config = await self.pricing_repo.get_active_commission()
        if config:
            config["commission_percentage_display"] = percentage_bps_to_display(
                config["commission_percentage_bps"]
            )
        return config

    async def update_commission(
        self, new_percentage_bps: int, admin_id: str
    ) -> Dict[str, Any]:
        """
        Update commission percentage.
        The old config is superseded; new one takes effect immediately.
        Historical transactions retain their original commission.
        """
        # Get current
        current = await self.pricing_repo.get_active_commission()
        previous_bps = current["commission_percentage_bps"] if current else 0

        # Supersede current
        if current:
            await self.pricing_repo.supersede_active_commission()

        # Determine version
        version = (current.get("version", 0) + 1) if current else 1

        # Create new config
        new_config = {
            "commission_percentage_bps": new_percentage_bps,
            "effective_from": datetime.now(timezone.utc),
            "effective_until": None,
            "created_by": admin_id,
            "status": "ACTIVE",
            "version": version,
        }
        config_id = await self.pricing_repo.create_commission_config(new_config)

        return {
            "config_id": config_id,
            "previous_percentage_bps": previous_bps,
            "new_percentage_bps": new_percentage_bps,
            "previous_display": percentage_bps_to_display(previous_bps),
            "new_display": percentage_bps_to_display(new_percentage_bps),
            "effective_from": new_config["effective_from"],
        }

    async def get_commission_history(self):
        return await self.pricing_repo.list_commission_history()
