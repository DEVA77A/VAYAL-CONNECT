"""No production connections: startup safety, real socket binding, and cleanup."""

import asyncio
import os
import socket
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import httpx
import pytest
import uvicorn

from app import main
from app.core.database import Database


@pytest.fixture
def startup_mocks(monkeypatch):
    connect, close, expire = AsyncMock(), AsyncMock(), AsyncMock()
    monkeypatch.setattr(main, "connect_db", connect)
    monkeypatch.setattr(main, "close_db", close)
    monkeypatch.setattr(
        "app.core.database.database.is_connected", AsyncMock(return_value=True)
    )
    monkeypatch.setattr(
        "app.services.order_service.OrderService.expire_reservations", expire
    )
    monkeypatch.setattr("app.core.database.get_database", lambda: MagicMock())
    return connect, close, expire


@pytest.mark.asyncio
async def test_server_binds_while_indexes_pending_and_blocks_business_routes(
    monkeypatch, startup_mocks
):
    entered, release = asyncio.Event(), asyncio.Event()

    async def delayed_indexes():
        entered.set()
        await release.wait()

    monkeypatch.setattr(main, "create_indexes", delayed_indexes)
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    monkeypatch.setenv("PORT", str(port))
    server = uvicorn.Server(
        uvicorn.Config(
            main.create_app(),
            host="0.0.0.0",
            port=int(os.environ["PORT"]),
            log_level="warning",
            lifespan="on",
        )
    )
    task = asyncio.create_task(server.serve())
    try:
        await asyncio.wait_for(entered.wait(), 5)
        for _ in range(100):
            if server.started:
                break
            await asyncio.sleep(0.02)
        assert server.started, "Slow indexes must not prevent the listening socket"
        assert server.servers[0].sockets[0].getsockname()[0] == "0.0.0.0"
        startup_mocks[2].assert_not_awaited()
        async with httpx.AsyncClient(
            base_url=f"http://127.0.0.1:{port}", trust_env=False
        ) as client:
            health = await client.get("/health")
            assert (
                health.status_code == 503
                and health.json()["database"] == "initializing"
            )
            for path in (
                "/api/v1/auth/login",
                "/api/v1/payments",
                "/api/v1/market-prices",
            ):
                response = await client.get(path)
                assert response.status_code == 503
                assert response.json()["error"]["code"] == "SERVICE_INITIALIZING"
            release.set()
            for _ in range(100):
                health = await client.get("/health")
                if health.status_code == 200:
                    break
                await asyncio.sleep(0.02)
            assert health.status_code == 200
            assert (await client.get("/")).status_code == 200
            startup_mocks[2].assert_awaited()
    finally:
        release.set()
        server.should_exit = True
        await asyncio.wait_for(task, 5)
    startup_mocks[1].assert_awaited_once()
    assert not server.config.app.state.database_ready


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", ["exception", "timeout"])
async def test_initialization_failure_never_marks_healthy_or_runs_cleanup(
    monkeypatch, startup_mocks, caplog, failure
):
    if failure == "timeout":

        async def blocked():
            await asyncio.Event().wait()

        monkeypatch.setattr(main, "create_indexes", blocked)
        monkeypatch.setattr(main, "DATABASE_INITIALIZATION_TIMEOUT_SECONDS", 0.01)
    else:
        monkeypatch.setattr(
            main,
            "create_indexes",
            AsyncMock(side_effect=RuntimeError("private-database-value")),
        )
    monkeypatch.setattr(main.settings, "CORS_ORIGINS", '["https://startup.example"]')
    app = main.create_app()
    async with main.lifespan(app):
        await asyncio.sleep(0.03)
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://test"
        ) as client:
            headers = {
                "Origin": "https://startup.example",
                "X-Request-ID": "failed-startup",
            }
            response = await client.get("/health", headers=headers)
            assert (
                response.status_code == 503
                and response.json()["database"] == "initialization_failed"
            )
            rejection = await client.get("/api/v1/market-prices", headers=headers)
            assert rejection.status_code == 503
            assert rejection.json()["error"]["code"] == "DATABASE_INITIALIZATION_FAILED"
            assert rejection.headers["X-Request-ID"] == "failed-startup"
            assert rejection.json()["request_id"] == "failed-startup"
            assert "access-control-allow-origin" in rejection.headers
        assert not app.state.database_ready
        startup_mocks[2].assert_not_awaited()
    startup_mocks[1].assert_awaited_once()
    assert not app.state.database_ready
    assert "Database initialization failed" in caplog.text
    assert "private-database-value" not in caplog.text


@pytest.mark.asyncio
async def test_shutdown_cancels_pending_initialization_and_closes_database(
    monkeypatch, startup_mocks
):
    entered, cancelled = asyncio.Event(), asyncio.Event()

    async def blocked():
        entered.set()
        try:
            await asyncio.Event().wait()
        finally:
            cancelled.set()

    monkeypatch.setattr(main, "create_indexes", blocked)
    async with main.lifespan(main.create_app()):
        await asyncio.wait_for(entered.wait(), 1)
    assert cancelled.is_set()
    startup_mocks[1].assert_awaited_once()


@pytest.mark.asyncio
async def test_failed_connection_is_closed_without_starting_indexes(
    monkeypatch, startup_mocks
):
    monkeypatch.setattr(
        main, "connect_db", AsyncMock(side_effect=RuntimeError("connection failed"))
    )
    indexes = AsyncMock()
    monkeypatch.setattr(main, "create_indexes", indexes)
    with pytest.raises(RuntimeError):
        async with main.lifespan(main.create_app()):
            pytest.fail("Startup must not yield after a failed connection")
    indexes.assert_not_awaited()
    startup_mocks[1].assert_awaited_once()


@pytest.mark.asyncio
async def test_mongo_commands_are_bounded_and_initialization_phase_is_logged(
    monkeypatch, caplog
):
    client = MagicMock()
    client.admin.command = AsyncMock()
    factory = MagicMock(return_value=client)
    monkeypatch.setattr("app.core.database.AsyncIOMotorClient", factory)
    db = Database()
    await db.connect()
    assert factory.call_args.kwargs["socketTimeoutMS"] == 30000
    assert factory.call_args.kwargs["waitQueueTimeoutMS"] == 10000
    client.__getitem__.return_value.__getitem__.return_value.create_index = AsyncMock(
        side_effect=RuntimeError("private-value")
    )
    with caplog.at_level("INFO"), pytest.raises(RuntimeError):
        await db.create_indexes()
    assert db.startup_phase == "users:indexes"
    assert "phase=users:indexes" in caplog.text
    assert "private-value" not in caplog.text


def test_docker_command_uses_render_host_and_environment_port():
    dockerfile = (Path(__file__).parents[1] / "Dockerfile").read_text()
    assert "--host 0.0.0.0 --port ${PORT:-8000}" in dockerfile


@pytest.mark.asyncio
@pytest.mark.parametrize("missing_state", [False, True])
async def test_missing_lifespan_fails_closed_even_when_mongo_is_connected(
    monkeypatch, startup_mocks, missing_state
):
    app = main.create_app()
    assert app.state.database_ready is False
    assert app.state.database_initialization_failed is False
    if missing_state:
        del app.state.database_ready
        del app.state.database_initialization_failed
    indexes = AsyncMock()
    monkeypatch.setattr(main, "create_indexes", indexes)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        health = await client.get("/health")
        assert health.status_code == 503
        assert health.json()["database"] == "initializing"
        for path in ("/api/v1/market-prices", "/api/v1/payments", "/"):
            response = await client.get(path)
            assert response.status_code == 503
            assert response.json()["error"]["code"] == "SERVICE_INITIALIZING"
        assert (await client.post("/api/v1/auth/login", json={})).status_code == 503
    startup_mocks[0].assert_not_awaited()
    indexes.assert_not_awaited()
    from app.core.database import database

    database.is_connected.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("failed", [False, True])
@pytest.mark.parametrize("supplied_id", [None, "startup-client-trace"])
async def test_startup_503_preserves_cors_and_request_id(
    monkeypatch, failed, supplied_id
):
    from uuid import UUID

    origin = "https://allowed.example"
    monkeypatch.setattr(main.settings, "CORS_ORIGINS", '["https://allowed.example"]')
    app = main.create_app()
    app.state.database_initialization_failed = failed
    headers = {"Origin": origin}
    if supplied_id:
        headers["X-Request-ID"] = supplied_id
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.get("/api/v1/market-prices", headers=headers)
        assert response.status_code == 503
        assert response.headers["access-control-allow-origin"] == origin
        assert response.headers["access-control-allow-credentials"] == "true"
        request_id = response.headers["X-Request-ID"]
        assert response.json()["request_id"] == request_id
        assert response.headers["Retry-After"] == "5"
        if supplied_id:
            assert request_id == supplied_id
        else:
            assert UUID(request_id)
        assert response.json()["error"]["code"] == (
            "DATABASE_INITIALIZATION_FAILED" if failed else "SERVICE_INITIALIZING"
        )
        health = await client.get("/health", headers=headers)
        assert health.status_code == 503
        assert health.headers["access-control-allow-origin"] == origin
        assert health.headers["X-Request-ID"]
        disallowed = await client.get(
            "/api/v1/market-prices", headers={"Origin": "https://disallowed.example"}
        )
        assert disallowed.status_code == 503
        assert "access-control-allow-origin" not in disallowed.headers
        assert disallowed.headers["X-Request-ID"]
    assert not app.state.database_ready


@pytest.mark.asyncio
async def test_cors_preflight_is_traceable_and_does_not_bypass_readiness(monkeypatch):
    monkeypatch.setattr(main.settings, "CORS_ORIGINS", '["https://allowed.example"]')
    app = main.create_app()
    executed = AsyncMock()

    async def business():
        await executed()
        return {"success": True}

    app.add_api_route("/business-probe", business, methods=["POST"])
    headers = {
        "Origin": "https://allowed.example",
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "Content-Type,X-Request-ID",
        "X-Request-ID": "preflight-trace",
    }
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        preflight = await client.options("/business-probe", headers=headers)
        assert preflight.status_code == 200
        assert preflight.headers["access-control-allow-origin"] == headers["Origin"]
        assert preflight.headers["X-Request-ID"] == "preflight-trace"
        rejection = await client.post(
            "/business-probe", json={}, headers={"Origin": headers["Origin"]}
        )
        assert rejection.status_code == 503
        assert rejection.headers["access-control-allow-origin"] == headers["Origin"]
        assert rejection.json()["request_id"] == rejection.headers["X-Request-ID"]
        bad_preflight = await client.options(
            "/business-probe",
            headers={**headers, "Origin": "https://disallowed.example"},
        )
        assert bad_preflight.status_code == 400
        assert "access-control-allow-origin" not in bad_preflight.headers
        assert bad_preflight.headers["X-Request-ID"] == "preflight-trace"
    executed.assert_not_awaited()
    assert not app.state.database_ready
