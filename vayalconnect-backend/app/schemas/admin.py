"""
VayalConnect Backend — Admin & Report Schemas
"""

from typing import Optional, List
from pydantic import BaseModel, Field, ConfigDict
from datetime import datetime, date


class AdminDashboardResponse(BaseModel):
    """Admin dashboard metrics."""
    total_orders: int = 0
    total_sales_paise: int = 0
    total_sales_display: str = "₹0.00"
    total_quantity_sold: int = 0
    total_farmer_payout_paise: int = 0
    total_farmer_payout_display: str = "₹0.00"
    total_platform_commission_paise: int = 0
    total_platform_commission_display: str = "₹0.00"
    active_farmers: int = 0
    active_buyers: int = 0
    pending_payouts: int = 0
    completed_payouts: int = 0
    failed_payouts: int = 0
    pending_farmer_approvals: int = 0


class ReportQueryParams(BaseModel):
    """Report filter parameters."""
    period: Optional[str] = None  # today, yesterday, week, month
    date_from: Optional[date] = None
    date_to: Optional[date] = None
    product_id: Optional[str] = None
    farmer_id: Optional[str] = None
    buyer_id: Optional[str] = None
    order_status: Optional[str] = None
    payout_status: Optional[str] = None
    page: int = 1
    limit: int = 50


class OrderReportItem(BaseModel):
    """Single order in admin report."""
    order_id: str
    order_number: str
    product_name: str
    farmer_name: str
    buyer_name: str
    quantity: int
    unit: str
    government_reference_price_paise: int
    government_reference_price_display: str
    farmer_payout_per_unit_paise: int
    farmer_total_payout_paise: int
    farmer_total_payout_display: str
    buyer_price_per_unit_paise: int
    buyer_total_paise: int
    buyer_total_display: str
    commission_percentage_bps: int
    commission_percentage_display: str
    commission_total_paise: int
    commission_total_display: str
    order_status: str
    payment_status: str
    payout_status: str
    created_at: Optional[datetime] = None


class OrderReportResponse(BaseModel):
    """Admin order report."""
    items: List[OrderReportItem]
    total: int
    page: int
    limit: int
    pages: int
    summary: "ReportSummary"


class ReportSummary(BaseModel):
    """Aggregated report summary."""
    total_orders: int = 0
    total_quantity: int = 0
    total_buyer_amount_paise: int = 0
    total_buyer_amount_display: str = "₹0.00"
    total_farmer_payout_paise: int = 0
    total_farmer_payout_display: str = "₹0.00"
    total_commission_paise: int = 0
    total_commission_display: str = "₹0.00"


class RevenueReportResponse(BaseModel):
    """Revenue summary report."""
    period: str
    total_revenue_paise: int = 0
    total_revenue_display: str = "₹0.00"
    total_commission_paise: int = 0
    total_commission_display: str = "₹0.00"
    total_farmer_payouts_paise: int = 0
    total_farmer_payouts_display: str = "₹0.00"
    total_orders: int = 0
    average_order_value_paise: int = 0
    average_order_value_display: str = "₹0.00"


class FarmerApproveRequest(BaseModel):
    """Approve a farmer account."""
    model_config = ConfigDict(extra="forbid")
    application_revision: int = Field(0, ge=0, strict=True)


class FarmerRejectRequest(BaseModel):
    """Reject a farmer account."""
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    reason: str = Field(..., min_length=1, max_length=500)
    application_revision: int = Field(0, ge=0, strict=True)


class AdminUserListItem(BaseModel):
    """User list item for admin."""
    id: str
    name: str
    email: str
    phone: str
    role: Optional[str] = None
    is_active: bool
    email_verified: bool
    created_at: Optional[datetime] = None
