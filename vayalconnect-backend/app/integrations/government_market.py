"""
VayalConnect Backend — Government Market Price Integration

Fetches agricultural commodity prices from the official data.gov.in API.
Dataset: "Current Daily Price of Various Commodities from Various Markets (Mandi)"
Resource ID: 9ef84268-d588-465a-a308-a864a43d0070
Source: AGMARKNET, Ministry of Agriculture & Farmers Welfare

IMPORTANT:
- Never invent or estimate Government prices.
- If API is unavailable, return explicit unavailability.
- Never generate fake prices.
"""

from abc import ABC, abstractmethod
from typing import Optional, Dict, Any, List
from datetime import datetime, timezone
import httpx
import logging

from app.core.config import settings
from app.utils.money import rupees_to_paise

logger = logging.getLogger(__name__)


class MarketPriceProvider(ABC):
    """Abstract market price provider. Allows swapping implementations."""

    @abstractmethod
    async def get_market_price(
        self,
        commodity: str,
        market: Optional[str] = None,
        state: Optional[str] = None,
        district: Optional[str] = None,
    ) -> Optional[Dict[str, Any]]:
        """
        Retrieve the latest market price for a commodity.
        Returns None if unavailable.
        """
        pass

    @abstractmethod
    async def search_prices(
        self,
        commodity: Optional[str] = None,
        market: Optional[str] = None,
        state: Optional[str] = None,
        district: Optional[str] = None,
        limit: int = 20,
        offset: int = 0,
    ) -> Dict[str, Any]:
        """Search for market prices matching criteria."""
        pass


class GovernmentMarketPriceProvider(MarketPriceProvider):
    """
    Official Government of India data.gov.in AGMARKNET API provider.

    API Endpoint: https://api.data.gov.in/resource/9ef84268-d588-465a-a308-a864a43d0070
    Dataset: "Current Daily Price of Various Commodities from Various Markets (Mandi)"

    Parameters:
      - api-key: required
      - format: json
      - filters[commodity]: commodity name
      - filters[market]: market name
      - filters[state]: state name
      - filters[district]: district name
      - limit: number of records
      - offset: pagination offset
    """

    def __init__(self):
        self.api_key = settings.GOVERNMENT_MARKET_API_KEY
        self.base_url = settings.GOVERNMENT_MARKET_API_BASE_URL
        self._configured = bool(self.api_key)

        if not self._configured:
            logger.warning(
                "Government Market API key not configured. "
                "Market price lookups will return unavailable."
            )

    @property
    def is_configured(self) -> bool:
        """Check if provider has a configured API key."""
        return bool(self.api_key and self.api_key.strip())

    async def get_market_price(
        self,
        commodity: str,
        market: Optional[str] = None,
        state: Optional[str] = None,
        district: Optional[str] = None,
    ) -> Optional[Dict[str, Any]]:
        """
        Fetch the latest market price for a single commodity.
        Returns normalized price dict or None if unavailable.
        """
        if not self.is_configured:
            logger.warning("Government Market API key not configured")
            return None

        result = await self.search_prices(
            commodity=commodity,
            market=market,
            state=state,
            district=district,
            limit=5,
            offset=0,
        )

        records = result.get("records", [])
        if not records:
            return None

        return records[0]

    async def search_prices(
        self,
        commodity: Optional[str] = None,
        market: Optional[str] = None,
        state: Optional[str] = None,
        district: Optional[str] = None,
        limit: int = 20,
        offset: int = 0,
    ) -> Dict[str, Any]:
        """
        Search for market prices matching criteria against data.gov.in AGMARKNET.
        Returns a dict with records, total count, live status, and message.
        """
        if not self.is_configured:
            return {
                "records": [],
                "count": 0,
                "total": 0,
                "live": False,
                "message": "Government Market API key not configured in environment.",
            }

        params: Dict[str, Any] = {
            "api-key": self.api_key,
            "format": "json",
            "limit": min(max(1, limit), 100),
            "offset": max(0, offset),
        }

        if commodity and commodity.strip():
            params["filters[commodity]"] = commodity.strip().title()
        if state and state.strip():
            params["filters[state]"] = state.strip().title()
        if district and district.strip():
            params["filters[district]"] = district.strip().title()
        if market and market.strip():
            params["filters[market]"] = market.strip().title()

        try:
            # Connect with a reasonable timeout; never log or expose self.api_key
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(self.base_url, params=params)
                response.raise_for_status()
                data = response.json()

            # Validate response schema
            if not isinstance(data, dict):
                logger.error("Government Market API returned non-dict JSON response")
                return {
                    "records": [],
                    "count": 0,
                    "total": 0,
                    "live": False,
                    "message": "Government Market API returned an unexpected response format.",
                }

            raw_records = data.get("records", [])
            total = int(data.get("total", len(raw_records)))

            normalized_records = [
                self._normalize_record(r) for r in raw_records if isinstance(r, dict)
            ]
            # Filter out records where commodity or prices are completely absent
            valid_records = [
                r for r in normalized_records if r["commodity"] and r["modal_price_paise"] > 0
            ]

            return {
                "records": valid_records,
                "count": len(valid_records),
                "total": total,
                "live": True,
                "message": "Live government mandi rates retrieved successfully.",
            }

        except httpx.ConnectError:
            logger.warning("Government Market API server connection refused or host unreachable.")
            return {
                "records": [],
                "count": 0,
                "total": 0,
                "live": False,
                "message": "Government market API server is currently unreachable.",
            }
        except httpx.TimeoutException:
            logger.warning("Government Market API request timed out.")
            return {
                "records": [],
                "count": 0,
                "total": 0,
                "live": False,
                "message": "Government market API request timed out.",
            }
        except httpx.HTTPStatusError as e:
            logger.warning(f"Government Market API returned HTTP error: {e.response.status_code}")
            return {
                "records": [],
                "count": 0,
                "total": 0,
                "live": False,
                "message": f"Government market API returned HTTP {e.response.status_code}.",
            }
        except Exception as e:
            logger.warning(f"Government Market API error: {type(e).__name__}")
            return {
                "records": [],
                "count": 0,
                "total": 0,
                "live": False,
                "message": f"Error communicating with government market API: {type(e).__name__}.",
            }

    def _normalize_record(self, record: Dict[str, Any]) -> Dict[str, Any]:
        """
        Normalize a raw Government AGMARKNET record to our standardized schema.
        Handles diverse case formats, XML-escaped space keys, date parsing,
        and currency/unit conversions.
        """
        # Case-insensitive / variation-tolerant lookup
        commodity = (
            self._get_val(record, "commodity", "Commodity") or ""
        ).strip()
        state = (
            self._get_val(record, "state", "State") or ""
        ).strip()
        district = (
            self._get_val(record, "district", "District") or ""
        ).strip()
        market = (
            self._get_val(record, "market", "Market", "Mandi") or ""
        ).strip()
        variety = (
            self._get_val(record, "variety", "Variety") or "Common"
        ).strip()
        grade = (
            self._get_val(record, "grade", "Grade") or "FAQ"
        ).strip()

        # Parse arrival date (DD/MM/YYYY, YYYY-MM-DD, DD-MM-YYYY)
        raw_date = str(
            self._get_val(record, "arrival_date", "Arrival_Date", "arrivaldate") or ""
        ).strip()
        arrival_date = self._parse_date(raw_date)

        # Parse prices in ₹ / Quintal
        min_price = self._parse_price(
            self._get_val(
                record,
                "min_price",
                "Min_Price",
                "Min_x0020_Price",
                "min_price_rs",
            )
        )
        max_price = self._parse_price(
            self._get_val(
                record,
                "max_price",
                "Max_Price",
                "Max_x0020_Price",
                "max_price_rs",
            )
        )
        modal_price = self._parse_price(
            self._get_val(
                record,
                "modal_price",
                "Modal_Price",
                "Modal_x0020_Price",
                "modal_price_rs",
            )
        )

        # A missing modal price is unavailable; never estimate an official rate.

        # Unit in AGMARKNET is always Quintal (1 Quintal = 100 kg)
        unit = "Quintal"
        min_price_paise = rupees_to_paise(min_price) if min_price > 0 else 0
        max_price_paise = rupees_to_paise(max_price) if max_price > 0 else 0
        modal_price_paise = rupees_to_paise(modal_price) if modal_price > 0 else 0

        # Calculate per-kilogram rate
        price_per_kg_rupees = round(modal_price / 100.0, 2) if modal_price > 0 else 0.0
        price_per_kg_paise = round(modal_price_paise / 100) if modal_price_paise > 0 else 0

        # Unique deterministic price ID for tracking
        date_str = arrival_date.isoformat() if arrival_date else "unknown"
        safe_comm = commodity.lower().replace(" ", "_").replace("(", "").replace(")", "")
        safe_mkt = market.lower().replace(" ", "_")
        price_id = f"mp_{safe_comm}_{safe_mkt}_{date_str}"

        return {
            "price_id": price_id,
            "commodity": commodity,
            "market": market,
            "state": state,
            "district": district,
            "variety": variety,
            "grade": grade,
            "min_price_paise": min_price_paise,
            "max_price_paise": max_price_paise,
            "modal_price_paise": modal_price_paise,
            "modal_price_verified": modal_price_paise > 0,
            "min_price_display": f"₹{min_price:,.2f}",
            "max_price_display": f"₹{max_price:,.2f}",
            "modal_price_display": f"₹{modal_price:,.2f}",
            "price_per_kg_paise": price_per_kg_paise,
            "price_per_kg_display": f"₹{price_per_kg_rupees:,.2f} / kg",
            "unit": unit,
            "arrival_date": arrival_date,
            "source": "data.gov.in AGMARKNET",
            "retrieved_at": datetime.now(timezone.utc),
        }

    def _get_val(self, record: Dict[str, Any], *candidate_keys: str) -> Any:
        """Helper to find key by exact name or normalized name."""
        for key in candidate_keys:
            if key in record and record[key] is not None:
                return record[key]

        # Normalized lookup map: lowercase without underscores or spaces
        norm_map = {
            k.lower().replace("_x0020_", "").replace("_", "").replace(" ", ""): v
            for k, v in record.items()
        }
        for key in candidate_keys:
            clean = key.lower().replace("_x0020_", "").replace("_", "").replace(" ", "")
            if clean in norm_map and norm_map[clean] is not None:
                return norm_map[clean]
        return None

    def _parse_date(self, raw_date: str) -> Optional[datetime.date]:
        """Safely parse various date formats."""
        if not raw_date:
            return None
        for fmt in ("%d/%m/%Y", "%Y-%m-%d", "%d-%m-%Y", "%d/%m/%y", "%d-%b-%Y"):
            try:
                return datetime.strptime(raw_date, fmt).date()
            except ValueError:
                continue
        return None

    def _parse_price(self, value: Any) -> float:
        """Safely parse a price value to float."""
        if value is None:
            return 0.0
        try:
            cleaned = str(value).replace(",", "").replace("₹", "").strip()
            return max(0.0, float(cleaned))
        except (ValueError, TypeError):
            return 0.0


# Singleton provider
market_price_provider = GovernmentMarketPriceProvider()
