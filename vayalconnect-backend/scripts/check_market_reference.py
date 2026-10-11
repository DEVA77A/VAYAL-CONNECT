"""Read-only official market-provider check. Never prints credentials or invents rates."""
import argparse
import asyncio
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", type=Path)
    parser.add_argument("--commodity", default="Tomato")
    parser.add_argument("--state", default="Tamil Nadu")
    args = parser.parse_args()
    if args.env_file:
        from dotenv import load_dotenv
        load_dotenv(args.env_file, override=True)
    from app.integrations.government_market import market_price_provider
    from app.services.pricing_service import PricingEngine
    from urllib.parse import urlparse
    if urlparse(market_price_provider.base_url).hostname != "api.data.gov.in":
        print(json.dumps({"available": False, "message": "Official api.data.gov.in endpoint is required for this probe."}))
        return
    result = await market_price_provider.search_prices(commodity=args.commodity, state=args.state, limit=5)
    if not result.get("live"):
        import httpx
        try:
            async with httpx.AsyncClient(timeout=5.0) as diagnostic:
                await diagnostic.get("https://api.data.gov.in/")
        except httpx.RequestError as exc:
            description = str(exc).upper()
            reason = "TLS certificate verification failed" if "CERTIFICATE_VERIFY_FAILED" in description else "DNS resolution failed" if "GETADDRINFO" in description or "NAME RESOLUTION" in description else "Public host connection unavailable"
            print(json.dumps({"public_host_diagnostic": reason, "error_type": type(exc).__name__}))
    valid = [r for r in result.get("records", []) if PricingEngine._valid_reference(r, args.commodity, r.get("market", ""))]
    print(json.dumps({"available": bool(valid) and result.get("live", False), "message": result.get("message"),
                      "verified_record_count": len(valid),
                      "records": [{k: str(r.get(k)) for k in ("commodity", "market", "unit", "arrival_date", "source")} for r in valid]}))


if __name__ == "__main__":
    asyncio.run(main())
