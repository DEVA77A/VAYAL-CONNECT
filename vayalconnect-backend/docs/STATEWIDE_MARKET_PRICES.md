# Current verified Uzhavar Santhai integration — 13 October 2026

This section supersedes the older source/access and modal calculation instructions
below. The historical implementation audit is retained for context.

## Verified source and explicit mappings

Official website: https://www.agrimark.tn.gov.in/
The homepage Angular `getPrice()` posts an empty body to
`https://www.agrimark.tn.gov.in/home/us_dist_report_api/{DD-MM-YYYY}/{crop_id}`.
No credentials or API key are needed. The crop-wise table labels min/max INR/kg.
Response content is JSON even though the server advertises text/html.

Only Tomato=8, Banana (fruit)=27, Jasmine=109, Marigold=107 are mapped. Tested
aliases include Tomato/தக்காளி, Banana fruit/Banana (fruit)/வாழைப்பழம்,
Jasmine/மல்லிகை, Marigold (English only; Tamil flower names can be ambiguous). Generic Banana, Banana stem, Paddy, Rose,
and ambiguous aliases are unavailable. No other ID is guessed. Catalogue entries
alone do not prove daily reporting. Grain coverage is not implemented.

`app/integrations/tn_market.py` uses the existing httpx dependency: 10-second
connect, 25-second HTTP timeout, 120-second batch limit, 2 MB decoded-response
limit, configured row cap, no retries/redirects, no auth/cookies/proxy credentials.
A supported crop is requested once per batch even with multiple aliases.
Malformed markets are rejected individually with count-only diagnostics. Dates
and crop identity come from the request URL; the raw response omits both. Any
contradictory supplied metadata is rejected. District is explicitly Not provided;
no district is inferred from a market name. `qty` is unused because its unit is
unknown. Source `modal` is unused because its independent meaning is unverified.

## Calculation and existing cache integration

The legacy modal median remains available for historical OGD evidence only.
For Uzhavar Santhai, each market contributes the midpoint of its documented
min/max range, rounded half-up to integer paise. The reference is the median of
these distinct-market midpoints, again half-up. Method:
`median_distinct_market_range_midpoint`. This is an application calculation,
not an official statewide or wholesale mandi price. UI labels the calculation
and its Uzhavar Santhai provenance explicitly. Same-market conflicting ranges
are excluded; currencies, dates, endpoints, units, variety, grade and market types
remain separate. At least MARKET_STATEWIDE_MIN_OBSERVATIONS (default 3) valid
markets are required. Zero lower bounds are valid; all-zero observations cannot
supply a positive reference under the existing usable-price contract.

Existing market_prices upserts, source_records, date freshness checks, daily
claim and cross-day lease are reused. Legacy evidence hashes are preserved.
Partial crop failures retain successful independent crop groups and structured
failure diagnostics; no cache rows are deleted. Ordinary GETs never request the
external source. Failed/insufficient refreshes preserve the last good history;
stale observations are marked stale and never treated as current.

## Live verification and limitations

The implemented client retrieved 251 valid observations dated 2026-10-13:
Tomato 120 markets, Banana fruit 75, Jasmine 27, Marigold 29. All four derived
references passed the same provenance reconstruction used by cache reads.
This check was HTTP-only: no production or local database was written.
Availability at 08:00, publisher completion time, long-term reliability, usage
limits, complete statewide coverage and production Render egress remain
unverified. Uzhavar Santhai is a distinct market type, not a wholesale substitute.

## Exact activation/configuration steps (no production changes made)

1. Use the nested backend under the Flutter Git root as deployment input; relevant
   standalone source/tests/docs are synchronized. Intentional standalone-only
   scripts/recover_admin.py remains untouched.
2. Review official source access/usage conditions and the midpoint policy. Validate
   live records from staging/Render, especially whether today's records exist at
   08:00 IST. Never relabel yesterday's records as today to fill a missing cache.
3. In an isolated staging DB, dry-run/review the existing additive index script,
   then apply indexes only with its explicit database confirmation. Configure
   normal backend credentials privately; this source needs NO government API key.
4. Review and explicitly enable staging MARKET_STATEWIDE_ENABLED,
   MARKET_SOURCE_VERIFIED, MARKET_DAILY_REFRESH_ENABLED. Keep generation flags off.
   Run `python -m scripts.refresh_market_prices`; inspect validated cache, leases,
   unavailable/stale states, partial failures and farmer-price independence.
5. Render Cron Job: Docker runtime, same reviewed backend Dockerfile/context and
   database as the web service, command `python -m scripts.refresh_market_prices`,
   UTC schedule `30 2 * * *` (08:00 IST). In the root blueprint the Dockerfile is
   `./vayalconnect-backend/Dockerfile` with context `./vayalconnect-backend`;
   the backend-only blueprint uses `./Dockerfile`. Apply only one blueprint.
   Ensure exactly one active job. Existing daily Mongo claim prevents overlap and
   rerun duplication; same-day reruns skip an already reserved attempt, including
   failures. No automatic retry is introduced.
6. Review production config explicitly before enabling those three flags. Current
   defaults and Render blueprint flags remain disabled and unchanged. No active
   production cron, deployment or production refresh was verified or performed.
7. Farmer forms use localized hintText examples. Price hint is exactly 10; its
   controller stays empty for new listings. Cached reference lookup is debounced
   for supported crop names and never changes the selling-price controller.
   Existing persisted values still populate edit forms normally.

---

# Tamil Nadu statewide reference workflow and deployment checklist

This is the current workflow; it supersedes the earlier market-specific Groq
and pyPricing activation instructions. Implementation is local. Live source
coverage is NOT verified. All activation flags remain false.

## Source evidence and access blockers

Primary resource: https://www.data.gov.in/resource/current-daily-price-various-commodities-various-markets-mandi

The existing resource candidate is `9ef84268-d588-465a-a308-a864a43d0070` at
`https://api.data.gov.in/resource/9ef84268-d588-465a-a308-a864a43d0070`.
Authentication uses backend-only `GOVERNMENT_MARKET_API_KEY` in the `api-key`
query parameter. Never log full request URLs. Reconfirm this ID against the
official resource API tab when the portal becomes accessible; do not call an
unreviewed substitute endpoint. No response example in tests proves this API works.

Audit: one bounded authenticated Tamil Nadu request (`limit=5`, `offset=0`)
timed out after 15 seconds. The resource page returned 503 through the browser
tool. No actual observation date, commodity/variety, record count or trading unit
was established. No crop category or flower coverage can therefore be claimed.
The Tamil Nadu department https://www.agrimark.tn.gov.in/ returned HTTP 200 in
the local read-only check, but the public links inspected did not establish a
documented programmatic price feed or its usage contract. No alternative was
activated, no restrictions bypassed, and no failing endpoint repeatedly retried.

Expected parsing contract (a hypothesis tested synthetically until live schema
verification): JSON `status=ok|success`, integer `total`, list `records`;
row `commodity`, `state`, `district`, `market`, `arrival_date` (`DD/MM/YYYY`),
`modal_price`, optional min/max/variety/grade/ID, and explicit supported `unit`.
Rupee decimal values convert exactly to integer paise (no fractional paise).
Missing or changed fields and invalid dates/values fail closed. A missing unit
is rejected, even if `GOVERNMENT_MARKET_UNIT` is configured. That deprecated
global unit is never used. If the real OGD response omits units, activation
requires a separately reviewed, commodity-specific official unit contract and
a tested adapter; do not infer quintals for every crop or kilograms for flowers.

Pagination: one state, 100 rows/request, offsets advanced by actual returned
count, total must remain consistent, default maximum 5,000 rows, 2 MB/page,
15-second request timeout, 120-second overall retrieval budget. Empty pages
before total, unexpected oversized pages, total changes, truncation, timeout,
401/403/429 and malformed data prevent statewide calculation from partial data.
No retries or redirects. Exact official account rate limits remain unverified;
confirm in the OGD portal before activation and lower the local row cap if needed.

Government Open Data License guidance: https://www.data.gov.in/godl . Retain
provider, source URL and license attribution; derivative medians must not imply
government endorsement. Confirm this particular resource's license/access
conditions when the page is available. The app attributes data.gov.in AGMARKNET
and labels its calculation separately from the source's observations.

## Deterministic calculation policy

`StatewideMarketProvider` is the scheduled application provider. It reuses
`MarketEvidenceRetriever`, the existing daily Mongo claim/lease, repository and
collection. It requests the primary source only, with Tamil Nadu state context;
farmer market/district/state values never restrict statewide source retrieval.
Registered names/categories/explicit bilingual aliases come from products,
watchlist and farmer onboarding. Unknown names remain unavailable; no guessed
translations or crop whitelist. `civai` was not established as a valid mandi;
existing user records are untouched and this value is irrelevant to statewide
lookup. Corrections of listing metadata remain owner-controlled.

Current policy:
- Freshness: observation must be TODAY in Asia/Kolkata (`MARKET_CURRENT_MAX_DAYS=0`).
  Cache retrieval also expires after 24 hours and re-evaluates staleness on every GET.
- Minimum: 3 DISTINCT market/district pairs, configurable upward via
  `MARKET_STATEWIDE_MIN_OBSERVATIONS`. A single market cannot multiply its weight.
- Group by source commodity, source variety, grade, currency, compatible unit,
  source endpoint and observation date. Missing variety/grade form their own
  groups; never blend with named varieties/grades or other dates.
- Unit aliases only: kilogram/kg, quintal/qtl, tonne/ton, piece/count. No
  cross-weight normalization is needed for this initial statistic. Source units
  and values remain intact in the original records. Bunch, bundle, dozen and
  other approved units stay separate; no bunch-size or flower-weight inference.
- Exact duplicates have one market weight. Conflicting same-market modal prices
  exclude that market from the group. All accepted original observations remain
  in audit history, including insufficient groups; they are not statewide prices.
- Median of source MODAL values: sorted middle amount for odd count; arithmetic
  mean of two middle values for even count, rounded half-up to integer paise.
  No arrival-volume weighting; available records do not prove exhaustive coverage.
- Every sufficiently populated group is returned separately. Farmer reference
  chooses the newest fresh compatible group, displays its variety/unit, and
  returns all groups for transparency. It never pools different varieties.
- Fallback: insufficient/missing/invalid observations produce unavailable. No AI
  estimate, farmer selling price, unofficial provider or stale-as-current fallback.

Label: **Tamil Nadu statewide reference price — calculated from available market observations**.
This is an application calculation from available markets, not an official
government statewide price. Tamil translation exists in the Flutter catalog.

## Groq and quotas

The existing strict evidence-ID Groq provider remains available and tested, with
`openai/gpt-oss-120b`, one whole-batch dispatch, no retry/fallback and pre-dispatch
context/output/token-budget rejection. It is NOT invoked by the deterministic
statewide provider. Consequently statewide runs use **zero generation requests**,
which satisfies the at-most-one requirement without unnecessary inference costs.
Keep `GROQ_MARKET_ENABLED=false`. Future AI mapping must reuse the single-dispatch
provider and undergo review; do not infer units/prices or accept model-owned data.
Official model docs: https://console.groq.com/docs/model/openai/gpt-oss-120b .
Configured context 131,072; request budget 8,000 includes 2,048 output reserve.
UTF-8 byte count plus schema/framing is a conservative input-token upper bound.
Actual account TPM/RPM/RPD and model pricing require dashboard verification.
No inference request was performed during this implementation.

## Cache, endpoints and locks

No new price collection. `market_prices` retains original source observations
(`retrieved_source_record`) and additive calculated rows (`statewide_source_median`).
Calculated rows embed contributing `source_records` and their evidence IDs,
original values/units/locations/dates, count, method, minimum and retrieval time.
GET validation reconstructs the calculation; tampered amounts/counts/provenance
are rejected. Unique sparse `discovery_key` upserts include crop/location/variety/
grade/unit/date/source and method for statewide rows. Existing documents and
financial collections are never migrated or deleted.

`GET /api/v1/market-prices` and `/latest` default to `scope=statewide`. Legacy
market observations remain accessible with `scope=market`. Pagination and crop,
category, variety and commodity-ID filters remain. Statewide lookup ignores
farmer market/district and uses Tamil Nadu. Empty cache retains the established
503 `MARKET_SOURCE_UNAVAILABLE` response. GETs only read MongoDB.
Authenticated farmer `/api/v1/products/price-reference` requires crop and unit;
market is optional. Upload preview and selling-price calculations read statewide
cache; only valid weight/count conversions are shown, and farmer payout is
independent. Old snapshots remain history. Admin POST `/market-prices/refresh`
requires all activation gates and consumes the same daily claim as cron.

Daily IST `batch:YYYY-MM-DD` claim uses Mongo unique `_id` and majority writes
before retrieval. A 10-minute lease prevents overlap across date boundaries,
renewed before discovery; expired owners cannot dispatch. Daily claims are never
reopened after ambiguous failures. A crash can lose that day's attempt, but cannot
cause retries. The next day uses a new key; leases expire and release in finally.
Statuses distinguish reserved/completed/unavailable/failed/busy/lease_expired.
Claims' completed timestamps have a 90-day TTL. Original prices retain history.
Partial DB write failure may leave validated new observations or cache rows but
the run stays FAILED, never success. Existing valid rows remain untouched.

## Local checks and staging checklist

1. Work from the Git root `vayalconnect-flutter`; its nested backend and root
   `render.yaml` are deployment inputs. Standalone backend is the local working
   copy; mirror relevant files only. Do not apply both Render blueprints.
2. Owner rotates the previously exposed Groq key privately. No key is requested
   in chat; no automatic rotation. Groq is optional for this deterministic path.
3. Configure staging `APP_ENV`, `MONGODB_URI`, `MONGODB_DATABASE`, private
   `JWT_SECRET`, `ENCRYPTION_KEY` and `GOVERNMENT_MARKET_API_KEY`. Keep all market
   flags false while verifying live schema, dates, terms and per-row unit evidence.
4. Run `.\venv\Scripts\python.exe -m pytest -q`; ordinary source/Groq tests are
   mocked. Mongo integration tests opt in only against the exact loopback replica
   URI `mongodb://127.0.0.1:27019/?replicaSet=vayal_verification`, with generated
   test databases. Never set integration-test URI to Atlas.
5. `python -m scripts.ensure_market_indexes` is dry-run and does not connect.
   For an isolated staging database only, run
   `python -m scripts.ensure_market_indexes --apply --confirm-database <staging-name>`.
   Additive unique/index creation can fail on existing duplicates; inspect and
   propose remediation without deleting data. Production application is separate
   approval and additionally needs `--allow-production`.
6. Separately authorized staging source refresh: set `MARKET_SOURCE_VERIFIED=true`,
   `MARKET_STATEWIDE_ENABLED=true`, `MARKET_DAILY_REFRESH_ENABLED=true` only after
   evidence gates pass, keep Groq false, and run `python -m scripts.refresh_market_prices`.
   Compare source records against embedded provenance; test stale/unavailable
   prices, flowers separately, authorization and farmer payout independence.
7. Render Docker web service uses backend Dockerfile/context, Uvicorn on `$PORT`,
   health `/health`. One cron uses same image/database/env and
   `python -m scripts.refresh_market_prices`, UTC `30 2 * * *` = 08:00 IST.
   Dashboard job existence/environment remains UNVERIFIED. No in-process price
   scheduler and no restart refresh. Verify exactly one job in Render before deployment.
8. Configure actual trusted web `CORS_ORIGINS` (existing blueprint wildcard needs
   deployment review), auth/OTP/payment variables for applicable features, persistent
   media storage/base URL, Mongo network allowlist and backups. Confirm `/health`
   reports connected in staging. Production health GET timed out in this audit.
9. Flutter API URL defaults to `https://vayal-connect.onrender.com`; staging uses
   `--dart-define=BACKEND_BASE_URL=<staging-https-url>`. Run `flutter test --no-pub`
   and `flutter analyze --no-pub --no-fatal-infos` with SDK `C:\src\flutter`.
10. Release signing requires private `android/key.properties` and its keystore;
    never commit either. Build only in a fresh isolated copy, then copy APK to a
    NEW versioned artifact filename. Do not overwrite `app-release.apk` or any
    existing release. Inspect signer/application ID/version and test staging on a
    device before release distribution; never uninstall the owner's installed app.

Required market variables: `GOVERNMENT_MARKET_API_KEY`, `MARKET_STATEWIDE_ENABLED`,
`MARKET_SOURCE_VERIFIED`, `MARKET_DAILY_REFRESH_ENABLED`,
`MARKET_STATEWIDE_MIN_OBSERVATIONS`, `MARKET_CURRENT_MAX_DAYS`,
`MARKET_SOURCE_MAX_ROWS`. Optional retained Groq variables: `GROQ_API_KEY`,
`GROQ_MODEL`, `GROQ_MARKET_ENABLED`, `GROQ_CONTEXT_TOKENS`,
`GROQ_MAX_COMPLETION_TOKENS`, `GROQ_REQUEST_TOKEN_BUDGET`, `GROQ_TIMEOUT_SECONDS`.
No secret belongs in Flutter or Git. Reviewed JSON feeds/pyPricing/Gemini are
not fallbacks for the statewide primary source.

## Rollback

Set `MARKET_DAILY_REFRESH_ENABLED=false`, `MARKET_STATEWIDE_ENABLED=false`,
`MARKET_SOURCE_VERIFIED=false`, `GROQ_MARKET_ENABLED=false`; suspend the one cron.
Reads retain validated historical cache and calculate staleness. Revert reviewed
application changes to the prior deployed image if needed, without dropping
collections/indexes or overwriting farmer prices and transaction history.
Production flag/image changes require separate deployment approval.

## Executed local acceptance checks — 2026-10-13

- Full backend: 423 passed, 0 failed, 0 skipped; isolated loopback Mongo replica
  set, 132 dependency/deprecation warnings. Final focused backend suite: 145
  passed; final mirrored source/Groq suite: 116 passed. All price fixtures are
  synthetic and no live generation was executed.
- Flutter: 89 passed. Final analysis exit 0: 17 pre-existing informational lints,
  no errors/warnings. Legacy zero-price UI acceptance was replaced by explicit
  unavailable assertions to match the current positive-price contract.
- Dependency compatibility: `pip check` passed; Python compileall passed.
  Local real FastAPI lifespan/index startup and `/health` passed (200 healthy,
  connected); empty cache 503 and unauthenticated refresh 401 verified.
- Index dry-run and disabled cron invocation passed without database/provider
  access. Mongo index/upsert/history/concurrent-run/failure tests passed locally;
  no production indexes were applied. The isolated Mongo processes were stopped.
- Release APK built in a fresh isolated copy; Android v2 signature verification
  passed. New artifact:
  `C:\VAYAL CONNECT\artifacts\vayalconnect-statewide-review-20261013-203123.apk`.
  Application ID `com.vayalconnect.app`, version `1.1.0`, versionCode `2`.
  SHA-256 `4990959B878A33500D0F83D5ED5859BCF55EB37440955FB34EE8E06D35FD3B1B`.
  No `.env`, keystore or signing-properties entry is packaged. Existing APKs
  were not overwritten. Device acceptance and release versionCode review still
  required before distribution; this review APK is not a deployment.
- Relevant backend copies match; `scripts/recover_admin.py` is an intentional
  unrelated standalone-only file and was left untouched. Git remains `main`
  at `58fcc93` with preserved uncommitted changes; no commit/push/deployment.
- Source is still blocked: no live Tamil Nadu crop or flower coverage established,
  source units/schema/dates/access limits unresolved. Primary source and schedule
  flags remain off. Render dashboard access was unavailable and no active cron
  claim is made. Production database/configuration were not modified.
