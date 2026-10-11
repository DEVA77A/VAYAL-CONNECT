# VayalConnect release and operations guide

This source update implements real database operations. A compiled APK is a **production-configured, unverified candidate** until the external/deployment/device gates below pass. No payment or government price is simulated in release mode. Existing releases are preserved.

## Pricing and lifecycle

- Currency: integer INR paise. Commission: basis points (1000 = 10%). Each unit commission is `ROUND_HALF_UP(farmer_base_paise * commission_bps / 10000)`. Buyer total = quantity × (base + unit commission) + delivery fee. Farmer earnings = quantity × base. The existing default is 20% until an administrator saves a rate; the screen shows this default explicitly.
- Delivery fee is currently zero: farmer-offered delivery is included. Farm approval controls whether delivery is offered. Government mandi data is advisory and never supplies an invented base price. Weight conversions are explicit; count and weight units cannot be compared.
- Order price, commission configuration/version, fulfillment/address, estimate inputs and reservation expiry are stored at checkout. Later rate/listing changes do not recalculate historical orders.
- Unpaid reservations expire after 30 minutes (configurable 5–120). A 60-second worker cancels at most 50 expired orders per pass. MongoDB transactions serialize capture/cancellation, prevent overselling, and release stock once. Legacy unpaid records lacking expiry receive a single grace period when the new backend creates its indexes; existing financial snapshots stay unchanged.
- Supported fulfillment: `PENDING_PAYMENT → PAID → CONFIRMED → PROCESSING → SHIPPED → COMPLETED` for delivery; pickup completes from PROCESSING. Only verified captured payment unlocks fulfillment. Buyers/farmers/admins can cancel eligible unpaid orders. Paid cancellation/refund automation is unavailable; the API refuses to claim a refund. A late capture leaves a cancelled order cancelled and records `refund_required` without creating a payout.
- Payout records track genuine expected farmer earnings. Approval requires a COMPLETED/CAPTURED order with matching amounts. Bank transfers are disabled for the TEST demonstration; no sandbox transfer reports a fake success.
- Admin financial/order filters use the order creation cohort and UTC day/month/year. Gross order value includes all recorded orders, including cancelled ones. Earned sales/commission require COMPLETED plus CAPTURED. Captured totals include amounts requiring refund review. Payout totals use payout creation dates; account/listing counts are current, all-time counts. The dashboard describes these definitions.
- Delivery is an estimate: Haversine straight-line distance, 30 km/h, 1.5 distance factor, 24-hour preparation, harvest readiness, and a 24-hour arrival window. These assumptions are configurable. It is never advertised as road distance or a guaranteed arrival. Pickup requires no delivery address. A saved postal address is independent of device location; destination coordinates must be obtained with consent while physically at that destination. No geocoder/routing provider is configured.

## Administrator access

An administrator already exists in the configured Atlas database. It was preserved, and no password was read, guessed or replaced. Its ID and login email were exported only to the private local file:

`C:\VAYAL CONNECT\vayalconnect-flutter\.local-verification\private\existing-administrator.txt`

Open it privately. The login uses the **email**, not the internal account ID. Recover the existing account with the app's Forgot password email OTP flow, then use Profile → Change password. Actual OTP delivery and live administrator login still require verification. Do not send credentials through chat or commit them.

For a genuinely empty database, run from the backend folder in your own terminal (not redirected/shared logs):

```powershell
.\venv\Scripts\python.exe -m scripts.seed_admin --email <your-admin-email> --phone <your-10-digit-phone> --generate-password
```

Without `--generate-password`, the command prompts twice with hidden input. Generated passwords are shown only in a private interactive terminal after a successful creation; save one in a password manager. The command refuses public/noninteractive bootstrap, ordinary-account promotion, duplicate initial admins and password overwrite. Concurrent bootstrap is serialized by a MongoDB transaction. No public admin registration exists.

## Mandatory secret rotation

The local JWT and bank-encryption values matched public test fixtures already in Git history. Current tests generate fresh isolated keys. Production startup rejects the exposed values; history was preserved rather than rewritten. Render's actual values could not be inspected. **Rotate any environment using those exposed values before claiming production security.** Changing only ENCRYPTION_KEY would make existing bank ciphertext unreadable.

1. Take an Atlas backup. Identify the exact database, service and all backend writers. Pause writers and coordinate a maintenance window through Render; this access is unavailable in the current session.
2. In a private backend terminal, with the existing environment pointing to the exact database, run a read-only check:

```powershell
.\venv\Scripts\python.exe -m scripts.rotate_security_keys --dry-run
```

3. With all writers paused and the backup complete, run:

```powershell
.\venv\Scripts\python.exe -m scripts.rotate_security_keys --new-key-file <absolute-private-path-to-next-security.env>
```

The command requires an explicit private-terminal confirmation. It creates an exclusive, permission-restricted recovery file containing fresh JWT and Fernet keys, then atomically re-encrypts the existing bank fields. It never logs values. Invalid ciphertext rolls back every database change. It refuses batches above 1000 profiles; coordinate a larger migration rather than bypassing that boundary. Keep the recovery file even if an error occurs.

4. Before resuming ANY writer, securely install both values in Render and the local backend `.env`. Never copy them into Flutter, source code, or command arguments. Restart/deploy, check bank readability and masked responses, verify authentication, and resume service. JWT rotation invalidates old sessions. Preserve the Atlas backup and private recovery keys in a password manager.

This migration was tested on isolated real MongoDB data; it was **not run against Atlas** because the deployed service cannot be paused/configured here.

## Backend deployment

Repository: `DEVA77A/VAYAL-CONNECT`, branch `main`; backend source: `vayalconnect-backend/`. The root Blueprint uses repository-relative Dockerfile/context paths without a rootDir, avoiding duplicate backend paths. See [Render monorepo documentation](https://render.com/docs/monorepo-support).

Use the existing Render service rather than creating another database or service. Confirm its linked repository/branch and commit; pushing alone is not deployment evidence. In Render → service → Manual Deploy, deploy the source commit reported in the final verification. Configure APP_ENV=production, APP_VERSION=1.1.0, the existing Atlas URI/database, fresh private JWT/encryption keys, Brevo email settings, and the government/payment settings below. Preserve the database and existing accounts. Do not upload `.env`; Docker excludes local environment files.

- MongoDB must be a replica set/Atlas with transactions. Startup creates compatible indexes and a bounded legacy reservation migration. Read-only preflight found zero duplicate payment order IDs, gateway payment IDs or payout order IDs in the configured Atlas DB; the Render DB identity is unverified. If another environment has duplicates, reconcile audited records before unique-index creation. Do not wipe or blindly delete records.
- Government settings: GOVERNMENT_MARKET_API_BASE_URL=`https://api.data.gov.in/resource/9ef84268-d588-465a-a308-a864a43d0070`; GOVERNMENT_MARKET_API_KEY is private. The current configured request fails before a genuine record is obtained. From Render, verify DNS/TCP/TLS and make the crop-specific request using that environment's key without logging the query URL/key. Only after connectivity works can HTTP/key/rate-limit validity be established. Exact matching is enforced for commodity and requested market/region. The farmer selects the nearest mandi by name; automatic geolocation-to-mandi selection is unavailable because the source provides no verified routing/location lookup here.
- Razorpay settings: a valid `rzp_test_` key ID, its matching RAZORPAY_KEY_SECRET and RAZORPAY_WEBHOOK_SECRET. The local pair returned HTTP 401 on a read-only order-list request. Replace it privately with a valid TEST pair in local/Render environments. Never enable live mode. Configure a signed Razorpay test webhook at `/api/v1/webhooks/razorpay` and verify gateway capture, amount, currency and order relationship. The public checkout key is returned to authenticated buyers; the secret stays on the backend.
- After deployment, `/health` must report `database=connected` and `commit` equal to the intended Git SHA. Verify role/onboarding/product/address/order/payment contracts with genuine authorized accounts. `/api/v1/market-prices?commodity=Wheat&limit=2` must contain genuinely retrieved matching records before calling market prices fixed. HTTP 503 is correct when the source fails; cached records retain their original retrieved/reported dates and stale labels.

Official provenance: [Government dataset](https://www.data.gov.in/resource/current-daily-price-various-commodities-various-markets-mandi). No alternate host, API-key bypass, invented price or unrelated commodity is used. Direct official alternate Agmarknet report probes returned 403 and were not bypassed.

## Tests

Backend documented command: `python -m pytest tests/ -q`. Full isolated Mongo integration verification additionally sets `VAYALCONNECT_RUN_MONGO_TESTS=1` and uses a local replica set on 127.0.0.1:27019 named `vayal_verification`; disposable DBs have checked prefixes. Existing opt-in auth tests use disposable localhost DBs. Test users/products/orders live only in those DBs. Government/Razorpay HTTP and Android native callbacks are mocked only in automated provider/UI tests; real external evidence is recorded separately.

Flutter: `flutter pub get`, `flutter analyze`, `flutter test`. Analyzer informational lints are reported separately; they are not silently suppressed. No Android device/emulator is connected, so actual Android location permission, photo picker, native checkout and complete role journeys remain NOT TESTED on a device.

## APK and signing

```powershell
C:\src\flutter\bin\flutter.bat build apk --release --dart-define=BACKEND_BASE_URL=https://vayal-connect.onrender.com
```

App ID `com.vayalconnect.app`, version `1.1.0` (build 2). Release signing requires the private ignored `android/key.properties`; no debug-key fallback is allowed. This workspace has a dedicated RSA release key under the private `.local-verification/signing/` directory. Back up that key and key.properties securely; losing them prevents signed updates. Never commit or upload them. Previous debug-signed installs cannot be updated with this new key; arrange data/account-safe installation on a separate test device rather than discarding user data.

The final APK is copied with an exclusive unique `UNVERIFIED` filename under `releases/`; existing releases are never overwritten/deleted. The verification record includes size, SHA-256, package/version, signature, backend URL and known-secret scan. Compilation/signature checks do not certify deployed functionality. Do not publish a verified GitHub release until the source, credentials, government retrieval, deployment and Android workflow gates pass.
