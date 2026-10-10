# VayalConnect v0.3.0-test

Build: Android debug APK, local testing only.

Fixed registration OTP requests, truthful provider failure handling, OTP confirmation, authenticated role selection, role onboarding recovery, resend cooldown, duplicate submissions, malformed responses, and stale default backend address. Approved login layout and localization remain intact.

Backend: apply the reviewed backend-auth-fix overlay to the existing sibling FastAPI project. Keep MongoDB and `uvicorn app.main:app --host 0.0.0.0 --port 8000` running. MongoDB connectivity to vayalconnect_test is verified. The current Wi-Fi URL is http://192.168.137.195:8000; API docs are at /api/docs. Phone and laptop must share trusted Wi-Fi. Update the app server URL if DHCP changes the address. This is not a hosted production backend.

Email: existing Brevo integration requires a valid BREVO_API_KEY and an account-controlled BREVO_SENDER_EMAIL verified by Brevo, configured only in the ignored local .env. Current local credential appears to be a placeholder; the sender differs from vayalconnect@gmail.com. Sender ownership, live provider acceptance, and inbox delivery are BLOCKED/unverified. No real test email was sent. A Gmail password is not a Brevo API key. Rotate the previously exposed password. Provider acceptance does not guarantee inbox delivery; check spam.

Validation: 58 backend unit tests and 24 Flutter tests pass. Flutter dependency installation passes. Strict flutter analyze reports 43 informational lints; --no-fatal-infos exits successfully with no warnings/errors. APK ZIP integrity and the compiled LAN URL were checked. Physical phone launch, installation, and live email authentication flow are NOT TESTED: no ADB device is connected. Farmer/Buyer MongoDB API lifecycle checks use synthetic users and mocked email; Admin login/authorization is unit-tested, not tested with a real Admin account. Existing data was preserved. Sessions use the existing in-memory store.

Install: download vayalconnect-android-test.apk, enable installation from the trusted download source, and install. Debug signing is used; if Android reports a signing conflict with an existing app, preserve/export any needed local app data before deciding whether to uninstall it. Connect the phone to the laptop Wi-Fi and open http://192.168.137.195:8000/api/docs before testing. Configure email before registering real accounts.

APK size: 166358595 bytes.
SHA-256: `e8b75b5aeb2eda1bb7c79fe074a0f1b47833ea2ea366d086bd6bee69a771f97a`
