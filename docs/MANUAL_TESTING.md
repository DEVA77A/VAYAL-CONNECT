# VayalConnect manual authentication testing

## A. Prerequisites

Review and apply the backend-auth-fix overlay to the existing backend only if it is not already applied. This Git repository tracks Flutter and the backend overlay, not the complete backend. Back up any independently edited matching files before applying it. Preserve the local .env and all MongoDB data.

Configure these exact names directly in C:\VAYAL CONNECT\vayalconnect-backend\.env (never in chat or Flutter):

```dotenv
BREVO_API_KEY=<new rotated transactional API key>
BREVO_SENDER_EMAIL=vayalconnect@gmail.com
BREVO_SENDER_NAME=Vayal Connect
```

Keep the existing MONGODB_URI, MONGODB_DATABASE, JWT_SECRET and other settings. The local database is vayalconnect_test. Revoke the key exposed in chat. Rotate the Admin password that was previously embedded in historical quick-fill source/APKs; removing quick-fill controls does not revoke that credential. Rotate any other real accounts that reused the removed quick-fill passwords. Git history and previous APKs were not rewritten or deleted. Confirm the sender is verified and transactional sending is enabled in Brevo. Gmail's domain cannot be authenticated with DNS records you control; DKIM/DMARC warnings may remain, and Brevo may substitute a compliant sender address. Provider acceptance does not guarantee inbox receipt.

Use only test recipients you control. Use separate email addresses and phone numbers for Farmer and Buyer accounts. Connect the phone and laptop to the same trusted Wi-Fi. Do not forward the backend port to the internet. MongoDB and FastAPI must stay running.

## B. Start backend (Windows PowerShell)

```powershell
Get-Service MongoDB
# If stopped, start it from an administrator PowerShell:
Start-Service MongoDB
Set-Location 'C:\VAYAL CONNECT\vayalconnect-backend'
# Calling the venv executable directly avoids activation-policy changes:
.\venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

If port 8000 is already occupied by the working backend, use its existing process; restart it after changing .env or code. Do not start a second server. Open http://10.20.18.111:8000/api/docs from the phone browser before testing.

## C. Install APK

Open https://github.com/DEVA77A/VAYAL-CONNECT/releases with an account authorized for this repository. Select the new test release only once publication is confirmed and download vayalconnect-android-test.apk. Verify its SHA-256 against that release's notes. Allow installation from your trusted download source when Android requests it. Debug builds may conflict with an app signed with a different key; preserve local app data before considering an uninstall.

This build targets http://10.20.18.111:8000. DHCP can change the laptop IP. The app's Server IP / URL dialog can update the current session. Rebuild with the new BACKEND_BASE_URL for a different compile-time default:

```powershell
Set-Location 'C:\VAYAL CONNECT\vayalconnect-flutter'
C:\src\flutter\bin\flutter.bat build apk --debug --dart-define=BACKEND_BASE_URL=http://<CURRENT_LAN_IP>:8000
```

## D. Farmer

1. Open Registration; enter valid test details and select Farmer. Password needs at least 8 characters, an uppercase letter and a digit; age must be 18-120.
2. Submit once. OTP verification should open only after the provider accepts the request. A delivery failure must show an error and keep the account unverified; correct configuration and retry after the cooldown.
3. Check the test inbox and spam folder. Enter the actual received six-digit OTP within 10 minutes. Do not share or record the OTP in reports.
4. Verify, then confirm the Farmer dashboard opens. Newly registered Farmers remain subject to the existing approval rules.
5. Log out and log back in with the same details; confirm the Farmer identity and dashboard.

## E. Buyer

Repeat the same steps with a different controlled email and phone number, choosing Buyer. Confirm the Buyer dashboard and login. A role button cannot grant Admin access.

## F. Negative tests

- Wrong OTP: verification fails, no dashboard opens. Maximum 5 attempts; a fresh OTP is needed after exhaustion.
- Expired OTP: wait over 10 minutes; verification fails. TTL cleanup may return invalid rather than expired after removal.
- Reuse: a previously verified OTP must fail.
- Resend: requests within 60 seconds fail with a cooldown. After 60 seconds resend; only the newest accepted code should work.
- Invalid password and unknown email: login fails without a session.
- Provider unavailable: run the mocked backend tests below. Do not alter shared credentials or disable account security just to induce failure.
- Backend unavailable: stop the test backend, try login, confirm a network error, then restart it.

```powershell
Set-Location 'C:\VAYAL CONNECT\vayalconnect-backend'
.\venv\Scripts\python.exe -m pytest -q
```

## G. Troubleshooting

Backend unreachable: first check /api/docs on the laptop and phone, Wi-Fi connectivity, the bind address, and a narrowly scoped Private-network firewall rule if needed. Never disable Windows Firewall.

Incorrect IP: run Get-NetIPAddress -InterfaceAlias Wi-Fi -AddressFamily IPv4; update the app server URL or rebuild. Android localhost refers to the phone; emulators use http://10.0.2.2:8000.

Brevo 401/403: replace the local API credential with a rotated transactional API key and restart the backend. Do not copy provider diagnostics or keys into reports.

Sender error: confirm the exact sender in the Brevo dashboard and check sending activation, quota, blocked recipients, and transactional logs. Record acceptance separately from inbox receipt.

MongoDB unavailable: check Get-Service MongoDB and the existing MONGODB_URI/database. Preserve collections and real users.

## Verification limits

Automated tests mock external email. No live Brevo send or inbox receipt is claimed until separately verified. Ordinary backend tests run 77 unit tests and skip 2 local integration tests. To include the isolated local MongoDB API checks, set $env:VAYALCONNECT_RUN_MONGO_TESTS='1' before pytest and remove it afterward; the full run passes 79 tests. Physical-device launch and inbox results must be recorded during these manual steps. Repository visibility and existing releases must be confirmed through authenticated GitHub access before publishing a new release.

Brevo references: https://developers.brevo.com/docs/send-a-transactional-email, https://help.brevo.com/hc/en-us/articles/17286219877778-FAQs-About-domain-authentication-Brevo-code-DKIM-DMARC, and https://help.brevo.com/hc/en-us/articles/14925263522578-Comply-with-Gmail-Yahoo-and-Microsoft-s-requirements-for-email-senders.
