# Market repair — 14 October 2026

## Confirmed diagnosis

The public Render health endpoint reported commit `eaf0ade3a615ff7a4e8391836090d84ca1d9aa6f` and a connected database. Tomato returned 503 with an empty cache. The route incorrectly classified every empty result as a source failure, although GET never contacts the source.

A read-only inspection of the Atlas database configured in the local backend found zero market prices, zero daily runs, and zero watchlist entries. The Render database identity and environment have not been inspected, so local Atlas configuration is not proof of Render's settings. Local configuration defaults all three market gates to false. The working-tree Blueprint declarations also disable those gates. The deployed Git commit has no cron declaration; uncommitted Blueprint work adds one. A declaration is not an instantiated Render job.

Flutter retrieved references but never assigned one to the selling-price controller. Its default Grains category was sent as a strict reference filter even for Tomato; the service also filtered by farmer category. Edit forms did not automatically load references. Default API statewide scope discarded district/market constraints and excluded individual observations.

## Source verification and coverage

Official source: https://www.agrimark.tn.gov.in/

The crop selector confirms Tomato=8, Banana (fruit)=27, Jasmine=109, Marigold=107. The page labels the crop-wise report `Price Rs/Kg` and its JavaScript POSTs an empty body to `/home/us_dist_report_api/DD-MM-YYYY/CROP_ID`. The JSON is a market-name-keyed object with `min`, `max`, `modal`, and `qty`; the date/crop are bound to the request. No district is inferred from a market name. Raw min/max values, date, crop ID, source URL and kg units are preserved. The calculated suggestion is explicitly a median of distinct-market range midpoints, not a claimed government modal price.

The successful live-source/local-API smoke run accepted 112 Tomato, 71 Banana (fruit), 24 Jasmine and 28 Marigold observations on 2026-10-14. One Tomato row failed validation. Tomato's calculated reference was 3000 paise/kg. Counts can change as the department updates the day's report. No other crop mappings were added; unsupported or ambiguous crops remain unavailable. There are no AI requests or required source credentials.

Public source snapshots and the full smoke evidence are in `C:/VAYAL CONNECT/artifacts/`. These are source evidence, not production cache writes.

## Repaired behavior

- Empty searches return HTTP 200 with no records and an explanation; genuine Mongo failures return 503 / `MARKET_CACHE_UNAVAILABLE`.
- Market searches default to individual market observations. Use `scope=statewide` explicitly for calculated references. Crop, market and district filters are honored.
- Refresh starts with the four verified crop mappings, even with no listings/watchlist. Registered contexts remain supported. Invalid evidence cannot overwrite verified cache; upserts retain creation timestamps and handle duplicate-key races. Cache history is retained after source failure.
- Official read-only report requests retry transient failures once (two attempts maximum per crop); malformed data and permanent HTTP errors are not retried. The whole source pass is bounded at 240 seconds. A daily Mongo claim and shared lease prevent concurrent refresh jobs. A failed daily claim stays consumed after these bounded attempts; the next scheduled day is the next run. Partial coverage and source diagnostics are visible in admin status.
- Current verified references, converted to the listing unit, fill the Add form automatically. Farmers can edit them. Manual edits, including clearing the field, and existing Edit prices are preserved across asynchronous responses. Stale references remain visible but do not autofill. Unsupported/unavailable references leave an untouched price empty. Publication requires a real farmer-selected price; the decorative `10` hint is never serialized.
- Loading, empty, retry, stale and suggestion states have English/Tamil text. Listing/payment price calculations remain independent of market references.

## Production activation — approval and Render access required

Do not apply either Blueprint blindly: its declared web-service name differs from the public hostname and the existing service must be identified first. No Render dashboard session or API credential was available during this repair. Therefore the existence, schedule, environment and successful execution of a Render cron job are **not verified**.

1. Identify the existing service serving `https://vayal-connect.onrender.com` and its linked repo/branch. Do not create a replacement web service.
2. Inspect Render for an existing `vayalconnect-market-daily` job. If absent, obtain approval for the scheduled service and its hosting cost before creating it. Use the same backend image/revision and existing Atlas configuration.
3. After explicit approval, set `MARKET_STATEWIDE_ENABLED=true`, `MARKET_SOURCE_VERIFIED=true`, and `MARKET_DAILY_REFRESH_ENABLED=true` on the refresh job. These flags enable source requests and market-cache/run/watchlist writes. Set the web-service gates only if administrator-triggered refresh is wanted. No source key is needed. Do not change payment, authentication or encryption values.
4. Schedule `30 2 * * *` UTC, which is 08:00 IST year-round, with command `python -m scripts.refresh_market_prices`. Required existing backend environment: `APP_ENV=production`, `MONGODB_URI`, `MONGODB_DATABASE`, `JWT_SECRET`, `ENCRYPTION_KEY`. Reuse current private values; never paste them into source or logs. Keep `MARKET_STATEWIDE_MIN_OBSERVATIONS=3`; Groq/Gemini remain disabled.
5. Validate and deploy the reviewed commit through the existing Render web service. Explicitly approve the initial market refresh/cache writes. Do not run general database-seeding or credential-rotation scripts.
6. Verify `/health` reports the deployed commit, `/api/v1/market-prices?commodity=Tomato&limit=3` reports genuine dated observations, and authenticated `/api/v1/market-prices/status` shows successful refresh diagnostics. Check the Render cron's actual next-run time and next scheduled execution; an HTTP health check alone does not verify scheduling.

The user explicitly reserved approval for production flags and data changes. No production activation, refresh, credential change, payment change or production test was performed.

## Validation commands

Backend tests use only `mongodb://127.0.0.1:27019/?replicaSet=vayal_verification`, with `APP_ENV=testing`, `MONGODB_DATABASE=vayalconnect_test`, `VAYALCONNECT_RUN_MONGO_TESTS=1` and that same `VAYALCONNECT_TEST_MONGO_URI`. Integration tests create disposable, uniquely named local databases. Never run this suite against Atlas.

Run `python -m pytest tests -q`, `ruff check app scripts tests --select E9,F63,F7,F82`, `flutter test`, `flutter analyze`, and formatting checks. The repository has existing informational Dart lints and formatting differences outside this repair; report them separately from errors in changed files.

Build APKs in a new timestamped source copy outside the existing build directory. Use the existing private release signing configuration and explicit `--dart-define=BACKEND_BASE_URL=https://vayal-connect.onrender.com`. Keep the result marked pending production activation until live endpoints and device workflows are verified.
