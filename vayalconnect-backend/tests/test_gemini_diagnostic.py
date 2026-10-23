"""Operator probe tests always mock the SDK. Never call the real provider."""
import json
import logging
from contextlib import asynccontextmanager
from types import SimpleNamespace as NS
from unittest.mock import AsyncMock, patch
import httpx

import pytest
from google import genai
from google.genai.errors import ClientError

from app.integrations.gemini_market import error_diagnostics, sanitized_provider_message, GeminiMarketPriceProvider, configured_api_key
from scripts.diagnose_gemini_market import main


def test_message_preserves_quota_wording_and_redacts_sensitive_values(monkeypatch):
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "synthetic-private-key")
    monkeypatch.setattr("app.integrations.gemini_market.settings.JWT_SECRET", "private-jwt-secret")
    message = ("Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, "
               "limit: 0, model: gemini-3.5-flash-lite. Key=synthetic-private-key JWT=private-jwt-secret "
               "Bearer unlisted-token https://example.org?key=unlisted-secret "
               "projects/project-123 consumer=hidden-consumer\nRetry later.")
    result = sanitized_provider_message(message, {"metadata": {"consumer": "hidden-consumer"}})
    assert "Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests" in result
    assert "limit: 0, model: gemini-3.5-flash-lite" in result
    for private in ("synthetic-private-key", "private-jwt-secret", "unlisted-token", "unlisted-secret",
                    "project-123", "hidden-consumer"):
        assert private not in result
    assert "\n" not in result


def test_sdk_message_and_status_are_captured_without_inferring_quota():
    error = ClientError(429, {"error": {"status": "RESOURCE_EXHAUSTED",
        "message": "Google Search grounding quota exceeded for this model."}})
    result = error_diagnostics(error, "gemini-3.5-flash-lite")
    assert result["provider_message"] == "Google Search grounding quota exceeded for this model."
    assert result["status"] == "RESOURCE_EXHAUSTED" and result["http_status"] == 429
    assert result["quota_violations"] == []


@pytest.mark.asyncio
async def test_diagnostic_is_dry_run_by_default(capsys):
    with patch.object(genai, "Client") as client:
        assert await main([]) == 0
    client.assert_not_called()
    result = json.loads(capsys.readouterr().out)
    assert result["executed"] is False
    assert result["scheduler_claim_consumed"] is False


@pytest.mark.asyncio
@pytest.mark.parametrize("code", [None, 429, 403])
async def test_diagnostic_uses_one_explicit_model_no_database_no_retry(monkeypatch, capsys, code):
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "synthetic-private-key")
    original_model = "gemini-3.8-flash"
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_MARKET_MODELS", original_model)
    message = "Quota exceeded. synthetic-private-key"
    error = ClientError(code, {"error": {"status": "RESOURCE_EXHAUSTED", "message": message}}) if code else None
    generate = AsyncMock(side_effect=error, return_value=NS(text="{}", candidates=[]))
    @asynccontextmanager
    async def aio_client():
        yield NS(models=NS(generate_content=generate))
    previous_logging_level = logging.root.manager.disable
    with patch.object(genai, "Client", return_value=NS(aio=aio_client())) as client, \
         patch("app.core.database.connect_db", AsyncMock(side_effect=AssertionError("No MongoDB access"))) as connect, \
         patch("app.services.market_discovery.MarketDiscoveryService.refresh_daily", AsyncMock()) as daily:
        exit_code = await main(["--execute-one-request", "--model", "gemini-3.5-flash-lite",
                                "--crop", "Jasmine", "--crop", "Tomato"])
    assert exit_code == 1
    generate.assert_not_awaited()
    client.assert_not_called()
    connect.assert_not_awaited()
    daily.assert_not_awaited()
    assert logging.root.manager.disable == previous_logging_level
    output = capsys.readouterr().out
    assert "synthetic-private-key" not in output
    assert json.loads(output)["error_code"] == "LEGACY_MARKET_PATH_DISABLED"


def test_long_message_redacts_key_before_truncation(monkeypatch):
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "synthetic-private-key")
    result = sanitized_provider_message("x" * 3990 + "synthetic-private-key")
    assert len(result) <= 4000 and "synthetic" not in result


@pytest.mark.parametrize("value", ["Bearer synthetic-token", "ya29.synthetic-token",
    "auth_tokens/synthetic-token", "Authorization: synthetic-token", '"synthetic-key"',
    "key\nwith-controls", "eyJtest.eyJtest.signature"])
@pytest.mark.asyncio
async def test_oauth_or_header_credentials_fail_before_any_sdk_call(monkeypatch, value):
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", value)
    with patch.object(genai, "Client") as client:
        result = await GeminiMarketPriceProvider().diagnose_once([dict(commodity="Jasmine")], "gemini-3.5-flash-lite")
    client.assert_not_called()
    assert result["error_code"] == "INVALID_API_KEY_FORMAT"
    assert value not in json.dumps(result)


def test_authorization_api_keys_are_not_mistaken_for_oauth_tokens(monkeypatch):
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "AQ.synthetic-test-authorization-key")
    assert configured_api_key() == "AQ.synthetic-test-authorization-key"


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", [False, True])
async def test_real_sdk_uses_key_header_and_developer_endpoint_despite_ambient_overrides(monkeypatch, failure):
    # Real SDK with an in-memory HTTP transport, never network access.
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "synthetic-configured-key")
    for name, value in {"GOOGLE_API_KEY": "synthetic-wrong-key", "GOOGLE_GENAI_USE_VERTEXAI": "true",
            "GOOGLE_GENAI_USE_ENTERPRISE": "true", "GOOGLE_CLOUD_PROJECT": "synthetic-project",
            "GOOGLE_CLOUD_LOCATION": "us-central1", "GOOGLE_GEMINI_BASE_URL": "https://wrong.example"}.items():
        monkeypatch.setenv(name, value)
    requests = []
    def transport(request):
        requests.append(request)
        assert request.url.host == "generativelanguage.googleapis.com"
        assert request.url.path.startswith("/v1beta/models/")
        assert request.headers["x-goog-api-key"] == "synthetic-configured-key"
        assert "authorization" not in request.headers
        if failure:
            return httpx.Response(401, json={"error": {"code": 401, "status": "UNAUTHENTICATED",
                "message": "Request had invalid authentication credentials.", "details": [{
                    "@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": "ACCESS_TOKEN_TYPE_UNSUPPORTED"}]}})
        return httpx.Response(200, json={"candidates": [{"content": {"parts": [{"text": "{}"}], "role": "model"}}]})
    real_client = genai.Client
    async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as mock_http:
        def create(**kwargs):
            assert kwargs["api_key"] == "synthetic-configured-key"
            assert kwargs["vertexai"] is False and kwargs["enterprise"] is False
            assert kwargs["credentials"] is None
            kwargs["http_options"].httpx_async_client = mock_http
            return real_client(**kwargs)
        with patch.object(genai, "Client", side_effect=create), patch("google.auth.default") as adc:
            outcome = await GeminiMarketPriceProvider().diagnose_once([dict(commodity="Jasmine")], "gemini-3.5-flash-lite")
        adc.assert_not_called()
    assert len(requests) == 1
    if failure:
        assert outcome["error_code"] == 401
        assert outcome["diagnostics"]["status"] == "UNAUTHENTICATED"
        assert outcome["diagnostics"]["reasons"] == ["ACCESS_TOKEN_TYPE_UNSUPPORTED"]
        assert "credential type" in outcome["message"]
    else:
        assert outcome["generation_succeeded"] is True
    # Collect SDK finalizers while this test's event loop is still running.
    import gc, asyncio
    gc.collect()
    await asyncio.sleep(0)


@pytest.mark.asyncio
async def test_offline_auth_check_sends_no_request(monkeypatch, capsys):
    monkeypatch.setattr("app.integrations.gemini_market.settings.GEMINI_API_KEY", "synthetic-private-key")
    with patch("google.genai.models.AsyncModels.generate_content", AsyncMock()) as generate:
        assert await main(["--check-auth"]) == 0
    generate.assert_not_awaited()
    output = capsys.readouterr().out
    assert "synthetic-private-key" not in output
    assert json.loads(output)["executed"] is False
    import gc, asyncio
    gc.collect()
    await asyncio.sleep(0)


def test_backend_env_path_is_independent_of_working_directory():
    from pathlib import Path
    from app.core.config import Settings
    assert Path(Settings.model_config["env_file"]) == Path(__file__).parents[1] / ".env"


def test_settings_load_dotenv_then_process_environment_takes_precedence(monkeypatch, tmp_path):
    from app.core.config import Settings
    env_file = tmp_path / ".env"
    env_file.write_text("GEMINI_API_KEY=synthetic-file-key\n", encoding="utf-8")
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    assert Settings(_env_file=env_file).GEMINI_API_KEY == "synthetic-file-key"
    monkeypatch.setenv("GEMINI_API_KEY", "synthetic-process-key")
    assert Settings(_env_file=env_file).GEMINI_API_KEY == "synthetic-process-key"
