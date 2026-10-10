# VayalConnect v0.3.1-test — Brevo OTP authentication

Android debug build for local manual testing. This version is provisional: remote tags were checked, but authenticated release history must be inspected before publication. No release is claimed as published yet.

Frontend: registration, OTP verification, authenticated role selection and login retain the existing API contracts and approved layout. Unsafe account-password quick-fill controls were removed. Rotate the previously embedded Admin password and any real accounts using those old passwords; Git history and earlier APKs were not rewritten or deleted.

Backend: the complete FastAPI backend is outside this Git repository. The focused overlay is in `backend-auth-fix/`; the clean local `vayalconnect-backend-auth-fix.zip` contains the matching reviewed files. Preserve independently edited files, the local `.env`, and all MongoDB data when applying it. This follow-up uses `https://api.brevo.com/v3` with the `api-key` header, configures `Vayal Connect <vayalconnect@gmail.com>`, and makes attempt claims and OTP consumption atomic. No endpoint, account-lifecycle, role-authorization or database-schema changes were made.

Configuration: put a rotated transactional credential in `BREVO_API_KEY` directly in the ignored backend `.env`. Set `BREVO_SENDER_EMAIL=vayalconnect@gmail.com` and `BREVO_SENDER_NAME=Vayal Connect`. No credential is included. The key exposed in chat must be revoked. Sender verification is reported by the owner; provider-side status, a live send and inbox receipt remain NOT TESTED. Gmail's domain cannot be authenticated using DNS records controlled by the mailbox owner. Brevo may substitute a compliant sender; inbox delivery is not guaranteed.

Validation: 79 backend tests passed, including isolated local MongoDB Farmer/Buyer API flows with mocked email. 24 Flutter tests passed; dependency installation passed. Strict `flutter analyze` exited 1 with 43 informational lints and no warnings/errors; no checks were disabled. APK ZIP integrity, compiled LAN URL and Brevo key-format scanning passed. An initial APK scan found an embedded Admin password; its quick-fill source was removed before this rebuild. Real data was preserved.

API URL: `http://192.168.137.195:8000`. Keep MongoDB and FastAPI running on the laptop, with phone and laptop on the same trusted Wi-Fi. Open `/api/docs` from the phone before testing. If DHCP changes the address, rebuild using the new `BACKEND_BASE_URL`, or update the app's runtime URL for the current session. No public hosting or port forwarding was configured.

Start the backend in PowerShell:

```powershell
Set-Location 'C:\VAYAL CONNECT\vayalconnect-backend'
.\venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Download and install `vayalconnect-android-test.apk` only from a confirmed release or the local build location. Follow [MANUAL_TESTING.md](MANUAL_TESTING.md) for Farmer, Buyer and negative tests. Physical-device installation, live inbox receipt and complete marketplace device testing remain NOT TESTED. Existing sessions remain in memory.

APK size: **166,356,716 bytes**.

APK SHA-256:

```text
bb5a7ce7a6ab6c9f93ff6583fcbce2d4a9c912564f40a22ac3a3e71d5ed6abd0
```

References: [Brevo transactional API](https://developers.brevo.com/docs/send-a-transactional-email), [domain authentication limitations](https://help.brevo.com/hc/en-us/articles/17286219877778-FAQs-About-domain-authentication-Brevo-code-DKIM-DMARC).
