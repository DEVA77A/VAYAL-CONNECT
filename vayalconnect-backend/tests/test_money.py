"""
Tests for money calculation utilities.
Verifies integer paise arithmetic, rounding, formatting, and consistency invariants.
"""

from decimal import Decimal
import pytest
from app.utils.money import (
    rupees_to_paise,
    paise_to_rupees,
    format_rupees,
    calculate_percentage,
    percentage_bps_to_display,
    validate_financial_consistency,
    safe_multiply,
)


def test_rupees_to_paise():
    assert rupees_to_paise(1) == 100
    assert rupees_to_paise(35.50) == 3550
    assert rupees_to_paise("35.50") == 3550
    assert rupees_to_paise(Decimal("100.99")) == 10099
    assert rupees_to_paise(0) == 0


def test_paise_to_rupees():
    assert paise_to_rupees(3550) == Decimal("35.50")
    assert paise_to_rupees(100) == Decimal("1.00")
    assert paise_to_rupees(0) == Decimal("0.00")


def test_format_rupees():
    assert format_rupees(3550) == "₹35.50"
    assert format_rupees(100000) == "₹1,000.00"
    assert format_rupees(225000) == "₹2,250.00"


def test_calculate_percentage():
    # 15% of 5000 paise = 750 paise
    assert calculate_percentage(5000, 1500) == 750
    # 70% of 10000 paise = 7000 paise
    assert calculate_percentage(10000, 7000) == 7000
    # 20% of 10000 paise = 2000 paise
    assert calculate_percentage(10000, 2000) == 2000
    # 0% of 5000 paise = 0 paise
    assert calculate_percentage(5000, 0) == 0


def test_percentage_bps_to_display():
    assert percentage_bps_to_display(1500) == "15%"
    assert percentage_bps_to_display(1050) == "10.5%"
    assert percentage_bps_to_display(2000) == "20%"


def test_validate_financial_consistency():
    # buyer_total == farmer_payout + commission
    assert validate_financial_consistency(10000, 8000, 2000) is True
    assert validate_financial_consistency(9000, 7000, 2000) is True
    assert validate_financial_consistency(10000, 8000, 1999) is False
    assert validate_financial_consistency(10000, 8001, 2000) is False


def test_safe_multiply():
    assert safe_multiply(500, 10) == 5000
    assert safe_multiply(0, 10) == 0
    with pytest.raises(ValueError):
        safe_multiply(-10, 5)
    with pytest.raises(ValueError):
        safe_multiply(10, -5)
