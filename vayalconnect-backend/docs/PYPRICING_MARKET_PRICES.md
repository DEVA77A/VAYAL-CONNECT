> Superseded: active market discovery now uses [Groq evidence selection](GROQ_MARKET_PRICES.md). This file documents a retired implementation.

# pyPricingAPI market reference implementation — activation blocked

Investigation started 2026-10-12; final verification completed 2026-10-13 IST.
The adapter and cached application workflow are
implemented and tested offline. Current live data, crop coverage and the service's
continued availability could not be verified. This is **not production-ready live
price discovery**. `PYPRICING_ENABLED` defaults to false in code and the maintained
backend Render blueprint. Do not activate it until the following blockers are resolved.

## Provider evidence and blockers

Sources: [README](https://github.com/ag-chitta/pyPricingAPI/blob/main/README.md),
[APMCs](https://github.com/ag-chitta/pyPricingAPI/blob/main/APMCs), and
[MIT license](https://github.com/ag-chitta/pyPricingAPI/blob/main/LICENSE).

The published GET endpoint is
`https://k14y5popkj.execute-api.ap-south-1.amazonaws.com/stage/commodities`.
Required parameters are `place` (a place or comma-separated places), `radius`
(integer km), and `type` (`current` or `historical`). Optional `output=String`
and `language=ENGLISH` request the documented formatted output. `commodities`
is an optional prefix filter, not an exact commodity/variety matcher; the adapter
does not use it. State/national queries are weekly aggregates, and are not used.

Exactly one HTTP attempt was made, for `place=Coimbatore&radius=60&type=current`.
It failed before HTTP with `httpx.ConnectError: [Errno 11001] getaddrinfo failed`.
No provider HTTP status or response was obtained. Requests for Madurai, individual
crops, historical prices and flowers were stopped rather than repeat calls to
the same failing hostname. An independent Google Public DNS lookup returned
HTTP 200, DNS Status 3 (NXDOMAIN), zero A records, and an AWS API Gateway parent
zone SOA. That DNS lookup is not a Gemini or paid AI request.

**No crops or locations were verified through live prices.** Madurai is listed
as a documented uppercase available APMC. Coimbatore is not in that published
uppercase market list; nearby ANNUR/ANAIMALAI are documented, but their current
availability and distances were not independently verified. The README's price
examples are dated 2022 and are documentation examples, not current observations.
Flower support, tomato/onion/coconut coverage, current/historical behavior, rate
limits, uptime/SLA and hosted-service pricing/terms remain unverified. The
repository publishes no complete structured JSON row schema or separate commodity
catalog. The client therefore rejects unknown schemas rather than invent mappings.

The MIT repository license permits commercial use of its software/documentation
with notice preservation. It does not independently establish the hosted
service's continued operation, free usage terms, or all upstream data rights.
No noncommercial restriction was found. See the included third-party notice.

## Inspection and implementation plan

Inspected the Flutter Git repository (`main`, HEAD `58fcc93`, last five commits)
and all pre-existing modifications. The standalone backend is not a separate Git
repository; its tracked duplicate lives inside Flutter. Inspected market
provider files (government and Gemini), routes, schemas, repositories, pricing
service, database/index declarations, authentication dependencies, cron script,
Dockerfile, Render blueprints, requirements, pytest conventions, and relevant
commerce tests. Database structure was inspected from code, **not production Atlas**.

Flutter inspection covered market models/services/screens/cards, Add/Edit Crop,
API client, product service, translations, navigation and tests. Categories and
product names are free text in the existing backend schemas; neither the new
adapter nor refresh service restricts crops to the filter-options list.

Plan implemented: add an isolated bounded provider adapter; reuse the existing
cache/daily claim; expose read-only admin status; extend price metadata additively;
keep Flutter cache-only and farmer selling prices separate; test without live data.

## Contract and validation

The client uses the documented `output=String` format only, accepting a JSON
string or the documented `data.value` string wrapper. Each price line must have
the documented commodity, numeric price, `RS/Qui`, market and ISO date layout.
Negative/non-finite/malformed prices, invalid/future/missing dates, unknown
currency/units and malformed feeds fail closed. Zero is preserved as zero,
distinct from missing data. An empty valid feed stores nothing.

`RS` is interpreted as INR in this Indian-price documentation. The original
`Qui` token is preserved. Its physical meaning must be explicitly confirmed
before enabling any conversion to KG; no conversion is currently performed.
The formatter does not identify modal/minimum/maximum or trade type. These remain
unknown, and no modal, minimum, maximum, variety or district is invented.

Source name is pyPricingAPI (Chitta); observation date and retrieval time are
stored separately. `verification_method=provider_reported_quote` means a quote
validated from the provider response, not independently checked against an eNAM
bulletin or an official government price. Existing `verification_status` remains
for compatibility, and the UI labels these records “Source-reported market reference”.
No estimate or synthetic fixture is presented as live data.

Matching normalizes case/whitespace and supports only safe aliases for ground
nut/groundnut and the documented urad (black gram)/black gram label. Paddy and
rice remain separate. The provider crop label and farmer's original crop name
are both preserved. A requested variety cannot match a quote without a variety.
New crops/flowers match only if an actual source quote exists.

Only an exact requested market listed in the documented Tamil Nadu APMCs is
accepted. Nearby radius results are not silently substituted: no independently
verified distance data is available. A district-specific lookup remains unavailable
when the source does not provide district metadata. No Karnataka substitution,
state/national aggregate or guessed locality is used.

## Cache, scheduling and API

Reuse `market_prices`, `market_watchlist`, `market_daily_runs`, and the existing
unique sparse `discovery_key` index. No collection/index is removed and no
production migration was run. Stable upserts identify source/commodity/market/
date/unit/variety; provider case/alias variations do not create duplicates.
Empty/failed refreshes never delete or overwrite valid cached prices. Historical
validated cache is retained and labeled stale, including previously verified
Gemini records. No Gemini generation, model listing or fallback occurs in the
application's market workflow; Gemini source files and manual diagnostics remain.

The daily service collects deduplicated active listing and registered watchlist
contexts across categories. It sends at most one shared multi-location GET,
without per-crop calls, retries or redirects. Maximum 20 locations, 1 MB body,
5-second connect/15-second read timeout and 30-second total HTTP budget. More than
10000 deduplicated contexts fails explicitly before dispatch. These are
conservative application bounds, not claims about undocumented provider quotas.
Oversized batches fail explicitly rather than silently drop locations.

Existing majority-acknowledged unique `_id=batch:YYYY-MM-DD` reservation uses IST
and stays consumed after failure/crash. A 120-second persistent `refresh-lock`
lease also prevents overlapping requests across day boundaries and expires after
a crash. Reservations precede HTTP; an ambiguous reservation/lease error prevents
dispatch. The cache can remain stale after a failed attempt. Attempt/status/
completion timestamps and successful refresh times are recorded in existing runs.
When disabled, the cron command returns before database/provider access.

Existing GET `/api/v1/market-prices`, `/latest`, `/filter-options` and authenticated
farmer GET `/api/v1/products/price-reference` retain their response fields and
unavailable behavior. These read cache and may register a watchlist context;
they never refresh externally. New GET `/api/v1/market-prices/status` uses the
existing ADMIN dependency and reports last attempt/success plus activation state.
Farmers/buyers cannot access it. There is no externally callable refresh route.

Additive record fields: `commodity_id`, `quote_type`, `freshness_status`.
Reference fields additionally expose currency and verification method. No
listing price, order, commission, payment, cart or transaction record is updated
by refreshing prices. Existing financial calculations still use the farmer's
selling price for public listing creation and editing.

## Flutter

Existing navigation, layout and colors remain. Cached records show source,
market/state, original unit, price type (unknown when unspecified), observation
date, currency and stale/source-reported labels. Unavailable responses have an
English/Tamil message. User retries issue another backend GET only. The model
adds nullable quoted price metadata so zero remains distinct from missing.
The reference widget does not alter the farmer's selling-price controller.
All new fixed UI labels use the existing translation catalog.

## Render configuration — not deployed or verified active

The maintained backend `render.yaml` retains the existing Docker cron definition:

- Name: `vayalconnect-market-daily`
- Repository root directory: `vayalconnect-backend` for the Flutter repository
- Runtime: Docker; Dockerfile `./Dockerfile` within that directory
- Docker command: `python -m scripts.refresh_market_prices`
- Schedule: `30 0 * * *` UTC = 06:00 Asia/Kolkata daily
- Environment: existing application MongoDB/database, JWT/encryption settings;
  `APP_ENV=production`, `MARKET_DAILY_REFRESH_ENABLED=true`,
  `PYPRICING_ENABLED=false`, `PYPRICING_RADIUS_KM=60`.

The Flutter-root blueprint currently defines only the web service. Do not assume
it provisions this cron. A separate dashboard cron or correctly rooted backend
blueprint is needed after provider verification. No Gemini key is required by
the new workflow; existing Gemini configuration is preserved. No Render setting
was changed and no deployment/scheduler activation was performed. Do not enable
pyPricingAPI until its current endpoint, data, location/unit semantics and terms
are verified. A restored endpoint may require a documented endpoint update.

## Local commands (isolated data)

Use an existing local replica set; the sample process environment isolates the
database without editing private environment files. Do not run against production
Atlas for local development or tests.

```powershell
Set-Location -LiteralPath 'C:\VAYAL CONNECT\vayalconnect-backend'
$env:APP_ENV = 'development'
$env:MONGODB_URI = 'mongodb://localhost:27017/?replicaSet=rs0'
$env:MONGODB_DATABASE = 'vayalconnect_local'
$env:PYPRICING_ENABLED = 'false'
& '.\venv\Scripts\python.exe' -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

```powershell
Set-Location -LiteralPath 'C:\VAYAL CONNECT\vayalconnect-flutter'
& 'C:\src\flutter\bin\flutter.bat' run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:8000
```

For a desktop/browser target use `http://localhost:8000`; a physical phone needs
the development computer's LAN address. No existing release configuration changes.

## Modified files and verification

Backend: app/core/config.py; app/integrations/pypricing_market.py;
app/services/market_discovery.py; app/services/pricing_service.py;
app/api/v1/market_prices.py; app/repositories/pricing.py;
app/schemas/market_price.py; scripts/refresh_market_prices.py; render.yaml;
tests/test_gemini_market.py (legacy provider injection and lease fixture only);
tests/test_pypricing_market.py; docs/PYPRICING_MARKET_PRICES.md;
docs/PYPRICING_THIRD_PARTY_NOTICE.md. These are synchronized with the tracked copy.

Flutter: lib/models/market_price.dart; lib/services/market_price_service.dart;
lib/screens/market_prices_screen.dart; lib/widgets/market_reference_view.dart;
lib/utils/commerce_strings.dart; test/pypricing_market_ui_test.dart.

Existing unrelated Git changes remain. No secrets/environment files, releases,
APKs, production database records, Git commits/pushes or deployments were changed.
Final verification results:

- Backend complete suite: **291 passed, 12 skipped, 8 existing dependency warnings**.
  The skipped tests require opt-in MongoDB/replica-set integration configuration;
  no production database was connected. Existing order, commission and payment
  unit tests passed. The 60 new provider tests use only synthetic/mock data.
- Flutter complete suite: **82 passed**. This includes loading, unavailable,
  stale, Tamil, cache-only retry and selling-price preservation tests.
- `flutter analyze --no-pub`: **no errors or warnings**, 17 pre-existing
  informational lints in unrelated files; the default command exits 1 for infos.
  Scoped `dart analyze` of all six changed Dart files: **no issues, exit 0**.
- Dart formatter check of changed files: **no changes required, exit 0**.
- Backend `compileall -q app scripts`: passed. No backend formatter/linter is
  configured in this repository; ruff/black/flake8 are not installed.
- `git diff --check`: passed. All 13 changed backend file pairs match.
- Android **debug APK build passed** using final source in a fresh isolated copy:
  `.local-verification/pypricing-android-94894500e6bc467fb84cdf6b9f39f8af/`.
  Its APK remains inside that ignored verification directory and uses the local
  emulator backend URL. No signing credentials were copied or changed. All eight
  pre-existing APK hashes remain unchanged. No signed release/device test was run.

Backend verification command (run in the tracked backend copy with the existing
standalone virtual environment; process-only empty AI key prevents accidental
credential use in tests):

```powershell
Set-Location -LiteralPath 'C:\VAYAL CONNECT\vayalconnect-flutter\vayalconnect-backend'
& 'C:\VAYAL CONNECT\vayalconnect-backend\venv\Scripts\python.exe' -c "import os,pytest; os.environ['GEMINI_API_KEY']=''; raise SystemExit(pytest.main(['-q','tests']))"
```

Flutter verification commands:

```powershell
Set-Location -LiteralPath 'C:\VAYAL CONNECT\vayalconnect-flutter'
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub
```

Acceptance limits: production cache contents and active Render scheduling were
not inspected or changed. Current live provider behavior, all named crop/flower
coverage, measurement meaning beyond the original `Qui` token, district/distance
metadata and hosted usage terms remain unresolved. No live market-price success
or production-readiness claim is made. No Gemini generation was performed.
