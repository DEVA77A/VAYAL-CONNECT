"""
VayalConnect Backend — Money Utilities

All financial calculations use integer paise (1 INR = 100 paise).
Intermediate calculations use Python Decimal for precision.
NEVER use float for money.
"""

from decimal import Decimal, ROUND_HALF_UP, InvalidOperation
from typing import Union


# 1 INR = 100 paise
PAISE_PER_RUPEE = 100

# Basis points: 1% = 100 bps, so 15% = 1500 bps
BPS_PER_PERCENT = 100


def rupees_to_paise(rupees: Union[str, int, float, Decimal]) -> int:
    """
    Convert rupee amount to paise (integer).
    ₹35.50 → 3550 paise

    Uses Decimal for precision; input can be string/int/float.
    """
    d = Decimal(str(rupees))
    paise = d * PAISE_PER_RUPEE
    return int(paise.to_integral_value(rounding=ROUND_HALF_UP))


def paise_to_rupees(paise: int) -> Decimal:
    """
    Convert paise to rupee Decimal.
    3550 paise → Decimal('35.50')
    """
    return Decimal(paise) / Decimal(PAISE_PER_RUPEE)


def format_rupees(paise: int) -> str:
    """
    Format paise as Indian Rupee display string.
    3550 → '₹35.50'
    225000 → '₹2,250.00'
    """
    rupees = paise_to_rupees(paise)
    # Format with Indian locale style (simplified)
    formatted = f"{rupees:,.2f}"
    return f"₹{formatted}"


def calculate_percentage(amount_paise: int, percentage_bps: int) -> int:
    """
    Calculate a percentage of an amount.
    Both input and output in paise.
    Percentage in basis points (1500 bps = 15%).

    Example: calculate_percentage(5000, 1500) → 750 paise (15% of ₹50)
    """
    amount = Decimal(amount_paise)
    pct = Decimal(percentage_bps) / Decimal(10000)  # bps to decimal
    result = amount * pct
    return int(result.to_integral_value(rounding=ROUND_HALF_UP))


def percentage_bps_to_display(bps: int) -> str:
    """
    Convert basis points to display percentage.
    1500 → '15%'
    1050 → '10.5%'
    2000 → '20%'
    """
    pct = Decimal(bps) / Decimal(BPS_PER_PERCENT)
    if pct == pct.to_integral():
        return f"{int(pct)}%"
    # Normalize removes trailing zeros only from fractional part
    return f"{pct.normalize():f}%"


def validate_financial_consistency(
    buyer_total_paise: int,
    farmer_total_payout_paise: int,
    commission_total_paise: int,
) -> bool:
    """
    Validate the core financial invariant:
    buyer_total == farmer_payout + commission

    Returns True if consistent, False otherwise.
    """
    return buyer_total_paise == (farmer_total_payout_paise + commission_total_paise)


def safe_multiply(unit_price_paise: int, quantity: int) -> int:
    """
    Safely multiply unit price by quantity.
    Both must be non-negative integers.
    """
    if unit_price_paise < 0 or quantity < 0:
        raise ValueError("Unit price and quantity must be non-negative")
    return unit_price_paise * quantity
