"""The same requirements govern review, publishing and checkout eligibility."""
from app.schemas.farmer import FarmerApplicationRequest, FarmerBankDetailsRequest
from app.core.security import decrypt_value


def missing_farmer_fields(profile):
    missing = []
    try:
        data = FarmerApplicationRequest.model_validate(profile.get("application") or {})
        if data.coordinates is None:
            missing.append("farm_coordinates")
    except Exception:
        missing.append("farm_application")
    try:
        FarmerBankDetailsRequest(account_holder_name=decrypt_value(profile.get("bank_account_holder_name", "")),
            bank_name=decrypt_value(profile.get("bank_name", "")),
            account_number=decrypt_value(profile.get("bank_account_number", "")),
            ifsc=decrypt_value(profile.get("bank_ifsc", "")))
    except Exception:
        missing.append("bank_payout_details")
    return missing
