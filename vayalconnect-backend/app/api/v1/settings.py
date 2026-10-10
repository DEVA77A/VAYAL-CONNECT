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
