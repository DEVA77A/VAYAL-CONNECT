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
from datetime import date, datetime, timezone, timedelta
from motor.motor_asyncio import AsyncIOMotorDatabase
import logging

from app.core.transactions import locked_transactional
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
        self._commission_loaded = False
        self._commission = None

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
        selling_price_per_unit_paise: Optional[int] = None,
    ) -> Dict[str, Any]:
        """
        Calculate complete pricing for a product.
        Returns the pricing snapshot data (not yet persisted).

        This is the ONLY place where prices are calculated.
        """
        if selling_price_per_unit_paise is not None:
            try:
                reference = await self.get_verified_reference(product_name, market, unit)
            except (MarketPriceUnavailableError, ValidationError):
                reference = {"government_reference_price_paise": 0, "reference_price_available": False,
                    "reference_price_message": "No compatible verified official reference available. Selling price is farmer-selected."}
            amounts = await self.selling_amounts(selling_price_per_unit_paise)
            return {**reference, **amounts, "farmer_id": farmer_id, "pricing_mode": "FARMER_SELECTED",
                    "pricing_policy_id": None, "pricing_policy_version": 0,
                    "market": market, "location": location, "quality_grade": quality_grade, "quantity": quantity, "unit": unit,
                    "farmer_total_payout_paise": safe_multiply(selling_price_per_unit_paise, quantity),
                    "buyer_total_paise": safe_multiply(amounts["buyer_price_per_unit_paise"], quantity),
                    "commission_total_paise": safe_multiply(amounts["commission_per_unit_paise"], quantity),
                    "calculated_at": datetime.now(timezone.utc)}
        # Historical-policy helpers still require the same verified, bounded reference.
        # New public listing creation always supplies a farmer-selected base price.
        reference = await self.get_verified_reference(product_name, market, unit)
        gov_ref_price_paise = reference["government_reference_price_paise"]
        price_unit = reference["reference_price_unit"]
        price_date = reference["reference_price_date"]
        price_source = reference["reference_price_source"]

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
        gov_per_kg_paise = reference["reference_price_per_listing_unit_paise"]

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

    async def selling_amounts(self, selling_price: int) -> Dict[str, Any]:
        if type(selling_price) is not int or not 0 < selling_price <= 100_000_000:
            raise ValidationError("Selling price must be positive integer paise, at most ₹1,000,000 per unit.")
        if not self._commission_loaded:
            self._commission = await self.pricing_repo.get_active_commission()
            self._commission_loaded = True
        config = self._commission
        bps = config["commission_percentage_bps"] if config else DEFAULT_COMMISSION_BPS
        if type(bps) is not int or not 0 <= bps <= 10000:
            raise FinancialInconsistencyError("Invalid commission configuration.")
        commission = calculate_percentage(selling_price, bps)
        return {"farmer_payout_per_unit_paise": selling_price, "buyer_price_per_unit_paise": selling_price + commission,
                "commission_per_unit_paise": commission, "commission_percentage_bps": bps,
                "commission_config_id": config.get("id") if config else None,
                "commission_config_version": config.get("version", 0) if config else 0}

    async def buyer_pricing(self, product: dict) -> dict:
        if not product.get("farmer_payout_per_unit_paise"):
            raise ValidationError("Listing has no valid farmer base price.")
        amounts = await self.selling_amounts(product["farmer_payout_per_unit_paise"])
        return {**product, **amounts, "commission_percentage": amounts["commission_percentage_bps"]}

    async def get_verified_reference(self, commodity: str, market: str, unit: str) -> dict:
        record = await market_price_provider.get_market_price(commodity=commodity, market=market, state=None)
        cached = False
        if not self._valid_reference(record, commodity, market):
            record = await self.pricing_repo.get_latest_market_price(commodity=commodity, market=market)
            cached = True
        if not self._valid_reference(record, commodity, market):
            raise MarketPriceUnavailableError()
        retrieved = record.get("retrieved_at")
        if isinstance(retrieved, str):
            try: retrieved = datetime.fromisoformat(retrieved.replace("Z", "+00:00"))
            except ValueError: retrieved = None
        if not isinstance(retrieved, datetime):
            raise MarketPriceUnavailableError()
        retrieved = retrieved.replace(tzinfo=timezone.utc) if retrieved.tzinfo is None else retrieved
        age = datetime.now(timezone.utc) - retrieved
        if age < timedelta(0) or age > timedelta(days=7):
            raise MarketPriceUnavailableError()
        arrival = date.fromisoformat(str(record["arrival_date"])[:10])
        raw_unit = record["unit"].upper().strip()
        aliases = {"KILOGRAM": "KG", "QTL": "QUINTAL", "TONNE": "TON", "MT": "TON", "PIECES": "PIECE"}
        raw_unit = aliases.get(raw_unit, raw_unit)
        factors = {"KG": 1, "QUINTAL": 100, "TON": 1000}
        raw_price = record["modal_price_paise"]
        if unit in factors and raw_unit in factors:
            converted = int((Decimal(raw_price) * factors[unit] / factors[raw_unit]).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
        elif unit == raw_unit and unit in ("PIECE", "DOZEN"):
            converted = raw_price
        else:
            raise ValidationError("Market reference unit cannot be compared with this listing unit.")
        if not cached:
            await self.pricing_repo.store_market_price(record)
        return {"reference_price_available": True, "government_reference_price_paise": raw_price, "reference_price_per_listing_unit_paise": converted,
                "reference_price_unit": record["unit"], "reference_listing_unit": unit,
                "reference_price_date": arrival.isoformat(), "reference_price_source": record["source"],
                "reference_price_cached": cached, "reference_price_stale": (datetime.now(timezone.utc).date() - arrival).days > 1,
                "reference_price_retrieved_at": record.get("retrieved_at"),
                "reference_commodity": record["commodity"], "reference_market": record["market"],
                "reference_min_paise": record.get("min_price_paise"), "reference_max_paise": record.get("max_price_paise"),
                "reference_state": record.get("state"), "reference_source_url": record.get("source_url")}

    @staticmethod
    def _valid_reference(record, commodity, market):
        if not isinstance(record, dict):
            return False
        if str(record.get("commodity", "")).strip().casefold() != commodity.strip().casefold() or str(record.get("market", "")).strip().casefold() != market.strip().casefold():
            return False
        if record.get("modal_price_verified") is not True:
            return False
        if record.get("source") != "data.gov.in AGMARKNET" or not record.get("unit"):
            return False
        price = record.get("modal_price_paise")
        if type(price) is not int or price <= 0:
            return False
        minimum, maximum = record.get("min_price_paise"), record.get("max_price_paise")
        if minimum is not None or maximum is not None:
            if not all(type(v) is int and v > 0 for v in (minimum, maximum)) or not minimum <= price <= maximum:
                return False
        try:
            arrival = date.fromisoformat(str(record.get("arrival_date"))[:10])
            return arrival <= datetime.now(timezone.utc).date()
        except (ValueError, TypeError):
            return False

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
            raise ValidationError("A count unit cannot be converted to a weight unit.")
        else:
            raise ValidationError("Unknown official market-price unit.")


class CommissionService:
    """Manage commission configuration."""

    def __init__(self, db: AsyncIOMotorDatabase):
        self.db = db
        self.pricing_repo = PricingRepository(db)

    async def get_active_commission(self) -> Optional[Dict[str, Any]]:
        config = await self.pricing_repo.get_active_commission()
        if config:
            config["commission_percentage_display"] = percentage_bps_to_display(
                config["commission_percentage_bps"]
            )
        return config

    @locked_transactional("configuration_locks", "global-commission")
    async def update_commission(
        self, new_percentage_bps: int, admin_id: str
    ) -> Dict[str, Any]:
        """
        Update commission percentage.
        The old config is superseded; new one takes effect immediately.
        Historical transactions retain their original commission.
        """
        if type(new_percentage_bps) is not int or not 0 <= new_percentage_bps <= 10000:
            raise ValidationError("Commission must be between 0% and 100%.")
        current = await self.pricing_repo.get_active_commission()
        previous_bps = current["commission_percentage_bps"] if current else DEFAULT_COMMISSION_BPS

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
