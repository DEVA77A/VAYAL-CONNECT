"""Actual compressed crop photographs stored in MongoDB, not ephemeral Render disk."""
import asyncio
from io import BytesIO
from bson import ObjectId, Binary
from fastapi import APIRouter, Depends, UploadFile, File, Request
from fastapi.responses import Response
from app.api.deps import get_approved_farmer, get_current_user, get_request_id
from app.core.database import get_database
from app.core.exceptions import ValidationError, NotFoundError
from app.schemas.common import APIResponse
from app.repositories.products import ProductRepository

router = APIRouter(prefix="/media", tags=["Crop images"])


def compress_image(raw):
    from PIL import Image, ImageOps, UnidentifiedImageError
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
        raise ValidationError("Upload a valid crop photograph, at most 5 MB and 20 megapixels.") from None


@router.post("", response_model=APIResponse, status_code=201)
async def upload_image(request: Request, file: UploadFile = File(...), user=Depends(get_approved_farmer), db=Depends(get_database)):
    raw = await file.read(5_000_001)
    await file.close()
    if len(raw) > 5_000_000:
        raise ValidationError("Crop photograph must be at most 5 MB.")
    data = await asyncio.to_thread(compress_image, raw)
    result = await db.crop_images.insert_one({"farmer_id": ObjectId(user["id"]), "data": Binary(data), "content_type": "image/jpeg"})
    return APIResponse(data={"image_url": "/api/v1/media/" + str(result.inserted_id)}, request_id=get_request_id(request))


@router.get("/{image_id}")
async def read_image(image_id: str, user=Depends(get_current_user), db=Depends(get_database)):
    if not ObjectId.is_valid(image_id):
        raise NotFoundError("Image")
    doc = await db.crop_images.find_one({"_id": ObjectId(image_id)})
    if not doc:
        raise NotFoundError("Image")
    if user["role"] != "ADMIN" and str(doc["farmer_id"]) != user["id"]:
        visible, count = await ProductRepository(db).list_active(limit=1, image_url="/api/v1/media/" + image_id)
        if not count:
            raise NotFoundError("Image")
    return Response(content=bytes(doc["data"]), media_type="image/jpeg", headers={"Cache-Control": "private, max-age=300", "X-Content-Type-Options": "nosniff"})


async def validate_owned_image(db, image_url, farmer_id):
    if image_url is None:
        return
    prefix = "/api/v1/media/"
    if not image_url.startswith(prefix) or not ObjectId.is_valid(image_url[len(prefix):]):
        raise ValidationError("Upload a crop photograph using the authenticated upload endpoint.")
    image = await db.crop_images.find_one({"_id": ObjectId(image_url[len(prefix):]), "farmer_id": ObjectId(farmer_id)}, {"_id": 1})
    if not image:
        raise ValidationError("Crop photograph must belong to the authenticated farmer.")
