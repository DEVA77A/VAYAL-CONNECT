# Marketplace milestone 1: access, trust, and real data

This is a locally verified foundation milestone, not a completed marketplace or a production deployment.

## Implemented

- Administrator provisioning prompts for a hidden password; refuses to promote an existing Farmer/Buyer and records an audit event. No public administrator-registration route was added.
- Product creation/editing requires an active, email-verified, approved farmer. Buyer lists/detail hide unapproved or inactive farmers, inactive listings, and zero stock. Pagination/counts run after eligibility filtering.
- Administrator dashboard uses real API data, supports UTC day/week/month filters (the API also supports year), and uses the correct PUT approval/rejection routes. Sample farmers/orders and invented bank verification were removed.
- Financial totals include only COMPLETED orders with CAPTURED payment status. Commission and farmer payout use stored order snapshots. They are order-accounting totals, not proof of bank settlement. Date filters use order creation time; user counts/payout status counts remain all-time. Partial-refund reconciliation and settlement reporting remain future work.
- Payment verification checks the stored order association, signature, and provider-confirmed captured payment ID/order ID/amount/currency. Sequential checkout retries reuse the gateway order. Live Razorpay keys are disabled for this test-mode milestone.
- The existing Razorpay 1.4.2 SDK requires `pkg_resources`; requirements now include setuptools 81.0.0 so its import works in fresh virtual environments. This compatibility dependency does not establish that gateway credentials or a real payment work.
- Refresh tokens are matched by a SHA-256 digest and consumed atomically. Logout invalidates access tokens using a persisted session version and revokes refresh records. Legacy bcrypt refresh records require signing in again after deployment; accounts/passwords are preserved.
- Registration optionally requests foreground location with explicit consent, handles denied/disabled/unavailable states, and keeps manual address entry available. Coordinates must be paired, finite, and within geographic bounds. GPS coordinates do not establish a deliverable address.
- Language changes persist through the authenticated backend API. Full translation coverage remains incomplete.
- The supplied VayalConnect logo is bundled for the splash, authentication header, and app bar.

## Repository and local backend

The versioned backend is `vayalconnect-flutter\vayalconnect-backend`. Render must deploy this directory from the repository; pushing changes does not prove deployment. The sibling `C:\VAYAL CONNECT\vayalconnect-backend` may differ and is not an independent Git repository. Do not overwrite differences or copy `.env` into Git.

Configure an ignored backend `.env` securely on the machine that runs the server. Required: `MONGODB_URI`, `MONGODB_DATABASE`, `JWT_SECRET`; bank operations require `ENCRYPTION_KEY`. Email uses existing `BREVO_API_KEY`, `BREVO_SENDER_EMAIL`, `BREVO_SENDER_NAME`. Payments use `RAZORPAY_KEY_ID` (test key only), `RAZORPAY_KEY_SECRET`, and `RAZORPAY_WEBHOOK_SECRET` for configured webhook verification. Never place these values in Flutter or release assets. Rotate credentials previously exposed in chat.

Run the versioned backend in PowerShell:

```powershell
Set-Location 'C:\VAYAL CONNECT\vayalconnect-flutter\vayalconnect-backend'
& 'C:\VAYAL CONNECT\vayalconnect-backend\venv\Scripts\python.exe' -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Use `0.0.0.0` only for a trusted LAN phone test, with Windows Firewall limited to the private network and no public port forwarding. An Android emulator uses `http://10.0.2.2:8000`; a physical phone uses the laptop's current LAN IP. Compile `BACKEND_BASE_URL` accordingly. Keep MongoDB and FastAPI running.

Provision an administrator once, after configuring the target database:

```powershell
Set-Location 'C:\VAYAL CONNECT\vayalconnect-flutter\vayalconnect-backend'
$adminEmail = Read-Host 'Administrator email'
$adminPhone = Read-Host 'Administrator phone'
& 'C:\VAYAL CONNECT\vayalconnect-backend\venv\Scripts\python.exe' -m scripts.seed_admin --email $adminEmail --phone $adminPhone
```

Choose a unique password of 16–72 UTF-8 bytes with uppercase and a digit in the hidden prompt; store it in your password manager. No password is printed or automatically sent. Existing administrator credentials are not replaced. Provisioning retains existing commission/pricing configuration and only bootstraps defaults when absent.

## Local verification

```powershell
Set-Location 'C:\VAYAL CONNECT\vayalconnect-flutter\vayalconnect-backend'
$env:VAYALCONNECT_RUN_MONGO_TESTS = '1'
& 'C:\VAYAL CONNECT\vayalconnect-backend\venv\Scripts\python.exe' -m pytest -q
Set-Location 'C:\VAYAL CONNECT\vayalconnect-flutter'
& 'C:\src\flutter\bin\flutter.bat' analyze --no-fatal-infos
& 'C:\src\flutter\bin\flutter.bat' test
```

MongoDB integration tests use only uniquely named disposable databases on localhost and remove only those databases. External email/payment calls are mocked. A successful mocked capture does not demonstrate a real payment.

## Manual checks and blocked production checks

1. Run the updated backend against a deliberate test database. Provision an administrator using the command above.
2. Sign in as Admin, then as Buyer. Confirm only Admin can open administrative APIs. Log out and confirm old access/refresh tokens are rejected.
3. Register a Farmer/Buyer with your own test details. Test location denied, permanently denied, services disabled, and an explicit successful request; manual address entry should remain usable.
4. Submit the existing farmer profile and review it as Admin. Confirm publishing is rejected before approval, allowed after approval, and rejected again after suspension/rejection. Check buyer visibility and stock exhaustion.
5. Change language, sign in again, and check that the preference is restored. Confirm bank information is masked and no fabricated bank status appears.
6. With securely configured, valid Brevo credentials and an authorized inbox, perform one actual OTP request/verification/login. Provider acceptance and inbox arrival must be verified separately. Neither is certified by this milestone.
7. With Razorpay test credentials, use an actual gateway checkout before claiming payment integration works on a phone. Tampered amounts, wrong order associations, and authorized-but-not-captured payments must not confirm an order.

Production environment inspection/deployment, real Brevo delivery, real Razorpay checkout, Android hardware permission behavior, and accessible production inbox confirmation are BLOCKED or NOT TESTED until access is available. Public health alone proves none of these workflows.

## Next incomplete milestone

Implement complete farmer application/completeness screens and administrative review; farmer-chosen base pricing plus commission snapshots for new orders; saved delivery addresses; **both pickup and delivery selected at checkout**; disclosed distance/ETA assumptions; concurrent order/payment idempotency and reservation expiry; complete checkout/refund/state transitions; full English/Tamil coverage and secure session persistence. Preserve old order snapshots. Market reference prices must show source/date/units and freshness and must never replace a farmer's chosen price silently.
