> Superseded: active market discovery now uses [Groq evidence selection](GROQ_MARKET_PRICES.md). This file documents a retired implementation.

# Daily Gemini market discovery

The existing app now reads a verified MongoDB cache. Neither Flutter GETs,
Add/Edit Crop lookups, listing saves, nor an empty/stale cache can trigger Gemini.
Lookup contexts are registered for the next scheduled run. No application rebuild,
production deployment, production data modification, credential change or APK
replacement was performed for this change.

## One request per IST day

`python -m scripts.refresh_market_prices` collects all ACTIVE products plus farmer
lookup contexts requested within 90 days. There is no crop/category whitelist.
Whitespace and case are used for deduplication, preserving the first original crop
spelling. Different state/district/market/variety/category contexts are retained.
Crops are grouped with all their contexts in ONE Google Search grounded prompt,
including vegetables, fruits, flowers, Jasmine and newly registered crops.

Before discovery, MongoDB atomically inserts `_id: batch:YYYY-MM-DD` into
`market_daily_runs`, using the Asia/Kolkata day and majority write acknowledgement.
MongoDB's built-in unique `_id` index arbitrates concurrent workers/cron services.
There is no expiring lease, per-crop loop or same-day retry. Repeated invocations,
429, timeouts, rejected evidence, credentials/model errors and crashes all retain
that day's reservation. Do not delete a current-day reservation to rerun the job.
The existing 90-day TTL for finished history cannot remove a current-day claim.

With valid configuration and nonempty crops, the winning run sends exactly ONE
`generate_content` request. SDK retries are disabled (`attempts=1`). It performs
no `models.list` call. Disabled jobs, empty catalogs or invalid local configuration
send zero requests. A crash after reservation but before dispatch can also lose
the day's request. This is an intentional at-most-once guarantee: a database and
an external API cannot provide exactly-once dispatch across ambiguous crashes.

Google may execute multiple internal searches within that single grounded API
request. One application request does not mean one Google search or a guaranteed
fixed bill. See [Google Search grounding](https://ai.google.dev/gemini-api/docs/google-search).

## Model selection and failure handling

The official `google-genai` SDK is used. `GEMINI_MARKET_MODELS` is a comma-separated
local priority list. Select the first documented grounding-capable ID, skipping
unknown/duplicate entries before dispatch. Default single primary: `gemini-3.8-flash`.
Other documented eligible IDs are `gemini-3.1-flash-lite` and
`gemini-3-flash-preview`. These were checked against Google's
[model catalog](https://ai.google.dev/gemini-api/docs/models) and grounding docs.
Account access is not guaranteed by documentation. No runtime model-listing
request is made during the daily run.

After dispatch there is NO automatic fallback. 400 reports invalid request/key
or model configuration; 401 invalid credentials; 403 permissions/project
restrictions/billing; 404 model unavailable; 429 rate limits or quota/billing
restrictions; other failures/timeouts report unavailable. Error bodies and secrets
are not logged. A 429 alone cannot distinguish transient rate limits from a
project-wide exhausted quota. Trying other models would violate the daily limit
and might encounter the same project restriction. Fix configuration/permissions
manually, or select another eligible primary for a later day's scheduled run.
`GEMINI_MARKET_RETRIES` is retained for old environment compatibility but ignored.

## Validation and cache preservation

Gemini output is only a candidate. Acceptance requires grounding references AND
an independently fetched, publicly accessible HTTPS source containing the verbatim
crop/price/unit excerpt. Crop identity, requested locality, quoted market, INR,
positive finite price, original selling unit, observation date, variety and any
min/max/modal labels are checked. Prices from another crop row, invented dates,
uncited URLs, estimates and unsupported unit conversions are rejected. Sources
must be accessible text/HTML/JSON; unsupported PDFs and unverifiable formats fail
closed. Verification means source-excerpt verification, not government certification.

Multiple markets, varieties, wholesale/retail/farm-gate/mandi types, sources and
original kg/bunch/bundle/count/etc units are preserved. Missing optional prices
remain null. Count/bunch prices are never converted to weight. The farmer's
selected selling price and existing financial arithmetic are preserved.

Only accepted records are upserted into `market_prices`. Discovery failure never
deletes or overwrites an earlier price with an unavailable value. Existing legacy
records remain stored but are not labelled verified without grounding evidence.
Default current observation age: 2 days. Cache observation/retrieval age: 7 days.
Historical usable records are explicitly stale; older records stay in MongoDB but
are excluded from displayed references. Empty cache reports unavailable and queues
the requested crop context for the next day. Finite model context/output and the
120-second total budget can leave crops without verified records; no additional
requests or invented prices compensate for incomplete coverage. Job logs record
covered and unavailable context counts.

## Exact manual Render Cron Job configuration

Source configuration exists in `render.yaml`; deployment has NOT been verified or
performed. Use the same repository/root directory containing the backend Dockerfile.

| Field | Value |
| --- | --- |
| Service type | Cron Job |
| Name | vayalconnect-market-daily |
| Runtime | Docker |
| Dockerfile path | ./Dockerfile relative to backend root |
| Docker command | python -m scripts.refresh_market_prices |
| Schedule (UTC) | 30 0 * * * |
| Local time | 06:00 Asia/Kolkata daily |
| APP_ENV | production |
| MARKET_DAILY_REFRESH_ENABLED | true |
| GEMINI_MARKET_TIMEOUT_SECONDS | 60 |
| GEMINI_MARKET_TOTAL_TIMEOUT_SECONDS | 120 |

Privately configure `GEMINI_API_KEY`, `MONGODB_URI`, `MONGODB_DATABASE`, `JWT_SECRET`
and `ENCRYPTION_KEY` on the cron service. Use the same database as the web service;
all replicas and cron services must share it for the daily claim to work. Preserve
existing credentials. Optionally configure `GEMINI_MARKET_MODELS`,
`MARKET_CURRENT_MAX_DAYS`, `MARKET_CACHE_MAX_DAYS`. Render schedules use UTC; see
[Render Cron Jobs](https://render.com/docs/cronjobs). No scheduler runs inside web
workers. Failed/unavailable discovery exits unsuccessfully for monitoring, but
another scheduler invocation still cannot repeat the consumed day's attempt.

## Verification and remaining blockers

Tests use synthetic prices and mocked SDK/database calls, never real credentials,
production writes or billable discovery. They cover consolidated coverage,
concurrent duplicate protection, crash/failure claims, zero per-crop calls,
cache-only API/Flutter requests, rejected evidence, error handling and cache
preservation. MongoDB transaction integration tests require a separate test DB.

Existing private backend environment files were left unchanged. The earlier live
probe returned HTTP 429 RESOURCE_EXHAUSTED and no verified prices. No live discovery
was repeated during this change, so current key access/quota and real consolidated
price coverage remain unverified. Project quota/billing must be checked manually;
this change does not enable billing. Inspect public evidence from a scheduled run
before claiming production discovery works.

`python -m scripts.check_market_reference --commodity Jasmine --state "Tamil Nadu"`
is now a read-only MongoDB cache probe, not a Gemini API probe. Only the scheduled
refresh command can dispatch discovery in the application paths.

## Files modified in this change

Backend paths below were synchronized between the sibling backend and Flutter's
tracked `vayalconnect-backend` copy. Existing unrelated changes were preserved.

- app/integrations/gemini_market.py
- app/services/market_discovery.py
- app/api/v1/market_prices.py
- app/core/config.py
- scripts/refresh_market_prices.py
- scripts/check_market_reference.py
- tests/test_gemini_market.py
- tests/test_market_prices.py
- render.yaml
- .env.example (example only; private .env files untouched)
- docs/GEMINI_MARKET_PRICES.md

Flutter paths:

- lib/screens/add_product_screen.dart
- lib/services/api_client.dart
- lib/services/market_price_service.dart
- lib/services/product_service.dart
- lib/utils/commerce_strings.dart
- test/market_cache_only_test.dart

Final local checks: backend `pytest -q tests`: 205 passed, 12 opt-in MongoDB
integration tests skipped, 8 existing dependency warnings. Flutter: 75 tests
passed. `flutter analyze --no-pub`: no errors/warnings, 17 existing informational
lint notices (default command exits 1 for these notices). `git diff --check`
passed. Modified backend file pairs match byte-for-byte; configured credentials
were not present in versioned/unignored source files. Live Gemini discovery and
Render deployment were not exercised.

## Quota investigation (no live API calls)

The earlier direct grounded probe targeted `gemini-3.8-flash` and recorded HTTP
429, `RESOURCE_EXHAUSTED`, an empty extracted reason-code list, and message tags
`quota`, `billing`, `limit`. Its complete Google error body was not saved.
The local backend stdout/stderr and verification logs do not contain the missing
`google.rpc.QuotaFailure` response. Therefore the exact historical quotaMetric,
quotaId, quotaDimensions, quotaValue and structured failure reason are UNKNOWN.
The tags do not prove billing was the actual cause; the earlier billing conclusion
was too specific. No request was sent to reconstruct the missing response.

Google's model pages document Search grounding for each candidate:

| API ID | Grounding support |
| --- | --- |
| [gemini-3.8-flash](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash) | Supported |
| [gemini-3.5-flash-lite](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite) | Supported |
| [gemini-3.1-flash-lite](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite) | Supported |
| [gemini-2.5-flash](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash) | Supported; documented legacy access restrictions |
| [gemini-2.5-flash-lite](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash-lite) | Supported; documented legacy access restrictions |

Keep `gemini-3.8-flash` as ONE explicitly configured primary in code defaults,
Render source configuration and the environment example. The private environment
files have no model override and remain untouched. Rationale: the user reports
available quota, this is the existing implementation's primary, and its documented
large context/output capacity suits consolidated discovery. Actual screenshot
quota numbers, active-key project association, grounding allowance and successful
generation were not independently verified. There is no evidence switching models
would fix the earlier 429. Other supported models remain manually configurable;
no automatic model fallback or retry is introduced.

Google evaluates RPM, input TPM and RPD independently, per project rather than
per key. An available request quota does not prove other limits or grounding
allowances are sufficient. Provider RPD resets at midnight Pacific, which is
separate from this application's IST duplicate-run boundary. See
[Google rate limits](https://ai.google.dev/gemini-api/docs/rate-limits).

For a FUTURE scheduled failure, the SDK's complete in-memory error object is
inspected and only allowlisted structured fields are retained: dispatched model,
HTTP status, status enum, quotaMetric/quotaId/quotaValue, model/location dimensions,
and ErrorInfo reason codes. Raw messages, project IDs, arbitrary metadata, headers,
URLs and keys are never logged or persisted. These diagnostics are stored in the
existing daily-run record and structured backend log. Missing details stay unknown.
No extra API call is needed to capture them. The whole-day reservation and cache
preservation still apply. The raw previous error cannot be recovered by this code.

Investigation validation: full backend suite 211 passed, 12 opt-in MongoDB tests
skipped, 8 existing dependency warnings; focused market/reference Flutter tests
4 passed; git diff --check passed. The seven changed files in this investigation
are app/integrations/gemini_market.py, app/services/market_discovery.py,
app/core/config.py, .env.example, render.yaml, tests/test_gemini_market.py and this
document. They are synchronized between the two maintained backend copies.
No live Google API request, production database access/write, API-key modification
or deployment was performed.

Final diagnostic-task verification: 81 focused backend tests passed; the full
backend suite passed 218 tests with 12 opt-in MongoDB tests skipped and 8 existing
dependency warnings. Four relevant Flutter cache/reference tests passed.
`git diff --check` passed. All provider calls in diagnostic tests were mocked;
the controlled diagnostic was not executed against Google.

## Authentication investigation and offline check

The controlled diagnostic reported HTTP 401, `UNAUTHENTICATED`, with
`ACCESS_TOKEN_TYPE_UNSUPPORTED`: Google rejected the authentication credential
type. This establishes the provider rejection, but does not establish whether
the credential itself, its restrictions, or the environment of that earlier
execution caused it. No live request was made to reproduce or resolve that
rejection during this investigation.

The diagnostic and scheduled provider both use `GeminiMarketPriceProvider` and
the same client factory. The inspected implementation already passed
`Settings.GEMINI_API_KEY` to `genai.Client(api_key=...)`; it did not construct an
OAuth Authorization header. The inspected local environment had no Vertex AI,
Enterprise, alternate endpoint or OAuth credential overrides, and the loaded key
matched the backend's dotenv value. Credential values were not printed. These
checks do not prove that Google accepts the credential.

Client creation now explicitly selects `vertexai=False`, `enterprise=False`,
`credentials=None`, and the official Gemini Developer API endpoint. Google Gen
AI SDK 1.75.0 sends this credential through `x-goog-api-key`, as confirmed by
mocked HTTP transport tests. OAuth token/header wrappers are rejected locally;
Google authorization API keys remain supported without an obsolete prefix
whitelist. See the [official SDK](https://googleapis.github.io/python-genai/)
and [Google API-key documentation](https://ai.google.dev/gemini-api/docs/api-key).

`app/core/config.py` now resolves `.env` from this backend directory rather than
the caller's working directory. Existing process environment variables still
take precedence. No environment files or credentials were changed.

The next safe diagnostic is entirely offline:

```powershell
Set-Location -LiteralPath 'C:\VAYAL CONNECT\vayalconnect-backend'
& '.\venv\Scripts\python.exe' -m scripts.diagnose_gemini_market --check-auth
```

This checks the constructed SDK endpoint and header names, never prints header
values, sends zero Google requests, and does not connect to MongoDB. A successful
offline check verifies client configuration only, not provider acceptance.

For a separately controlled future live investigation, the existing explicit
command remains available (not executed during this change):

```powershell
& '.\venv\Scripts\python.exe' -m scripts.diagnose_gemini_market --model gemini-3.5-flash-lite --crop Jasmine --crop Tomato --execute-one-request
```

That command sends at most one grounded generation request, consumes provider
quota, bypasses the MongoDB daily claim, and leaves cached prices untouched.
The normal daily job retains its atomic claim, consolidated crop discovery,
cache preservation, and no-retry/no-fallback behavior. HTTP 401 captures sanitized
Google status and reason information and returns without another request.

Authentication changes are limited to `app/core/config.py`,
`app/integrations/gemini_market.py`, `scripts/diagnose_gemini_market.py`,
`tests/test_gemini_diagnostic.py`, and this document, mirrored in both maintained
backend copies. Focused mocked tests: 94 passed. Full backend suite: 231 passed,
12 opt-in MongoDB tests skipped, 8 existing dependency warnings. `git diff --check`
passed. No live Google request, production data modification, credential change,
billing action or deployment was performed.
