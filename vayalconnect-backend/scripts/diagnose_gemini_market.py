"""Retired market diagnostic: dry-run/offline checks only. Execution is disabled."""
import argparse
import asyncio
import json

from app.integrations.gemini_market import GROUNDED_MODELS, developer_api_client


async def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", choices=sorted(GROUNDED_MODELS), default="gemini-3.5-flash-lite")
    parser.add_argument("--crop", action="append", help="Repeat to consolidate multiple crops in one request.")
    parser.add_argument("--state", default="Tamil Nadu")
    parser.add_argument("--district", default="Coimbatore")
    parser.add_argument("--market", default="Coimbatore")
    parser.add_argument("--execute-one-request", action="store_true")
    parser.add_argument("--check-auth", action="store_true", help="Offline SDK authentication check; sends no request.")
    args = parser.parse_args(argv)
    # Only explicit invocation can dispatch. No model listing, retry or fallback.
    queries = [dict(commodity=crop, state=args.state, district=args.district,
                    market=args.market, category=None, variety=None)
               for crop in dict.fromkeys(c.strip() for c in (args.crop or ["Jasmine", "Tomato"]) if c.strip())]
    plan = {"model": args.model, "request_budget": 1, "context_count": len(queries),
            "scheduler_claim_consumed": False, "cache_modified": False}
    if args.check_auth:
        if args.execute_one_request:
            parser.error("--check-auth cannot be combined with --execute-one-request")
        # SDK construction is local. Inspect header names only; never expose values.
        try:
            async with developer_api_client().aio as client:
                api = client._api_client
                headers = {k.lower() for k in api._http_options.headers or {}}
                correct = (not api.vertexai and "x-goog-api-key" in headers
                           and "authorization" not in headers
                           and str(api._http_options.base_url) == "https://generativelanguage.googleapis.com/")
            print(json.dumps({**plan, "executed": False, "offline_auth_check": correct,
                "authentication": "Gemini Developer API key via x-goog-api-key",
                "credential_values_printed": False}))
            return 0 if correct else 1
        except Exception:
            print(json.dumps({**plan, "executed": False, "offline_auth_check": False,
                              "message": "Offline authentication configuration check failed; no request sent."}))
            return 1
    if not args.execute_one_request:
        print(json.dumps({**plan, "executed": False, "message": "Legacy market diagnostic only. Execution is retired."}))
        return 0
    print(json.dumps({**plan, "executed": False, "error_code": "LEGACY_MARKET_PATH_DISABLED",
                      "message": "Gemini market execution retired. Use the Groq daily workflow and its shared claim."}))
    return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
