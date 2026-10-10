"""
VayalConnect Backend — Shared Schema Enums and Base Models

Common enumerations and base response structures used across all schemas.
"""

from enum import Enum
from typing import Optional, Any, Generic, TypeVar, List
from pydantic import BaseModel, Field
from datetime import datetime


# ============================================================
# Enumerations
# ============================================================

class UserRole(str, Enum):
    FARMER = "FARMER"
    BUYER = "BUYER"
    ADMIN = "ADMIN"


class Gender(str, Enum):
    MALE = "male"
    FEMALE = "female"
    OTHER = "other"


class Language(str, Enum):
    ENGLISH = "en"
    TAMIL = "ta"


class QuantityUnit(str, Enum):
    KG = "KG"
    QUINTAL = "QUINTAL"
    TON = "TON"
    PIECE = "PIECE"
    DOZEN = "DOZEN"


class QualityGrade(str, Enum):
    PREMIUM = "PREMIUM"
    A = "A"
    B = "B"
    C = "C"


class ProductStatus(str, Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    OUT_OF_STOCK = "OUT_OF_STOCK"
    SUSPENDED = "SUSPENDED"


class OrderStatus(str, Enum):
    PENDING_PAYMENT = "PENDING_PAYMENT"
    PAID = "PAID"
    CONFIRMED = "CONFIRMED"
    PROCESSING = "PROCESSING"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"
    REFUNDED = "REFUNDED"


class PaymentStatus(str, Enum):
    PENDING = "PENDING"
    CREATED = "CREATED"
    AUTHORIZED = "AUTHORIZED"
    CAPTURED = "CAPTURED"
    FAILED = "FAILED"
    REFUNDED = "REFUNDED"


class PayoutStatus(str, Enum):
    NOT_INITIATED = "NOT_INITIATED"
    PENDING_APPROVAL = "PENDING_APPROVAL"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"
    PROCESSING = "PROCESSING"
    PAID = "PAID"
    FAILED = "FAILED"


class FarmerApprovalStatus(str, Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class CommissionConfigStatus(str, Enum):
    ACTIVE = "ACTIVE"
    SUPERSEDED = "SUPERSEDED"


class OTPPurpose(str, Enum):
    REGISTRATION = "REGISTRATION"
    PASSWORD_RESET = "PASSWORD_RESET"


# ============================================================
# Order Status Transitions (State Machine)
# ============================================================

VALID_ORDER_TRANSITIONS = {
    OrderStatus.PENDING_PAYMENT: [OrderStatus.PAID, OrderStatus.CANCELLED],
    OrderStatus.PAID: [OrderStatus.CONFIRMED, OrderStatus.REFUNDED],
    OrderStatus.CONFIRMED: [OrderStatus.PROCESSING, OrderStatus.CANCELLED],
    OrderStatus.PROCESSING: [OrderStatus.COMPLETED, OrderStatus.CANCELLED],
    OrderStatus.COMPLETED: [],  # Terminal state
    OrderStatus.CANCELLED: [],  # Terminal state
    OrderStatus.REFUNDED: [],  # Terminal state
}

VALID_PAYOUT_TRANSITIONS = {
    PayoutStatus.PENDING_APPROVAL: [PayoutStatus.APPROVED, PayoutStatus.REJECTED],
    PayoutStatus.APPROVED: [PayoutStatus.PROCESSING],
    PayoutStatus.REJECTED: [],  # Terminal
    PayoutStatus.PROCESSING: [PayoutStatus.PAID, PayoutStatus.FAILED],
    PayoutStatus.PAID: [],  # Terminal
    PayoutStatus.FAILED: [PayoutStatus.PROCESSING],  # Can retry
}


# ============================================================
# Base Response Models
# ============================================================

class ErrorDetail(BaseModel):
    code: str
    message: str


class APIResponse(BaseModel):
    """Standard API response wrapper."""
    success: bool = True
    data: Optional[Any] = None
    error: Optional[ErrorDetail] = None
    request_id: Optional[str] = None


T = TypeVar("T")


class PaginatedResponse(BaseModel):
    """Paginated response wrapper."""
    items: List[Any]
    total: int
    page: int
    limit: int
    pages: int
