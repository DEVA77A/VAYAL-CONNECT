# Groq market reference cache

> Historical market-specific workflow. The current deterministic Tamil Nadu
> statewide provider, source blockers, feature flags and deployment checklist
> are documented in [STATEWIDE_MARKET_PRICES.md](STATEWIDE_MARKET_PRICES.md).
> Do not activate using the older instructions below.

Implemented locally in the existing backend and its Flutter repository copy.
No deployment, commit, live discovery, production credential change or database
write was performed during implementation. The database inspection was read-only.

## Inspection and existing contracts

`products.product_name` and `products.category` are free strings. There is no crop
whitelist or separate crop/category registry in the inspected database. Farmer
onboarding stores `farmer_profiles.application.crops` as free text. The current
schema has no bilingual-name fields, but retrieval accepts explicit
`product_name_en`/`product_name_ta` aliases if supplied in stored products.
It does not invent translations or conflate rice and paddy.

Products carry a nearest `market`, optional `state`, `district` and `variety`.
Postal farm addresses/coordinates are not reliable mandi identifiers and are not
used to invent a nearest market. Missing source-location metadata is rejected.
Without an explicit market and state, the context remains unavailable. Farmer crops
are split only on explicit commas,
semicolons or newlines. An undelimited phrase remains one exact crop name.

`market_prices` is the existing cache/history collection. Read-only inventory found
it empty with commodity/market/date indexes. No data migration/deletion is needed.
`market_watchlist` and `market_daily_runs` existed in code but not the inspected
database. These are context/operational collections, not competing price stores.

The pyPricingAPI experiment and historical Gemini parsers remain for provenance
and regression testing. The legacy Gemini CLI refuses execution. Active routes, pricing service and cron use Groq only.
Legacy Gemini excerpts and unverified pyPricing rows remain in history but are
excluded from verified cache reads. Only validated retrieved source records qualify.
There is no alternate AI fallback. Existing unrelated Gemini settings are retained.

## Configuration and authentication

Configure secrets privately in the backend environment. Rotate any key shared in
a conversation. Do not copy secrets into Flutter, Git, test reports or APK assets.

```dotenv
GROQ_API_KEY=
GROQ_MODEL=openai/gpt-oss-120b
GROQ_MARKET_ENABLED=false
MARKET_DAILY_REFRESH_ENABLED=false
MARKET_CURRENT_MAX_DAYS=0
GROQ_TIMEOUT_SECONDS=60
GROQ_CONTEXT_TOKENS=131072
GROQ_MAX_COMPLETION_TOKENS=2048
GROQ_REQUEST_TOKEN_BUDGET=8000
MARKET_SOURCE_MAX_ROWS=5000
GOVERNMENT_MARKET_API_KEY=
# Deprecated; ignored for source rows.
GOVERNMENT_MARKET_UNIT=
MARKET_SOURCE_URLS=[]
```

MongoDB/JWT/encryption settings remain the application's existing settings.
Before enabling discovery, run from the backend directory:

```powershell
venv/Scripts/python.exe -m scripts.check_groq_connection
```

This sends exactly one authenticated `GET /openai/v1/models`, not an inference
request. Missing keys send zero requests. Failed authentication or connectivity
produces a sanitized message and nonzero exit, without retries. Check that the
configured production model is available to your project. Re-run this check only
after configuration changes; it is intentionally not part of the daily job.
An earlier local model-list authentication check succeeded. The key shared in the
conversation must be rotated by its owner before production use. Do not repeat the
check merely to exercise quota; rerun it after rotating the key.

The official HTTP interface is used through the existing pinned `httpx` dependency.
`openai/gpt-oss-120b` and `openai/gpt-oss-20b` are the validated production
strict-JSON models. No obsolete model name or implicit model fallback is used.
Structured outputs and tool use cannot currently be combined; source retrieval
therefore happens in the backend before the completion.

Official references checked 2026-10-13:
- [Supported models and pricing](https://console.groq.com/docs/models)
- [Strict structured outputs](https://console.groq.com/docs/structured-outputs)
- [Rate limits](https://console.groq.com/docs/rate-limits)
- [OGD mandi dataset](https://data.gov.in/resource/current-daily-price-various-commodities-various-markets-mandi)

## Source retrieval and verification

The built-in retriever fetches the fixed official OGD resource
`9ef84268-d588-465a-a308-a864a43d0070`, paginated by requested state in pages of
100, with a configurable row cap and bounded 120-second overall retrieval budget.
It does not use the obsolete provider's retry path. An HTTP failure stops that
state's retrieval, preserves the cache and records a sanitized diagnostic.

The currently documented OGD schema does not establish an explicit unit for every
row. AGMARKNET's own entry manual describes commodity standard units and local
market unit conversions. A single global unit is unsafe; the deprecated
`GOVERNMENT_MARKET_UNIT` setting is ignored. The retriever accepts only an explicit,
supported row unit and records `OGD_ROW_UNIT_MISSING` otherwise. A separately
reviewed feed may provide per-record units. Flower/count/bunch units are never
inferred. Live OGD coverage and unit semantics remain unverified.

For flowers or other sources, `MARKET_SOURCE_URLS` is a JSON array of **reviewed**
public HTTPS JSON feed URLs. It defaults empty. An operator must verify the source
organization, price semantics, actual trading unit and update cadence before
allowlisting it. Adding a URL is a trust decision, not proof that a feed is official.
No URL generated by AI is fetched. Redirects, credentials, query-string URLs and
private/reserved DNS addresses are rejected. Deployment egress policy should also
block private-network access to protect against DNS rebinding.

Feed contract (synthetic example only, never a live price):

```json
{"records":[{
  "commodity":"Example flower", "market":"Example market",
  "district":"Madurai", "state":"Tamil Nadu", "currency":"INR",
  "unit":"bunch", "price_paise":12500,
  "observation_date":"2026-10-13",
  "source":"Reviewed publisher", "source_url":"https://publisher.example/prices.json"
}]}
```

`source_url` must equal the allowlisted feed URL. Optional fields:
`min_price_paise`, `max_price_paise`, `modal_price_paise`, `variety`, `grade`,
`source_record_id`, and original decimal values/unit when actually supplied.
Accepted unit spellings are documented in `market_evidence.py`. Every price field
must be a positive integer number of paise. Dates must be current under the
configured freshness policy and cannot be in the future. Min/modal/max bounds,
crop correspondence, exact requested location and variety are checked.
Records with incomplete evidence, missing unit or invalid data are rejected.

Groq receives **all** registered contexts plus eligible retrieved evidence in one
batch. Its strict response contains context/crop IDs, status and selected evidence
ID, not price numbers. The backend rejects unknown IDs, unknown evidence, missing
contexts, duplicate context results, extra fields and mismatched crop/location.
Accepted amounts, dates, units, source names and URLs are copied from validated
retrieval records. SHA-256 evidence IDs link each result to its original source row.
Thus an AI response cannot introduce a fabricated amount or source URL.

- **Verified:** retrieved source record passes all checks and is selected correctly.
- **Unverified:** insufficient evidence; recorded as a context status, never a price.
- **Unavailable:** no acceptable current quote, missing configuration or rejected run.
- **Stale:** previously verified historical quote, explicitly labelled stale on reads.

With the default age of zero days, yesterday's observation is never today's price.
Cache reads also require retrieval less than 24 hours old for a fresh label.
Observation date and retrieval time are separate. Old verified history is retained.
No current price is guaranteed for any particular crop, including flowers.

## Daily claim and persistence

Cron and authorized manual refresh share `_id=batch:<IST YYYY-MM-DD>` in
`market_daily_runs`, inserted with majority write concern **before** loading
contexts, retrieving sources or dispatching inference. A separate 600-second
lease prevents overlap across day boundaries. Only its owner releases it.
The reservation is never deleted/reopened after a timeout, crash or write failure.
A crash before dispatch can lose that day's refresh; this is the deliberate cost
of avoiding an ambiguous second API request. A skipped duplicate sends zero.

A successful discovery with evidence sends **exactly one Groq completion POST**.
Preflight failure, no crops, no current evidence or oversized complete batch sends
zero. Authentication failures, rate limits, timeouts, malformed output and MongoDB
write failures never trigger retries. The job does not run on backend startup,
screen opening, GET requests or crop upload. No per-crop AI loop exists.

The complete batch includes products of all statuses, persistent watchlist contexts
and farmer onboarding crop names. All categories are arbitrary strings. Context
IDs deduplicate identical crop/location/category/variety requests. Canonical crop
IDs are deterministic hashes of normalized registered crop name and category;
they are not product/farmer IDs. Renaming a crop/category changes that identity.
Explicit bilingual aliases support source matching without guessed translations.

Accepted records upsert in `market_prices` by deterministic `discovery_key`, which
includes crop identity, market/location, variety, unit, date and source. New dates
preserve history. `created_at` is insert-only; `updated_at`, retrieval timestamp,
`last_successful_refresh_at`, category, currency, evidence/source snapshot and
verification metadata are stored. The code-defined sparse unique `discovery_key` and new
crop/date plus category/location/date indexes support reads. No existing record
is deleted or rewritten by a schema migration. Writes may partially succeed before
a database failure; successfully stored rows still contain validated source evidence,
prior history remains intact, and the run is recorded failed if possible.

Daily documents store completion state, model, sanitized diagnostics, context
statuses, timestamps and request/token statistics. An interrupted run remains
reserved. The existing operational TTL retains completed run diagnostics for 90
days; cache history has no deletion policy added by this feature.

## API and Flutter compatibility

- `GET /api/v1/market-prices`: cached list with `commodity`, `commodity_id`, `category`, `market`,
  `state`, `district`, `variety`, `limit` (1–100), `offset`.
- `GET /api/v1/market-prices/latest?commodity=...`: latest matching cached quote.
- `GET /api/v1/market-prices/filter-options`: dynamic crop/category options from
  products, with the existing Tamil Nadu district suggestions if none are stored.
- `GET /api/v1/products/price-reference`: existing farmer reference contract.
- `GET /api/v1/market-prices/status`: existing admin authorization, cache status.
- `POST /api/v1/market-prices/refresh`: existing admin authorization, same daily
  claim, no force/retry argument; disabled until explicitly enabled in configuration.

All GETs read MongoDB only: no context registration write, HTTP retrieval or AI.
The old `MARKET_SOURCE_UNAVAILABLE`/503 empty-price response is retained for Flutter
compatibility. `records`, page `count`, `live=false`, unit and legacy reference
fields retain their shapes. `last_successful_refresh_at` is additive.
The legacy `government_reference_price_paise` name is preserved for compatibility;
the UI names the actual source and does not assume all prices are governmental.

Flutter only requests the backend. Crop entry loads registered categories and
accepts a new arbitrary category without a redesign. Existing Tamil translations,
loading/errors, source/date/unit/stale labels and role permissions are preserved.
The reference widget hides explicit unverified records. Lookup never assigns the
farmer selling-price controller. Commission and farmer-entered price remain governed
by the existing pricing engine. Only known mass conversions or equal units are
comparable; bunch/bundle/count are not converted to kilograms.

## Token limits and cost

The documented 120B context is 131,072 tokens, max completion 65,536. Published
pricing is $0.15/M input tokens and $0.60/M output tokens. Free-plan published TPM
is 8,000 (project limits may differ); developer-plan limits are higher. One daily
request does not remove TPM, context or output limits. Do not assume it is free.

Typical rough estimates: 100–200 input tokens per context, 150–250 per evidence
row, about 180–200 output tokens per selected context, plus schema/prompt overhead.
For 25 contexts with one evidence row each, approximately 6,500–12,000 input and
4,500–5,000 output tokens (~$0.0037–$0.0048 at published rates), excluding retrieval
costs. Reasoning/tokenizer variation means actual provider usage can differ.

The implementation conservatively estimates input using UTF-8 byte count plus
overhead and reserves the full configured completion allowance. This intentionally
overestimates, particularly for Tamil. It checks context/quota budget and output
capacity before dispatch, and never truncates/splits a complete batch. Defaults
may refuse a large catalog. Confirm your project's limits, then explicitly increase
`GROQ_REQUEST_TOKEN_BUDGET` and `GROQ_MAX_COMPLETION_TOKENS` (and align these on web
and cron). If it still cannot fit, reduce redundant **retrieved evidence** through
a reviewed source-side aggregate that preserves every crop/context, or arrange
a suitable quota. Do not exclude registered crops or split into multiple requests.

## Render configuration (not deployed)

The Git-tracked repository-root `render.yaml` now declares the cron service using
`vayalconnect-backend` as its Docker context. The standalone backend blueprint also
describes that service for backend-root deployments. Apply only the blueprint that
matches the deployment repository; never create two independent jobs. Actual Cron
Job existence in the Render dashboard was not verified. Editing YAML does not
create or change a job until
you explicitly apply the blueprint. Do not enable a second independent scheduler.

After review and production-resource approval, configure exactly one Render Cron
Job with the same backend source/root directory and Dockerfile as the web service:

- Command: `python -m scripts.refresh_market_prices`
- UTC schedule: `30 2 * * *` (08:00 Asia/Kolkata).
- Existing `MONGODB_URI`, identical `MONGODB_DATABASE`, `JWT_SECRET`, valid
  `ENCRYPTION_KEY`, `APP_ENV=production`.
- All Groq, source and budget settings above, `GROQ_MARKET_ENABLED=true` and
  `MARKET_DAILY_REFRESH_ENABLED=true` only after successful configuration checks.

Prefer private environment groups for shared secrets; never put key values in YAML.
Both blueprints keep discovery and daily refresh disabled. When enabled, the cron
job and web service share the same daily claim in MongoDB. Do not press Run Now for a live test without
explicit authorization; it would consume today's discovery attempt.

## Local verification and activation steps

1. Configure a rotated key privately and run the non-inference model-list check.
2. Verify a reachable feed's actual response, terms, per-record unit, observation
   date, crop and location coverage. Allowlist only reviewed explicit-unit feeds.
   Flower feeds must supply actual flower trading units.
3. Confirm quotas and set a complete-batch budget; keep discovery disabled meanwhile.
4. Use mocks: `venv/Scripts/python.exe -m pytest -q`, then in Flutter
   `flutter test` and `flutter analyze`. Integration Mongo tests require an explicitly
   configured isolated replica set; they must never use the production database.
5. Review the test/report results. Authorize at most one live discovery separately
   if desired, with an isolated database and the daily claim in place.
6. Preview additive indexes with `venv/Scripts/python.exe -m scripts.ensure_market_indexes`.
   In staging only, run `python -m scripts.ensure_market_indexes --apply --confirm-database <staging-db>`,
   then check query results.
   The command is idempotent and never drops records. A production rollout needs
   separate approval and the explicit `--allow-production` gate.
7. Verify exactly one Render dashboard Cron Job before enabling its flags.

Read-only source audit on 2026-10-13: the OGD request timed out; the documented
[pyPricingAPI](https://github.com/ag-chitta/pyPricingAPI) endpoint failed DNS
resolution; a single GET to an AGMARKNET 2.0 API endpoint returned HTTP 403.
No response yielded a verified current price, unit or date. The pyPricing repository's
MIT software license does not establish rights to re-publish its underlying data.
The official [AGMARKNET entry manual](https://agmarknet.gov.in/DailyDataEntry/UserManual.pdf)
describes per-commodity standard units and local market conversions. No flower
coverage has been verified. The observed registered `civai` market could not be
matched to a documented mandi; retain its user-owned value until the owner confirms
the correct market and state. The database inspection was read-only and its
`market_prices` collection was empty; new indexes await staged and approved rollout.

Remaining external dependencies: a rotated Groq credential, a reachable and usable
current source with explicit units and usage rights, source coverage for the actual
crop/location catalog, and verification of the Render dashboard job. No live
pricing integration is claimed operational until those checks succeed.
