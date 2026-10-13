"""One non-inference authentication/model-list GET; no market discovery."""
import asyncio
import httpx
from app.core.config import settings
from app.integrations.groq_market import API, STRICT_MODELS


async def main():
    if not settings.GROQ_API_KEY.strip():
        print("GROQ_API_KEY missing in backend environment. No request sent.")
        return 1
    try:
        async with httpx.AsyncClient(timeout=15, follow_redirects=False,
                transport=httpx.AsyncHTTPTransport(retries=0)) as client:
            response = await client.get(API + "/models", headers={"Authorization": "Bearer " + settings.GROQ_API_KEY})
        if response.status_code != 200:
            safe_message = {
                401: "Authentication rejected; check whether the key is valid and active.",
                403: "Access denied; check project permissions.",
                429: "Rate limit reached.",
            }.get(response.status_code, "Groq rejected the model-list request.")
            print(f"Groq authentication/model check failed: HTTP {response.status_code}. {safe_message} No retry.")
            return 1
        models = response.json()["data"]
        model = next((m for m in models if m["id"] == settings.GROQ_MODEL and m.get("active", True)), None)
        if model is None or settings.GROQ_MODEL not in STRICT_MODELS:
            print("Selected model unavailable or strict-output support not validated. Discovery must remain disabled.")
            return 1
        print("Authentication successful; configured strict-output model is available. No inference or discovery performed.")
        print("Model context window:", model.get("context_window", "not reported"))
        return 0
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        print("Groq connection/model check failed. No retry; credentials and upstream response suppressed.")
        return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
