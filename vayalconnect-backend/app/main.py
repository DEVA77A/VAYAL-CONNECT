"""
VayalConnect Backend — Main Application

FastAPI application factory with all routers, middleware, and startup hooks.
"""

from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import logging

from app.core.config import settings
from app.core.database import connect_db, close_db, create_indexes
from app.core.logging_config import setup_logging
from app.core.exceptions import VayalConnectError
from app.middleware.request_id import RequestIDMiddleware

# Import routers
from app.api.v1.auth import router as auth_router
from app.api.v1.users import router as users_router
from app.api.v1.farmers import router as farmers_router
from app.api.v1.buyers import router as buyers_router
from app.api.v1.products import router as products_router
from app.api.v1.orders import router as orders_router
from app.api.v1.payments import router as payments_router
from app.api.v1.payouts import router as payouts_router
from app.api.v1.admin import router as admin_router
from app.api.v1.reports import router as reports_router
from app.api.v1.webhooks import router as webhooks_router
from app.api.v1.settings import router as settings_router
from app.api.v1.market_prices import router as market_prices_router

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan — startup and shutdown."""
    # Startup
    setup_logging()
    logger.info(f"Starting VayalConnect Backend v{settings.APP_VERSION}")
    logger.info(f"Environment: {settings.APP_ENV}")

    await connect_db()
    await create_indexes()
    logger.info("Database connected and indexes created")

    yield

    # Shutdown
    logger.info("Shutting down VayalConnect Backend")
    await close_db()


def create_app() -> FastAPI:
    """Application factory."""
    app = FastAPI(
        title="VayalConnect API",
        description=(
            "🌾 VayalConnect — Agricultural Marketplace Backend\n\n"
            "நம்ம வயல், நேரடி CONNECT\n\n"
            "Connecting Farmers and Buyers with transparent, "
            "government-referenced pricing."
        ),
        version=settings.APP_VERSION,
        docs_url="/api/docs" if settings.APP_ENV != "production" else None,
        redoc_url="/api/redoc" if settings.APP_ENV != "production" else None,
        lifespan=lifespan,
    )

    # ============================================================
    # Middleware
    # ============================================================
    app.add_middleware(RequestIDMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.ALLOWED_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ============================================================
    # Global Exception Handler
    # ============================================================
    @app.exception_handler(VayalConnectError)
    async def vayalconnect_error_handler(request: Request, exc: VayalConnectError):
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "success": False,
                "error": {
                    "code": exc.error_code,
                    "message": exc.detail,
                },
                "data": None,
                "request_id": getattr(request.state, "request_id", None),
            },
        )

    @app.exception_handler(Exception)
    async def generic_error_handler(request: Request, exc: Exception):
        logger.error(f"Unhandled exception: {exc}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": {
                    "code": "INTERNAL_ERROR",
                    "message": "An unexpected error occurred.",
                },
                "data": None,
                "request_id": getattr(request.state, "request_id", None),
            },
        )

    # ============================================================
    # API Routers (v1)
    # ============================================================
    api_prefix = "/api/v1"
    app.include_router(auth_router, prefix=api_prefix)
    app.include_router(users_router, prefix=api_prefix)
    app.include_router(farmers_router, prefix=api_prefix)
    app.include_router(buyers_router, prefix=api_prefix)
    app.include_router(products_router, prefix=api_prefix)
    app.include_router(orders_router, prefix=api_prefix)
    app.include_router(payments_router, prefix=api_prefix)
    app.include_router(payouts_router, prefix=api_prefix)
    app.include_router(admin_router, prefix=api_prefix)
    app.include_router(reports_router, prefix=api_prefix)
    app.include_router(webhooks_router, prefix=api_prefix)
    app.include_router(settings_router, prefix=api_prefix)
    app.include_router(market_prices_router, prefix=api_prefix)

    # ============================================================
    # Health Check
    # ============================================================
    @app.get("/health")
    async def health_check():
        return {
            "status": "healthy",
            "service": "VayalConnect Backend",
            "version": settings.APP_VERSION,
        }

    @app.get("/")
    async def root():
        return {
            "service": "VayalConnect Backend",
            "tagline": "நம்ம வயல், நேரடி CONNECT",
            "version": settings.APP_VERSION,
            "docs": "/api/docs" if settings.APP_ENV != "production" else "disabled",
        }

    return app


# Create the application instance
app = create_app()
