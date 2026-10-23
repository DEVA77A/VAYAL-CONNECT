"""
VayalConnect Backend — Server-Side Crop Image Content Validation Service

Validates farmer-uploaded crop photographs before publication:
1. File format, byte size, and decode sanity checks (Pillow).
2. Visual meaningfulness (rejecting blank, solid-color, or degenerate images).
3. AI Multimodal Vision verification (Gemini Vision via google-genai) comparing
   the photograph against the farmer's specified crop name.
4. Detection and rejection of:
   - Selfies / human faces
   - Vehicles
   - Unrelated animals
   - Screenshots / documents
   - Crop mismatches (e.g. wheat photo for tomato listing)
   - Blank / unreadable / corrupt files
5. Deterministic test mock support for reliable CI and regression testing.
6. Bilingual (English and Tamil) explanations for all rejection reasons.
"""

from __future__ import annotations

import asyncio
import io
import json
import logging
from dataclasses import dataclass
from typing import Callable, Optional, Tuple

from PIL import Image, ImageOps, ImageStat

from app.core.config import settings
from app.core.exceptions import ValidationError

logger = logging.getLogger(__name__)


# Canonical Crop Dictionary (English <-> Tamil)
KNOWN_CROPS = {
    "tomato": ("Tomato", "தக்காளி"),
    "wheat": ("Wheat", "கோதுமை"),
    "banana": ("Banana", "வாழைப்பழம்"),
    "banana fruit": ("Banana", "வாழைப்பழம்"),
    "banana (fruit)": ("Banana", "வாழைப்பழம்"),
    "rice": ("Rice", "அரிசி"),
    "paddy": ("Paddy", "நெல்"),
    "onion": ("Onion", "வெங்காயம்"),
    "potato": ("Potato", "உருளைக்கிழங்கு"),
    "brinjal": ("Brinjal", "கத்தரிக்காய்"),
    "eggplant": ("Brinjal", "கத்தரிக்காய்"),
    "chilli": ("Chilli", "மிளகாய்"),
    "green chilli": ("Green Chilli", "பச்சை மிளகாய்"),
    "coconut": ("Coconut", "தேங்காய்"),
    "maize": ("Maize", "மக்காச்சோளம்"),
    "corn": ("Corn", "மக்காச்சோளம்"),
    "jasmine": ("Jasmine", "மல்லிகை"),
    "marigold": ("Marigold", "சாமந்தி"),
    "turmeric": ("Turmeric", "மஞ்சள்"),
    "garlic": ("Garlic", "பூண்டு"),
    "ginger": ("Ginger", "இஞ்சி"),
    "carrot": ("Carrot", "கேரட்"),
    "beetroot": ("Beetroot", "பீட்ரூட்"),
    "cabbage": ("Cabbage", "முட்டைக்கோஸ்"),
    "cauliflower": ("Cauliflower", "காலிஃபிளவர்"),
    "drumstick": ("Drumstick", "முருங்கைக்காய்"),
    "moringa": ("Moringa", "முருங்கைக்காய்"),
    "lady finger": ("Lady's Finger", "வெண்டைக்காய்"),
    "ladies finger": ("Lady's Finger", "வெண்டைக்காய்"),
    "okra": ("Okra", "வெண்டைக்காய்"),
    "bhendi": ("Bhendi", "வெண்டைக்காய்"),
    "cucumber": ("Cucumber", "வெள்ளரிக்காய்"),
    "bitter gourd": ("Bitter Gourd", "பாகற்காய்"),
    "bottle gourd": ("Bottle Gourd", "சுரைக்காய்"),
    "snake gourd": ("Snake Gourd", "புடலங்காய்"),
    "ridge gourd": ("Ridge Gourd", "பீர்க்கங்காய்"),
    "pumpkin": ("Pumpkin", "பூசணிக்காய்"),
    "radish": ("Radish", "முள்ளங்கி"),
    "coriander": ("Coriander", "கொத்தமல்லி"),
    "mint": ("Mint", "புதினா"),
    "groundnut": ("Groundnut", "நிலக்கடலை"),
    "peanut": ("Peanut", "நிலக்கடலை"),
    "sugarcane": ("Sugarcane", "கரும்பு"),
    "cotton": ("Cotton", "பருத்தி"),
    "mango": ("Mango", "மாம்பழம்"),
    "papaya": ("Papaya", "பப்பாளி"),
    "guava": ("Guava", "கொய்யா"),
    "pomegranate": ("Pomegranate", "மாதுளை"),
    "watermelon": ("Watermelon", "தர்பூசணி"),
    "lemon": ("Lemon", "எலுமிச்சை"),
    "lime": ("Lime", "எலுமிச்சை"),
}

# Reverse lookup for Tamil names
TAMIL_TO_CROP = {ta.strip().lower(): (en, ta) for en, ta in KNOWN_CROPS.values()}


def resolve_crop_names(crop_name: str) -> Tuple[str, str]:
    """Resolve input crop string into canonical English and Tamil names."""
    raw = (crop_name or "").strip()
    if "·" in raw:
        parts = [p.strip() for p in raw.split("·") if p.strip()]
        if len(parts) >= 2:
            return parts[0], parts[1]
    lowered = raw.lower()
    if lowered in KNOWN_CROPS:
        return KNOWN_CROPS[lowered]
    if lowered in TAMIL_TO_CROP:
        return TAMIL_TO_CROP[lowered]
    # Check partial contains
    for k, (en, ta) in KNOWN_CROPS.items():
        if k in lowered or ta in raw:
            return en, ta
    return raw, raw


@dataclass
class ImageValidationResult:
    is_valid: bool
    confidence: float
    reason_en: str
    reason_ta: str
    detected_category: str = "unknown"

    @property
    def combined_message(self) -> str:
        return f"{self.reason_en} / {self.reason_ta}"


class CropImageValidator:
    """Server-side image validator enforcing genuine crop photo requirements."""

    CONFIDENCE_THRESHOLD: float = 0.70
    MAX_FILE_BYTES: int = 5_000_000
    MIN_DIMENSION: int = 64
    MAX_PIXELS: int = 20_000_000

    # Deterministic mock handler for tests
    _mock_handler: Optional[Callable[[bytes, str], ImageValidationResult]] = None

    @classmethod
    def set_mock_handler(cls, handler: Optional[Callable[[bytes, str], ImageValidationResult]]) -> None:
        """Inject a deterministic mock handler for automated tests."""
        cls._mock_handler = handler

    @classmethod
    def reset_mock_handler(cls) -> None:
        """Clear test mock handler."""
        cls._mock_handler = None

    @classmethod
    def validate_image_bytes(cls, raw: bytes, crop_name: str) -> ImageValidationResult:
        """
        Execute full validation pipeline on raw image bytes.
        Returns ImageValidationResult. Does not raise exceptions unless corrupt/invalid.
        """
        # Step 1: Check file size
        if len(raw) == 0:
            return ImageValidationResult(
                is_valid=False,
                confidence=1.0,
                reason_en="Uploaded file is empty.",
                reason_ta="பதிவேற்றப்பட்ட கோப்பு காலியாக உள்ளது.",
                detected_category="empty",
            )
        if len(raw) > cls.MAX_FILE_BYTES:
            return ImageValidationResult(
                is_valid=False,
                confidence=1.0,
                reason_en="Crop photograph must be at most 5 MB.",
                reason_ta="பயிரின் படம் அதிகபட்சமாக 5 MB வரை மட்டுமே இருக்க வேண்டும்.",
                detected_category="too_large",
            )

        # Step 2: Decode image with Pillow
        try:
            Image.MAX_IMAGE_PIXELS = cls.MAX_PIXELS
            with Image.open(io.BytesIO(raw)) as original:
                format_name = (original.format or "").upper()
                if format_name not in {"JPEG", "JPG", "PNG", "WEBP"}:
                    return ImageValidationResult(
                        is_valid=False,
                        confidence=1.0,
                        reason_en="Uploaded file must be a valid JPEG, PNG, or WebP photograph.",
                        reason_ta="பதிவேற்றப்பட்ட படம் JPEG, PNG அல்லது WebP வடிவத்தில் இருக்க வேண்டும்.",
                        detected_category="invalid_format",
                    )
                if original.width < cls.MIN_DIMENSION or original.height < cls.MIN_DIMENSION:
                    return ImageValidationResult(
                        is_valid=False,
                        confidence=1.0,
                        reason_en=f"Image resolution is too low (minimum {cls.MIN_DIMENSION}x{cls.MIN_DIMENSION} required).",
                        reason_ta="படத்தின் தரம் மிகவும் குறைவாக உள்ளது.",
                        detected_category="low_resolution",
                    )
                if original.width * original.height > cls.MAX_PIXELS:
                    return ImageValidationResult(
                        is_valid=False,
                        confidence=1.0,
                        reason_en="Image dimensions exceed the 20 megapixel limit.",
                        reason_ta="படத்தின் அளவு அனுமதிக்கப்பட்ட வரம்பை விட அதிகமாக உள்ளது.",
                        detected_category="oversized",
                    )

                # Step 3: Check visual meaningfulness (blank / solid color check)
                img_rgb = ImageOps.exif_transpose(original).convert("RGB")
                stat = ImageStat.Stat(img_rgb)
                # Standard deviation of color channels: blank or solid image has near 0 stddev
                stddev = stat.stddev
                avg_stddev = sum(stddev) / len(stddev)
                if avg_stddev < 4.0:
                    return ImageValidationResult(
                        is_valid=False,
                        confidence=0.98,
                        reason_en="The uploaded image appears blank or unusable. Please upload a clear photo of your crop.",
                        reason_ta="பதிவேற்றப்பட்ட படம் வெற்று அல்லது பயன்படுத்த முடியாததாக உள்ளது. பயிரின் தெளிவான புகைப்படத்தைப் பதிவேற்றவும்.",
                        detected_category="blank",
                    )
        except Exception:
            return ImageValidationResult(
                is_valid=False,
                confidence=1.0,
                reason_en="The uploaded file is corrupt or not a valid image.",
                reason_ta="பதிவேற்றப்பட்ட படம் சிதைந்துள்ளது அல்லது செல்லுபடியாகாத படமாகும்.",
                detected_category="corrupt",
            )

        # Step 4: Check if test mock handler is installed
        if cls._mock_handler is not None:
            return cls._mock_handler(raw, crop_name)

        # Step 5: Server-side vision AI evaluation (Gemini Multimodal Vision)
        return cls._evaluate_vision_ai(raw, crop_name)

    @classmethod
    def _evaluate_vision_ai(cls, raw: bytes, crop_name: str) -> ImageValidationResult:
        """Call Gemini Multimodal Vision API to verify image content matches crop name."""
        api_key = (settings.GEMINI_API_KEY or "").strip()
        if not api_key:
            # When AI service key is missing, follow Section 4 policy:
            # "If the validator cannot determine whether the image matches:
            #  Do not claim that it was verified.
            #  Do not silently accept the image as AI-verified.
            #  Explain that the image could not be verified and ask the farmer to upload a clearer, more relevant photo."
            return ImageValidationResult(
                is_valid=False,
                confidence=0.0,
                reason_en="AI crop verification service is not configured. Please ensure GEMINI_API_KEY is configured.",
                reason_ta="AI பயிர் சரிபார்ப்பு சேவை அமைக்கப்படவில்லை. தயவுசெய்து சரியான அமைப்புகளை உறுதிப்படுத்தவும்.",
                detected_category="service_unconfigured",
            )

        crop_en, crop_ta = resolve_crop_names(crop_name)
        prompt = (
            f"You are an agricultural computer vision validation assistant for the VayalConnect farmer marketplace.\n"
            f"The farmer has listed this produce under crop name: '{crop_en}' (Tamil: '{crop_ta}').\n\n"
            f"Task: Evaluate if the provided photograph plausibly depicts this crop.\n"
            f"Valid depictions include:\n"
            f"- Harvested produce (e.g. tomatoes, wheat grains, bananas, onions)\n"
            f"- Produce growing on a plant\n"
            f"- Field crop plants\n"
            f"- Bundles, baskets, crates, or bags of the specified produce\n\n"
            f"Reject the image if it is:\n"
            f"- A selfie, face, or portrait of a person\n"
            f"- A vehicle, automobile, motorcycle, or machinery unrelated to the crop produce\n"
            f"- An unrelated animal, pet, or livestock\n"
            f"- A screenshot, text document, bill, or meme\n"
            f"- A completely different crop (e.g., photo of wheat when crop is Tomato, or photo of tomato when crop is Banana)\n"
            f"- Blank, blurry, dark, or unrecognizable\n\n"
            f"Respond strictly with valid JSON:\n"
            f"{{\n"
            f'  "is_match": true or false,\n'
            f'  "is_unrelated": true or false,\n'
            f'  "detected_category": "crop_match" | "crop_mismatch" | "selfie" | "vehicle" | "animal" | "screenshot" | "blank" | "unclear",\n'
            f'  "confidence": <float between 0.0 and 1.0>,\n'
            f'  "reason_en": "<concise explanation in English>",\n'
            f'  "reason_ta": "<concise explanation in Tamil>"\n'
            f"}}"
        )

        try:
            from google import genai
            from google.genai import types

            client = genai.Client(
                api_key=api_key,
                vertexai=False,
                enterprise=False,
                http_options={"api_version": "v1alpha", "timeout": 25.0},
            )
            # Use gemini-2.5-flash or gemini-3.8-flash
            model_name = "gemini-2.5-flash"
            part = types.Part.from_bytes(data=raw, mime_type="image/jpeg")
            response = client.models.generate_content(
                model=model_name,
                contents=[part, prompt],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    temperature=0.1,
                ),
            )
            text = (response.text or "").strip()
            # Clean possible markdown fence
            if text.startswith("```"):
                text = text.strip("`")
                if text.startswith("json"):
                    text = text[4:].strip()
            data = json.loads(text)

            is_match = bool(data.get("is_match", False))
            confidence = float(data.get("confidence", 0.0))
            category = str(data.get("detected_category", "unknown"))
            reason_en = data.get("reason_en", "")
            reason_ta = data.get("reason_ta", "")

            if is_match and confidence >= cls.CONFIDENCE_THRESHOLD:
                return ImageValidationResult(
                    is_valid=True,
                    confidence=confidence,
                    reason_en=reason_en or f"Verified crop photograph of {crop_en}.",
                    reason_ta=reason_ta or f"{crop_ta} பயிரின் படம் சரிபார்க்கப்பட்டது.",
                    detected_category="crop_match",
                )
            else:
                # Provide tailored bilingual explanations if not returned by model
                if category == "selfie":
                    r_en = "The uploaded photo appears to be a person or selfie, not a crop."
                    r_ta = "பதிவேற்றப்பட்ட படம் பயிருக்கு பதிலாக நபர் அல்லது செல்ஃபியாக உள்ளது."
                elif category == "vehicle":
                    r_en = "The uploaded photo contains a vehicle or machinery, not the crop."
                    r_ta = "பதிவேற்றப்பட்ட படம் பயிருக்கு பதிலாக வாகனம் அல்லது இயந்திரமாக உள்ளது."
                elif category == "animal":
                    r_en = "The uploaded photo contains an unrelated animal, not the specified crop."
                    r_ta = "பதிவேற்றப்பட்ட படம் பயிருக்கு பதிலாக தொடர்பில்லாத விலங்காக உள்ளது."
                elif category == "crop_mismatch":
                    r_en = f"The uploaded image does not match the specified crop ({crop_en})."
                    r_ta = f"பதிவேற்றப்பட்ட படம் குறிப்பிட்ட பயிருடன் ({crop_ta}) பொருந்தவில்லை."
                else:
                    r_en = reason_en or f"The image could not be verified as a valid photograph of {crop_en}. Please upload a clearer photo."
                    r_ta = reason_ta or f"இப்படம் {crop_ta} பயிரின் படமாக உறுதிப்படுத்தப்படவில்லை. தெளிவான புகைப்படத்தைப் பதிவேற்றவும்."

                return ImageValidationResult(
                    is_valid=False,
                    confidence=confidence,
                    reason_en=r_en,
                    reason_ta=r_ta,
                    detected_category=category,
                )

        except Exception as e:
            logger.warning("AI vision validation failed: %s", e)
            return ImageValidationResult(
                is_valid=False,
                confidence=0.0,
                reason_en="Could not verify the image content. Please upload a clearer, well-lit photo of the crop.",
                reason_ta="படத்தின் உள்ளடக்கத்தை சரிபார்க்க முடியவில்லை. பயிரின் தெளிவான, வெளிச்சமான புகைப்படத்தைப் பதிவேற்றவும்.",
                detected_category="ai_error",
            )
