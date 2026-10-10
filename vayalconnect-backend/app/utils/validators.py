"""
VayalConnect Backend — Input Validators

Prevent MongoDB injection and validate common patterns.
"""

import re
from typing import Any


# Patterns
EMAIL_REGEX = re.compile(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")
PHONE_REGEX = re.compile(r"^\+?[1-9]\d{9,14}$")
IFSC_REGEX = re.compile(r"^[A-Z]{4}0[A-Z0-9]{6}$")
UPI_REGEX = re.compile(r"^[\w.\-]+@[\w]+$")


def is_valid_email(email: str) -> bool:
    """Validate email format."""
    return bool(EMAIL_REGEX.match(email))


def is_valid_phone(phone: str) -> bool:
    """Validate phone number format."""
    return bool(PHONE_REGEX.match(phone))


def is_valid_ifsc(ifsc: str) -> bool:
    """Validate Indian IFSC code format."""
    return bool(IFSC_REGEX.match(ifsc.upper()))


def is_valid_upi(upi_id: str) -> bool:
    """Validate UPI ID format."""
    return bool(UPI_REGEX.match(upi_id))


def sanitize_mongo_input(value: Any) -> Any:
    """
    Prevent MongoDB injection by rejecting inputs containing $ operators.
    This applies to dict keys that start with $ — a common injection vector.
    """
    if isinstance(value, dict):
        for key in value:
            if isinstance(key, str) and key.startswith("$"):
                raise ValueError(f"Invalid input: MongoDB operator '{key}' not allowed")
            sanitize_mongo_input(value[key])
    elif isinstance(value, list):
        for item in value:
            sanitize_mongo_input(item)
    return value


def validate_positive_integer(value: int, field_name: str) -> int:
    """Ensure a value is a positive integer."""
    if not isinstance(value, int) or value <= 0:
        raise ValueError(f"{field_name} must be a positive integer")
    return value


def validate_quantity(quantity: int) -> int:
    """Validate product quantity."""
    if quantity <= 0:
        raise ValueError("Quantity must be greater than zero")
    if quantity > 1_000_000:
        raise ValueError("Quantity exceeds maximum allowed")
    return quantity
