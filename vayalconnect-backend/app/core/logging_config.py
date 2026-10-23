"""
VayalConnect Backend — Logging Configuration

Structured logging. Never logs secrets, passwords, OTPs, or bank details.
"""

import logging
import sys

from app.core.config import settings


def setup_logging():
    """Configure application logging."""
    log_level = logging.DEBUG if settings.DEBUG else logging.INFO

    # Root logger configuration
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=[logging.StreamHandler(sys.stdout)],
    )

    # Suppress noisy third-party loggers
    logging.getLogger("motor").setLevel(logging.WARNING)
    logging.getLogger("pymongo").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("google_genai").setLevel(logging.WARNING)

    logger = logging.getLogger("vayalconnect")
    logger.info(
        f"Logging initialized | env={settings.APP_ENV} | level={logging.getLevelName(log_level)}"
    )
    return logger
