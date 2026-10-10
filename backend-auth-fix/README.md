# Backend authentication fix overlay

The linked repository previously tracked Flutter only. These are the exact focused backend files tested in the sibling local FastAPI project; this directory is not a second backend service.

Review local changes before copying the matching paths from this overlay into the existing vayalconnect-backend directory. Preserve all other backend files, the virtual environment, MongoDB data, and the local .env. Run `venv\Scripts\python.exe -m pytest -q` there, then restart `uvicorn app.main:app --host 0.0.0.0 --port 8000`.

Keep the existing Brevo configuration in the ignored local .env: BREVO_API_KEY must contain a real transactional API credential; BREVO_SENDER_EMAIL must be an account-controlled sender verified in Brevo; BREVO_SENDER_NAME is VayalConnect. No credential is included here. The configured local credential currently appears to be a placeholder and the sender differs from vayalconnect@gmail.com. Sender ownership and live delivery remain unverified. Rotate the previously exposed account password. An ordinary Gmail password is not a Brevo API credential.

OTP send failure now returns HTTP 503, invalidates the unsent code, and never logs the OTP or raw provider errors. Provider acceptance requires a message ID. Blocking SDK calls run off the async event loop. MongoDB returns timezone-aware timestamps for OTP checks. No endpoint or account lifecycle changes were made.

The pending account remains unverified after failed delivery; request a new OTP after correcting configuration and waiting the existing 60-second cooldown. The Flutter registration sheet retains account creation state while open so retrying delivery does not create a duplicate account.

Automated email tests mock the provider and never send real mail. Real sender verification, provider acceptance, inbox receipt, and physical-device flow must still be tested.
