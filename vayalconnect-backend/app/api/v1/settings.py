"""
VayalConnect Backend — Settings Router

Public settings and configuration endpoints.
"""

from fastapi import APIRouter, Request
from app.schemas.common import APIResponse, QuantityUnit, QualityGrade, Language
from app.api.deps import get_request_id

router = APIRouter(prefix="/settings", tags=["Settings"])


@router.get("/languages")
async def get_languages(request: Request):
    """Available languages."""
    return APIResponse(
        success=True,
        data={
            "languages": [
                {"code": "en", "name": "English", "native": "English"},
                {"code": "ta", "name": "Tamil", "native": "தமிழ்"},
            ]
        },
        request_id=get_request_id(request),
    )


@router.get("/categories")
async def get_categories(request: Request):
    """Product categories."""
    return APIResponse(
        success=True,
        data={
            "categories": [
                "Vegetables", "Fruits", "Grains", "Pulses", "Spices",
                "Oil Seeds", "Cereals", "Flowers", "Dry Fruits",
                "Dairy", "Other",
            ]
        },
        request_id=get_request_id(request),
    )


@router.get("/units")
async def get_units(request: Request):
    """Available quantity units."""
    return APIResponse(
        success=True,
        data={
            "units": [u.value for u in QuantityUnit]
        },
        request_id=get_request_id(request),
    )


@router.get("/quality-grades")
async def get_quality_grades(request: Request):
    """Available quality grades."""
    return APIResponse(
        success=True,
        data={
            "grades": [g.value for g in QualityGrade]
        },
        request_id=get_request_id(request),
    )


@router.get("/app-release", response_model=APIResponse)
async def get_app_release(request: Request):
    """Latest mobile app release metadata for safe in-app updates."""
    import os
    return APIResponse(
        success=True,
        data={
            "app_id": "com.vayalconnect.app",
            "version_name": os.environ.get("LATEST_APP_VERSION_NAME", "1.1.0"),
            "version_code": int(os.environ.get("LATEST_APP_VERSION_CODE", "11")),
            "min_supported_version_code": 1,
            "apk_url": os.environ.get(
                "LATEST_APK_URL",
                "https://raw.githubusercontent.com/vayalconnect/vayalconnect-flutter/main/releases/v1.1.0-11/vayalconnect-release-1.1.0-11.apk",
            ),
            "sha256": os.environ.get(
                "LATEST_APK_SHA256",
                "",
            ),
            "release_notes_en": "• Fixed crop image upload with resilient fallback\n• Aligned interactive admin dashboard statistics\n• Enhanced farmer profile review & approval\n• Fresh lighter green UI theme\n• Safe in-app update checker and installer",
            "release_notes_ta": "• பயிர் புகைப்பட பதிவேற்றம் மேம்படுத்தப்பட்டது\n• நிர்வாகி புள்ளிவிவரங்கள் எளிதாக அணுகும் வசதி\n• விவசாயி விண்ணப்ப மறுஆய்வு & ஒப்புதல்\n• புதிய பசுமை வடிவமைப்பு\n• பாதுகாப்பான நேரடி புதுப்பிப்பு அமைப்பு",
            "mandatory": False,
            "release_date": "2026-10-26",
        },
        request_id=get_request_id(request),
    )
