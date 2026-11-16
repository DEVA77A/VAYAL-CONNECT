"""
VayalConnect Backend — Farmer Operating Cost Model & Pricing Intelligence Service

Calculates sustainable farmer production and marketing costs:
1. Harvesting Cost
2. Sorting and Grading Cost
3. Packaging Cost
4. Transportation Cost (mandi / local collection point)
5. Handling & Storage Cost
6. Wastage Allowance (percentage of reference or base floor)
7. Farmer Fair Margin (fair profit percentage or amount)

Formula:
  Total Operating Cost = Harvesting + Sorting + Packaging + Transport + Handling + Wastage
  Minimum Sustainable Farmer Price = Wholesale Reference Price + Total Operating Cost
  Suggested Farmer Selling Price = Minimum Sustainable Farmer Price + Farmer Margin

Features:
- Configurable defaults per KG in integer paise.
- Crop-specific and district-specific cost adjustments.
- Sanity check against verified local retail prices (Uzhavar Sandhai).
- Audit trail for admin configuration adjustments.
"""

from typing import Dict, Any, Optional, List
from decimal import Decimal, ROUND_HALF_UP
from datetime import datetime, timezone
import logging
from motor.motor_asyncio import AsyncIOMotorDatabase
from app.core.transactions import collection
from app.utils.money import format_rupees

logger = logging.getLogger(__name__)

# Sensible agricultural defaults in Tamil Nadu (in integer paise per KG)
DEFAULT_HARVESTING_COST_PAISE = 200    # ₹2.00 / KG
DEFAULT_SORTING_COST_PAISE = 150       # ₹1.50 / KG
DEFAULT_PACKAGING_COST_PAISE = 150     # ₹1.50 / KG
DEFAULT_TRANSPORT_COST_PAISE = 200     # ₹2.00 / KG
DEFAULT_HANDLING_COST_PAISE = 100      # ₹1.00 / KG
DEFAULT_WASTAGE_ALLOWANCE_BPS = 500    # 5.00% of reference price (min 100 paise)
DEFAULT_FARMER_MARGIN_BPS = 1500       # 15.00% margin (min 300 paise)

DEFAULT_CROP_ADJUSTMENTS = {
    "Tomato": {
        "harvesting_cost_paise": 250,
        "wastage_allowance_bps": 800,  # Highly perishable
    },
    "Onion": {
        "handling_cost_paise": 150,     # Storage ventilation
        "wastage_allowance_bps": 400,
    },
    "Potato": {
        "packaging_cost_paise": 120,
        "wastage_allowance_bps": 300,
    },
    "Banana": {
        "harvesting_cost_paise": 200,
        "handling_cost_paise": 150,
    },
    "Paddy": {
        "sorting_cost_paise": 100,
        "packaging_cost_paise": 100,
        "wastage_allowance_bps": 200,
    },
    "Rice": {
        "sorting_cost_paise": 100,
        "packaging_cost_paise": 120,
        "wastage_allowance_bps": 200,
    },
    "Carrot": {
        "sorting_cost_paise": 200,     # Washing and grading
        "transport_cost_paise": 250,    # Hill transport from Nilgiris/Kodaikanal
    },
    "Brinjal": {
        "harvesting_cost_paise": 200,
        "wastage_allowance_bps": 600,
    },
}

DEFAULT_DISTRICT_ADJUSTMENTS = {
    "The Nilgiris": {
        "transport_cost_paise": 350,   # Mountainous transit
    },
    "Nilgiris": {
        "transport_cost_paise": 350,
    },
    "Dindigul": {
        "transport_cost_paise": 220,
    },
    "Kanyakumari": {
        "transport_cost_paise": 240,
    },
}


class FarmerCostService:
    """Manages agricultural production/operating cost models and price recommendations."""

    def __init__(self, db: AsyncIOMotorDatabase):
        self.db = db
        self.config_col = collection(db, "pricing_cost_configs")
        self.audit_col = collection(db, "pricing_cost_audit")

    async def get_active_config(self) -> Dict[str, Any]:
        """Retrieve active pricing cost configuration or seed sensible defaults."""
        doc = await self.config_col.find_one({"_id": "active_cost_config"})
        if not doc:
            doc = {
                "_id": "active_cost_config",
                "harvesting_cost_paise": DEFAULT_HARVESTING_COST_PAISE,
                "sorting_cost_paise": DEFAULT_SORTING_COST_PAISE,
                "packaging_cost_paise": DEFAULT_PACKAGING_COST_PAISE,
                "transport_cost_paise": DEFAULT_TRANSPORT_COST_PAISE,
                "handling_cost_paise": DEFAULT_HANDLING_COST_PAISE,
                "wastage_allowance_bps": DEFAULT_WASTAGE_ALLOWANCE_BPS,
                "default_farmer_margin_bps": DEFAULT_FARMER_MARGIN_BPS,
                "crop_adjustments": DEFAULT_CROP_ADJUSTMENTS,
                "district_adjustments": DEFAULT_DISTRICT_ADJUSTMENTS,
                "version": 1,
                "updated_at": datetime.now(timezone.utc),
                "updated_by": "SYSTEM_DEFAULT",
            }
            try:
                await self.config_col.insert_one(doc)
            except Exception:
                pass
        doc["id"] = str(doc.get("_id", "active_cost_config"))
        return doc

    async def update_config(self, admin_id: str, updates: Dict[str, Any]) -> Dict[str, Any]:
        """Update cost model parameters with immutable audit logging."""
        current = await self.get_active_config()
        new_version = current.get("version", 1) + 1
        allowed_fields = [
            "harvesting_cost_paise",
            "sorting_cost_paise",
            "packaging_cost_paise",
            "transport_cost_paise",
            "handling_cost_paise",
            "wastage_allowance_bps",
            "default_farmer_margin_bps",
            "crop_adjustments",
            "district_adjustments",
        ]
        sanitized = {k: v for k, v in updates.items() if k in allowed_fields}
        sanitized["version"] = new_version
        sanitized["updated_at"] = datetime.now(timezone.utc)
        sanitized["updated_by"] = admin_id

        await self.config_col.update_one(
            {"_id": "active_cost_config"},
            {"$set": sanitized},
            upsert=True,
        )

        # Record audit log
        await self.audit_col.insert_one({
            "config_id": "active_cost_config",
            "version": new_version,
            "changed_by": admin_id,
            "changed_at": datetime.now(timezone.utc),
            "previous_values": {k: current.get(k) for k in sanitized if k in current},
            "new_values": sanitized,
        })

        return await self.get_active_config()

    async def get_audit_history(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Retrieve history of cost model modifications."""
        cursor = self.audit_col.find().sort("changed_at", -1).limit(limit)
        history = []
        async for doc in cursor:
            doc["id"] = str(doc.pop("_id"))
            history.append(doc)
        return history

    async def calculate_farmer_pricing(
        self,
        commodity: str,
        unit: str = "KG",
        district: Optional[str] = None,
        wholesale_price_per_kg_paise: int = 0,
        retail_price_per_kg_paise: Optional[int] = None,
        retail_source: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Calculate full farmer cost breakdown, minimum sustainable price,
        recommended price, and local retail sanity comparison.
        """
        config = await self.get_active_config()
        crop_adj = config.get("crop_adjustments", {}).get(commodity, {})
        if not crop_adj:
            # Case-insensitive lookup
            for c_name, c_vals in config.get("crop_adjustments", {}).items():
                if c_name.lower() == commodity.lower():
                    crop_adj = c_vals
                    break

        dist_adj = {}
        if district:
            dist_adj = config.get("district_adjustments", {}).get(district, {})
            if not dist_adj:
                for d_name, d_vals in config.get("district_adjustments", {}).items():
                    if d_name.lower() == district.lower():
                        dist_adj = d_vals
                        break

        # Base cost components
        harvesting = crop_adj.get("harvesting_cost_paise", config.get("harvesting_cost_paise", DEFAULT_HARVESTING_COST_PAISE))
        sorting = crop_adj.get("sorting_cost_paise", config.get("sorting_cost_paise", DEFAULT_SORTING_COST_PAISE))
        packaging = crop_adj.get("packaging_cost_paise", config.get("packaging_cost_paise", DEFAULT_PACKAGING_COST_PAISE))
        transport = dist_adj.get("transport_cost_paise", crop_adj.get("transport_cost_paise", config.get("transport_cost_paise", DEFAULT_TRANSPORT_COST_PAISE)))
        handling = crop_adj.get("handling_cost_paise", config.get("handling_cost_paise", DEFAULT_HANDLING_COST_PAISE))

        # Wastage allowance
        wastage_bps = crop_adj.get("wastage_allowance_bps", config.get("wastage_allowance_bps", DEFAULT_WASTAGE_ALLOWANCE_BPS))
        if wholesale_price_per_kg_paise > 0:
            wastage = max(100, int((Decimal(wholesale_price_per_kg_paise) * Decimal(wastage_bps) / Decimal(10000)).quantize(Decimal("1"), rounding=ROUND_HALF_UP)))
        else:
            wastage = 100  # Default ₹1.00 / KG minimum wastage allowance

        total_operating_cost = harvesting + sorting + packaging + transport + handling + wastage

        # Minimum Sustainable Price = Wholesale Reference + Operating Cost
        minimum_sustainable_price = wholesale_price_per_kg_paise + total_operating_cost

        # Farmer Margin (Fair profit)
        margin_bps = crop_adj.get("default_farmer_margin_bps", config.get("default_farmer_margin_bps", DEFAULT_FARMER_MARGIN_BPS))
        farmer_margin = max(300, int((Decimal(minimum_sustainable_price) * Decimal(margin_bps) / Decimal(10000)).quantize(Decimal("1"), rounding=ROUND_HALF_UP)))

        # Recommended Farmer Selling Price
        recommended_farmer_price = minimum_sustainable_price + farmer_margin

        # Local Retail Benchmark & Sanity Check
        suggested_above_retail = False
        review_notes = None
        if retail_price_per_kg_paise and retail_price_per_kg_paise > 0:
            # If recommended price is more than 25% higher than local retail price
            ceiling_check = int((Decimal(retail_price_per_kg_paise) * Decimal("1.25")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
            if recommended_farmer_price > ceiling_check:
                suggested_above_retail = True
                review_notes = (
                    f"Suggested price (₹{recommended_farmer_price/100:.2f}) exceeds local retail benchmark "
                    f"(₹{retail_price_per_kg_paise/100:.2f} at {retail_source or 'Uzhavar Sandhai'}) by over 25%. "
                    f"Recommended review to ensure competitive market positioning."
                )

        cost_breakdown = {
            "harvesting_cost_paise": harvesting,
            "harvesting_cost_display": format_rupees(harvesting),
            "sorting_cost_paise": sorting,
            "sorting_cost_display": format_rupees(sorting),
            "packaging_cost_paise": packaging,
            "packaging_cost_display": format_rupees(packaging),
            "transport_cost_paise": transport,
            "transport_cost_display": format_rupees(transport),
            "handling_cost_paise": handling,
            "handling_cost_display": format_rupees(handling),
            "wastage_allowance_paise": wastage,
            "wastage_allowance_display": format_rupees(wastage),
            "wastage_allowance_bps": wastage_bps,
            "total_operating_cost_paise": total_operating_cost,
            "total_operating_cost_display": format_rupees(total_operating_cost),
            "farmer_margin_paise": farmer_margin,
            "farmer_margin_display": format_rupees(farmer_margin),
            "farmer_margin_bps": margin_bps,
        }

        return {
            "commodity": commodity,
            "unit": unit,
            "district": district,
            "cost_breakdown": cost_breakdown,
            "wholesale_reference_price_paise": wholesale_price_per_kg_paise,
            "wholesale_reference_price_display": format_rupees(wholesale_price_per_kg_paise),
            "minimum_sustainable_price_paise": minimum_sustainable_price,
            "minimum_sustainable_price_display": format_rupees(minimum_sustainable_price),
            "recommended_farmer_price_paise": recommended_farmer_price,
            "recommended_farmer_price_display": format_rupees(recommended_farmer_price),
            "local_retail_comparison_paise": retail_price_per_kg_paise,
            "local_retail_comparison_display": format_rupees(retail_price_per_kg_paise) if retail_price_per_kg_paise else "Unavailable",
            "local_retail_source": retail_source or "Uzhavar Sandhai",
            "suggested_above_retail": suggested_above_retail,
            "review_notes": review_notes,
        }

