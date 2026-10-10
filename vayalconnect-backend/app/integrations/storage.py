"""
VayalConnect Backend — Media Storage Integration

Abstraction for product image storage.
Local implementation for development, can be swapped to Cloudinary/S3.
"""

from abc import ABC, abstractmethod
from typing import Optional
import logging

from app.core.config import settings

logger = logging.getLogger(__name__)


class MediaStorageProvider(ABC):
    """Abstract media storage provider."""

    @abstractmethod
    async def upload(self, file_data: bytes, filename: str, content_type: str) -> str:
        """Upload a file and return its URL."""
        pass

    @abstractmethod
    async def delete(self, file_url: str) -> bool:
        """Delete a file by URL."""
        pass


class LocalMediaStorage(MediaStorageProvider):
    """Local file storage for development."""

    async def upload(self, file_data: bytes, filename: str, content_type: str) -> str:
        # In development, just return a placeholder URL
        # Real implementation would save to disk
        logger.info(f"[LOCAL] File uploaded: {filename}")
        return f"{settings.MEDIA_STORAGE_BASE_URL}/{filename}"

    async def delete(self, file_url: str) -> bool:
        logger.info(f"[LOCAL] File deleted: {file_url}")
        return True


# Singleton
media_storage: MediaStorageProvider = LocalMediaStorage()
