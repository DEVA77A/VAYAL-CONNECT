"""
VayalConnect Backend — Report Service

MongoDB aggregation-based reports for admin dashboard.
Uses pipelines — does NOT load thousands of documents into Python.
"""

from typing import Optional, Dict, Any, List
from datetime import datetime, timedelta, timezone, date
from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase
import math
import logging

from app.utils.money import format_rupees

logger = logging.getLogger(__name__)


class ReportService:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.db = db
        self.orders = db["orders"]
        self.payouts = db["payouts"]
        self.users = db["users"]

    async def get_dashboard_metrics(self) -> Dict[str, Any]:
        """Admin dashboard aggregate metrics."""
        # Order totals
        order_pipeline = [
            {"$match": {"order_status": {"$ne": "CANCELLED"}}},
            {"$group": {
                "_id": None,
                "total_orders": {"$sum": 1},
                "total_sales": {"$sum": "$buyer_total_paise"},
                "total_quantity": {"$sum": "$quantity"},
                "total_farmer_payout": {"$sum": "$farmer_total_payout_paise"},
                "total_commission": {"$sum": "$commission_total_paise"},
            }},
        ]
        order_result = await self.orders.aggregate(order_pipeline).to_list(1)
        order_data = order_result[0] if order_result else {}

        # Payout status counts
        payout_pipeline = [
            {"$group": {
                "_id": "$status",
                "count": {"$sum": 1},
            }},
        ]
        payout_results = await self.payouts.aggregate(payout_pipeline).to_list(10)
        payout_counts = {r["_id"]: r["count"] for r in payout_results}

        # Active users
        active_farmers = await self.users.count_documents({"role": "FARMER", "is_active": True})
        active_buyers = await self.users.count_documents({"role": "BUYER", "is_active": True})
        pending_approvals = await self.db["farmer_profiles"].count_documents({"approval_status": "PENDING"})

        total_sales = order_data.get("total_sales", 0)
        total_farmer = order_data.get("total_farmer_payout", 0)
        total_commission = order_data.get("total_commission", 0)

        return {
            "total_orders": order_data.get("total_orders", 0),
            "total_sales_paise": total_sales,
            "total_sales_display": format_rupees(total_sales),
            "total_quantity_sold": order_data.get("total_quantity", 0),
            "total_farmer_payout_paise": total_farmer,
            "total_farmer_payout_display": format_rupees(total_farmer),
            "total_platform_commission_paise": total_commission,
            "total_platform_commission_display": format_rupees(total_commission),
            "active_farmers": active_farmers,
            "active_buyers": active_buyers,
            "pending_payouts": payout_counts.get("PENDING_APPROVAL", 0) + payout_counts.get("APPROVED", 0),
            "completed_payouts": payout_counts.get("PAID", 0),
            "failed_payouts": payout_counts.get("FAILED", 0),
            "pending_farmer_approvals": pending_approvals,
        }

    async def get_order_report(
        self,
        period: Optional[str] = None,
        date_from: Optional[date] = None,
        date_to: Optional[date] = None,
        product_id: Optional[str] = None,
        farmer_id: Optional[str] = None,
        buyer_id: Optional[str] = None,
        order_status: Optional[str] = None,
        payout_status: Optional[str] = None,
        page: int = 1,
        limit: int = 50,
    ) -> Dict[str, Any]:
        """Generate order report with filters and aggregation."""
        match: Dict[str, Any] = {}

        # Date filtering
        date_filter = self._build_date_filter(period, date_from, date_to)
        if date_filter:
            match["created_at"] = date_filter

        # Entity filters
        if product_id and ObjectId.is_valid(product_id):
            match["product_id"] = ObjectId(product_id)
        if farmer_id and ObjectId.is_valid(farmer_id):
            match["farmer_id"] = ObjectId(farmer_id)
        if buyer_id and ObjectId.is_valid(buyer_id):
            match["buyer_id"] = ObjectId(buyer_id)
        if order_status:
            match["order_status"] = order_status
        if payout_status:
            match["payout_status"] = payout_status

        # Count total
        total = await self.orders.count_documents(match)
        pages = math.ceil(total / limit) if total > 0 else 1

        # Get paginated items
        cursor = self.orders.find(match).sort("created_at", -1).skip((page - 1) * limit).limit(limit)
        items = []
        async for doc in cursor:
            items.append(self._format_order_report_item(doc))

        # Summary aggregation
        summary_pipeline = [
            {"$match": match},
            {"$group": {
                "_id": None,
                "total_orders": {"$sum": 1},
                "total_quantity": {"$sum": "$quantity"},
                "total_buyer_amount": {"$sum": "$buyer_total_paise"},
                "total_farmer_payout": {"$sum": "$farmer_total_payout_paise"},
                "total_commission": {"$sum": "$commission_total_paise"},
            }},
        ]
        summary_result = await self.orders.aggregate(summary_pipeline).to_list(1)
        summary_data = summary_result[0] if summary_result else {}

        return {
            "items": items,
            "total": total,
            "page": page,
            "limit": limit,
            "pages": pages,
            "summary": {
                "total_orders": summary_data.get("total_orders", 0),
                "total_quantity": summary_data.get("total_quantity", 0),
                "total_buyer_amount_paise": summary_data.get("total_buyer_amount", 0),
                "total_buyer_amount_display": format_rupees(summary_data.get("total_buyer_amount", 0)),
                "total_farmer_payout_paise": summary_data.get("total_farmer_payout", 0),
                "total_farmer_payout_display": format_rupees(summary_data.get("total_farmer_payout", 0)),
                "total_commission_paise": summary_data.get("total_commission", 0),
                "total_commission_display": format_rupees(summary_data.get("total_commission", 0)),
            },
        }

    def _build_date_filter(
        self,
        period: Optional[str],
        date_from: Optional[date],
        date_to: Optional[date],
    ) -> Optional[Dict]:
        now = datetime.now(timezone.utc)
        today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

        if period == "today":
            return {"$gte": today_start}
        elif period == "yesterday":
            yesterday = today_start - timedelta(days=1)
            return {"$gte": yesterday, "$lt": today_start}
        elif period == "week":
            week_ago = today_start - timedelta(days=7)
            return {"$gte": week_ago}
        elif period == "month":
            month_ago = today_start - timedelta(days=30)
            return {"$gte": month_ago}
        elif date_from or date_to:
            f: Dict[str, Any] = {}
            if date_from:
                f["$gte"] = datetime.combine(date_from, datetime.min.time()).replace(tzinfo=timezone.utc)
            if date_to:
                f["$lte"] = datetime.combine(date_to, datetime.max.time()).replace(tzinfo=timezone.utc)
            return f if f else None
        return None

    def _format_order_report_item(self, doc: Dict) -> Dict[str, Any]:
        from app.utils.money import percentage_bps_to_display
        return {
            "order_id": str(doc["_id"]),
            "order_number": doc.get("order_number", ""),
            "product_name": doc.get("product_name", ""),
            "farmer_name": doc.get("farmer_name", ""),
            "buyer_name": doc.get("buyer_name", ""),
            "quantity": doc.get("quantity", 0),
            "unit": doc.get("quantity_unit", ""),
            "government_reference_price_paise": doc.get("government_reference_price_paise", 0),
            "government_reference_price_display": format_rupees(doc.get("government_reference_price_paise", 0)),
            "farmer_payout_per_unit_paise": doc.get("farmer_unit_payout_paise", 0),
            "farmer_total_payout_paise": doc.get("farmer_total_payout_paise", 0),
            "farmer_total_payout_display": format_rupees(doc.get("farmer_total_payout_paise", 0)),
            "buyer_price_per_unit_paise": doc.get("buyer_unit_price_paise", 0),
            "buyer_total_paise": doc.get("buyer_total_paise", 0),
            "buyer_total_display": format_rupees(doc.get("buyer_total_paise", 0)),
            "commission_percentage_bps": doc.get("commission_percentage_bps", 0),
            "commission_percentage_display": percentage_bps_to_display(doc.get("commission_percentage_bps", 0)),
            "commission_total_paise": doc.get("commission_total_paise", 0),
            "commission_total_display": format_rupees(doc.get("commission_total_paise", 0)),
            "order_status": doc.get("order_status", ""),
            "payment_status": doc.get("payment_status", ""),
            "payout_status": doc.get("payout_status", ""),
            "created_at": doc.get("created_at"),
        }
