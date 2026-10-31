"""
VayalConnect Backend — Main Application

FastAPI application factory with all routers, middleware, and startup hooks.
"""

import asyncio
from contextlib import asynccontextmanager, suppress
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
import logging

from app.core.config import settings
from app.core.database import connect_db, close_db, create_indexes
from app.core.logging_config import setup_logging
from app.core.exceptions import VayalConnectError
from app.middleware.request_id import RequestIDMiddleware

# Import routers
from app.api.v1.media import router as media_router
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
DATABASE_INITIALIZATION_TIMEOUT_SECONDS = 300


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan — startup and shutdown."""
    # Startup
    setup_logging()
    logger.info(f"Starting VayalConnect Backend v{settings.APP_VERSION}")
    logger.info(f"Environment: {settings.APP_ENV}")

    app.state.database_ready = False
    app.state.database_initialization_failed = False

    async def reservation_worker():
        from app.services.order_service import OrderService
        from app.core.database import get_database
        while True:
            try:
                await OrderService(get_database()).expire_reservations()
            except Exception as exc:
                logger.warning("Reservation cleanup failed (%s)", type(exc).__name__)
            await asyncio.sleep(60)

    async def initialize_database():
        try:
            await asyncio.wait_for(create_indexes(), DATABASE_INITIALIZATION_TIMEOUT_SECONDS)
        except Exception as exc:
            from app.core.database import database
            app.state.database_ready = False
            app.state.database_initialization_failed = True
            logger.error("Database initialization failed phase=%s category=%s code=%s; service remains unready",
                database.startup_phase, type(exc).__name__, getattr(exc, "code", None))
            return
        app.state.database_ready = True
        logger.info("Database connected and indexes created; service ready")

        async def market_scheduler_worker():
            from app.services.market_discovery import MarketDiscoveryService
            from app.core.database import get_database
            from datetime import datetime, timezone, timedelta
            try:
                from zoneinfo import ZoneInfo
                kolkata_tz = ZoneInfo("Asia/Kolkata")
            except Exception:
                kolkata_tz = timezone(timedelta(hours=5, minutes=30))

            # Startup recovery check: if service starts or restarts after 08:00 AM IST,
            # execute recovery check immediately if today's daily batch hasn't run.
            try:
                db = get_database()
                now_ist = datetime.now(kolkata_tz)
                if now_ist.hour >= 8:
                    logger.info("Executing market price startup recovery check for IST %s", now_ist.date())
                    await MarketDiscoveryService(db).refresh_daily()
            except Exception as exc:
                logger.warning("Market scheduler startup recovery check failed: %s", exc)

            while True:
                try:
                    db = get_database()
                    now_ist = datetime.now(kolkata_tz)
                    # Trigger at or after 08:00 AM IST
                    if now_ist.hour >= 8:
                        await MarketDiscoveryService(db).refresh_daily()
                except Exception as exc:
                    logger.warning("Market scheduler worker category=%s", type(exc).__name__)
                await asyncio.sleep(60)

        asyncio.create_task(market_scheduler_worker())
        await reservation_worker()

    task = None
    try:
        await connect_db()
        # Uvicorn binds after lifespan yields. Keep protected routes unready
        # until all indexes and existing initialization operations succeed.
        task = asyncio.create_task(initialize_database())
        yield
    finally:
        app.state.database_ready = False
        if task is not None:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task
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
    app.state.database_ready = False
    app.state.database_initialization_failed = False

    # ============================================================
    # Middleware
    # ============================================================
    @app.middleware("http")
    async def database_readiness(request: Request, call_next):
        if request.url.path != "/health" and not getattr(app.state, "database_ready", False):
            failed = getattr(app.state, "database_initialization_failed", False)
            return JSONResponse(status_code=503, content={
                "success": False, "data": None,
                "error": {"code": "DATABASE_INITIALIZATION_FAILED" if failed else "SERVICE_INITIALIZING",
                          "message": "Database initialization failed." if failed else "Service is starting. Please retry."},
                "request_id": getattr(request.state, "request_id", None),
            }, headers={"Retry-After": "5"})
        return await call_next(request)

    # Last registered runs first: request IDs and CORS wrap readiness rejections.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.ALLOWED_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(RequestIDMiddleware)

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

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(request: Request, exc: RequestValidationError):
        # FastAPI's default includes submitted values, including passwords/bank data.
        fields = []
        messages = []
        for e in exc.errors():
            loc = list(e.get("loc", []))
            raw_msg = e.get("msg", "")
            if raw_msg.startswith("Value error, "):
                clean_msg = raw_msg[len("Value error, "):]
            else:
                clean_msg = raw_msg
            fields.append({
                "location": loc,
                "type": e.get("type", "value_error"),
                "message": clean_msg,
            })
            if clean_msg:
                messages.append(clean_msg)
        primary_message = messages[0] if messages else "Check required fields and values."
        return JSONResponse(status_code=422, content={
            "success": False, "data": None,
            "error": {
                "code": "VALIDATION_ERROR",
                "message": primary_message,
                "fields": fields,
            },
            "request_id": getattr(request.state, "request_id", None),
        })

    @app.exception_handler(Exception)
    async def generic_error_handler(request: Request, exc: Exception):
        logger.error("Unhandled exception category=%s", type(exc).__name__)
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
    app.include_router(media_router, prefix=api_prefix)
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
        if not getattr(app.state, "database_ready", False):
            failed = getattr(app.state, "database_initialization_failed", False)
            return JSONResponse(status_code=503, content={
                "status": "unhealthy" if failed else "starting",
                "database": "initialization_failed" if failed else "initializing",
            })
        from app.core.database import database
        connected = await database.is_connected()
        if not connected:
            return JSONResponse(status_code=503, content={"status": "unhealthy", "database": "unavailable"})
        import os
        return {
            "commit": os.getenv("RENDER_GIT_COMMIT"),
            "database": "connected",
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
