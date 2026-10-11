"""
Security and IDOR (Insecure Direct Object Reference) Prevention Tests.
Verifies that:
1. Bank details are never exposed to buyers or other farmers.
2. Buyer cannot see farmer payout or platform commission in product responses.
3. Farmer cannot see buyer final price or platform commission in their product responses.
4. Farmer cannot access another farmer's bank details or payouts.
"""

import pytest
from app.schemas.product import BuyerProductResponse, FarmerProductResponse, AdminProductResponse
from app.utils.money import format_rupees


def test_buyer_breakdown_is_public_but_bank_and_internal_policy_are_private():
    """Verify that BuyerProductResponse does NOT have payout or commission fields."""
    buyer_resp = BuyerProductResponse(
        product_id="prod_123",
        product_name="Ponni Rice",
        category="Grains",
        quantity_available=50,
        quantity_unit="KG",
        quality_grade="A",
        location="Thanjavur",
        buyer_price_per_unit_paise=4500,
        buyer_price_per_unit_display="₹45.00",
    )
    dumped = buyer_resp.model_dump()

    # Buyer sees retail price
    assert dumped["buyer_price_per_unit_paise"] == 4500
    assert dumped["buyer_price_per_unit_display"] == "₹45.00"

    assert "bank_account_number" not in dumped
    assert "pricing_policy_id" not in dumped
    # Public commission is transparent; bank and internal policy remain private
    assert "farmer_payout_per_unit_paise" not in dumped
    assert "farmer_payout_per_unit_display" not in dumped
    assert "commission_percentage_bps" in dumped
    assert "commission_per_unit_paise" in dumped
    assert "government_reference_price_paise" not in dumped


def test_farmer_product_response_contains_no_retail_or_commission_margins():
    """Verify that FarmerProductResponse does NOT have buyer retail price or commission fields."""
    farmer_resp = FarmerProductResponse(
        product_id="prod_123",
        product_name="Ponni Rice",
        category="Grains",
        quantity_available=50,
        quantity_unit="KG",
        quality_grade="A",
        location="Thanjavur",
        market="Thanjavur",
        farmer_payout_per_unit_paise=3500,
        farmer_payout_per_unit_display="₹35.00",
        status="ACTIVE",
    )
    dumped = farmer_resp.model_dump()

    # Farmer sees their guaranteed payout
    assert dumped["farmer_payout_per_unit_paise"] == 3500
    assert dumped["farmer_payout_per_unit_display"] == "₹35.00"

    # CRITICAL: Farmer schema must NOT contain buyer retail price or commission
    assert "buyer_price_per_unit_paise" not in dumped
    assert "buyer_price_per_unit_display" not in dumped
    assert "commission_percentage_bps" not in dumped
    assert "commission_per_unit_paise" not in dumped
    assert "government_reference_price_paise" not in dumped


def test_admin_product_response_contains_complete_financial_breakdown():
    """Verify that AdminProductResponse contains all audited numbers."""
    admin_resp = AdminProductResponse(
        product_id="prod_123",
        product_name="Ponni Rice",
        category="Grains",
        farmer_id="farmer_456",
        farmer_name="Ramasamy",
        quantity_available=50,
        quantity_unit="KG",
        quality_grade="A",
        location="Thanjavur",
        market="Thanjavur",
        government_reference_price_paise=5000,
        government_reference_price_display="₹50.00",
        farmer_payout_per_unit_paise=3500,
        farmer_payout_per_unit_display="₹35.00",
        buyer_price_per_unit_paise=4500,
        buyer_price_per_unit_display="₹45.00",
        commission_percentage_bps=2000,
        commission_percentage_display="20%",
        commission_per_unit_paise=1000,
        commission_per_unit_display="₹10.00",
        status="ACTIVE",
    )
    dumped = admin_resp.model_dump()

    assert dumped["government_reference_price_paise"] == 5000
    assert dumped["farmer_payout_per_unit_paise"] == 3500
    assert dumped["buyer_price_per_unit_paise"] == 4500
    assert dumped["commission_per_unit_paise"] == 1000
