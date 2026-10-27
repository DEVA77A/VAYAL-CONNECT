"""Actual compressed crop photographs stored in MongoDB, not ephemeral Render disk."""
import asyncio
from io import BytesIO
from typing import Optional
from bson import ObjectId, Binary
from fastapi import APIRouter, Depends, UploadFile, File, Form, Request
from fastapi.responses import Response
from app.api.deps import get_approved_farmer, get_optional_current_user, get_request_id
from app.core.database import get_database
from app.core.exceptions import ValidationError, NotFoundError
from app.schemas.common import APIResponse
from app.repositories.products import ProductRepository
from app.services.image_validator import CropImageValidator, resolve_crop_names

router = APIRouter(prefix="/media", tags=["Crop images"])


def compress_image(raw: bytes) -> bytes:
    from PIL import Image, ImageOps
    try:
        Image.MAX_IMAGE_PIXELS = 20_000_000
        with Image.open(BytesIO(raw)) as original:
            if original.width * original.height > 20_000_000:
                raise ValueError("Image dimensions exceed limit")
            image = ImageOps.exif_transpose(original).convert("RGB")
            image.thumbnail((1600, 1600))
            output = BytesIO()
            image.save(output, format="JPEG", quality=82, optimize=True)
            return output.getvalue()
    except Exception:
        raise ValidationError("Upload a valid crop photograph, at most 5 MB and 20 megapixels. / செல்லுபடியாகும் பயிர் புகைப்படத்தைப் பதிவேற்றவும்.") from None


@router.post("", response_model=APIResponse, status_code=201)
async def upload_image(
    request: Request,
    file: UploadFile = File(...),
    crop_name: Optional[str] = Form(None),
    user=Depends(get_approved_farmer),
    db=Depends(get_database),
):
    raw = await file.read(5_000_001)
    await file.close()
    if len(raw) > 5_000_000:
        raise ValidationError("Crop photograph must be at most 5 MB. / பயிரின் படம் அதிகபட்சமாக 5 MB வரை மட்டுமே இருக்க வேண்டும்.")
    
    # Technical validation of image content (format, dimensions, non-blank, non-corrupt)
    validation = CropImageValidator.validate_image_bytes(raw, crop_name.strip() if crop_name else "")
    if not validation.is_valid:
        raise ValidationError(validation.combined_message)
    is_validated = True
    ai_verified = False
    validation_category = validation.detected_category

    data = await asyncio.to_thread(compress_image, raw)
    doc = {
        "farmer_id": ObjectId(user["id"]),
        "data": Binary(data),
        "content_type": "image/jpeg",
        "crop_name": crop_name.strip() if crop_name else None,
        "validated": is_validated,
        "ai_verified": ai_verified,
        "validation_category": validation_category,
    }
    result = await db.crop_images.insert_one(doc)
    return APIResponse(
        data={
            "image_url": "/api/v1/media/" + str(result.inserted_id),
            "validated": is_validated,
            "ai_verified": ai_verified,
            "validation_category": validation_category,
        },
        request_id=get_request_id(request),
    )


@router.get("/{image_id}")
async def read_image(
    image_id: str,
    user: Optional[dict] = Depends(get_optional_current_user),
    db=Depends(get_database),
):
    if not ObjectId.is_valid(image_id):
        raise NotFoundError("Image")
    doc = await db.crop_images.find_one({"_id": ObjectId(image_id)})
    if not doc:
        raise NotFoundError("Image")

    # If image is attached to an existing product or order, it is public product imagery
    is_published = await db.products.find_one({"image_url": "/api/v1/media/" + image_id}, {"_id": 1})
    if not is_published:
        is_published = await db.orders.find_one({"items.image_url": "/api/v1/media/" + image_id}, {"_id": 1})

    if is_published:
        return Response(
            content=bytes(doc["data"]),
            media_type="image/jpeg",
            headers={"Cache-Control": "public, max-age=86400", "X-Content-Type-Options": "nosniff"},
        )

    # Otherwise, this is an unattached draft image — restrict to owner or admin
    if not user:
        raise NotFoundError("Image")
    if user.get("role") != "ADMIN" and str(doc["farmer_id"]) != user.get("id"):
        raise NotFoundError("Image")

    return Response(
        content=bytes(doc["data"]),
        media_type="image/jpeg",
        headers={"Cache-Control": "private, max-age=300", "X-Content-Type-Options": "nosniff"},
    )


async def validate_owned_image(db, image_url: Optional[str], farmer_id: str, product_name: Optional[str] = None):
    """
    Ensure the image URL is provided, belongs to the farmer, and has passed AI crop validation.
    """
    if not image_url or not str(image_url).strip():
        raise ValidationError("Crop photograph is required to publish a listing. / பயிரின் படம் கட்டாயம் தேவை.")

    prefix = "/api/v1/media/"
    raw_url = str(image_url).strip()
    if not raw_url.startswith(prefix) or not ObjectId.is_valid(raw_url[len(prefix):]):
        raise ValidationError("Upload a crop photograph using the authenticated upload endpoint. / சரியான புகைப்பட பதிவேற்ற முகவரியைப் பயன்படுத்தவும்.")

    image = await db.crop_images.find_one({"_id": ObjectId(raw_url[len(prefix):]), "farmer_id": ObjectId(farmer_id)})
    if not image:
        raise ValidationError("Crop photograph must belong to the authenticated farmer. / பயிரின் புகைப்படம் அங்கீகரிக்கப்பட்ட விவசாயிக்கு சொந்தமானதாக இருக்க வேண்டும்.")

    # Ensure image content has passed technical validation
    if not image.get("validated"):
        validation = CropImageValidator.validate_image_bytes(bytes(image["data"]), product_name or "")
        if not validation.is_valid:
            raise ValidationError(validation.combined_message)
        await db.crop_images.update_one(
            {"_id": image["_id"]},
            {"$set": {
                "validated": True,
                "crop_name": product_name.strip() if product_name else image.get("crop_name"),
                "ai_verified": False,
                "validation_category": validation.detected_category,
            }},
        )
    elif product_name and product_name.strip() and not image.get("crop_name"):
        await db.crop_images.update_one(
            {"_id": image["_id"]},
            {"$set": {"crop_name": product_name.strip()}},
        )
