# Backend authentication fix overlay

The linked repository previously tracked Flutter only. These are the exact focused backend files tested in the sibling local FastAPI project; this directory is not a second backend service.

Review local changes before copying the matching paths from this overlay into the existing vayalconnect-backend directory. Preserve all other backend files, the virtual environment, MongoDB data, and the local .env. Run `venv\Scripts\python.exe -m pytest -q` there, then restart `uvicorn app.main:app --host 0.0.0.0 --port 8000`.

Keep the existing Brevo configuration in the ignored local .env: BREVO_API_KEY must contain a real transactional API credential; BREVO_SENDER_EMAIL must be an account-controlled sender verified in Brevo; BREVO_SENDER_NAME is Vayal Connect. No credential is included here. The sender is configured as Vayal Connect <vayalconnect@gmail.com>, reported verified by the product owner. Provider-side verification and live inbox delivery remain unverified. Rotate any API key exposed in chat and configure its replacement directly in the ignored local .env. Rotate the previously exposed account password. An ordinary Gmail password is not a Brevo API credential.

OTP send failure now returns HTTP 503, invalidates the unsent code, and never logs the OTP or raw provider errors. Provider acceptance requires a message ID. Blocking SDK calls run off the async event loop. MongoDB returns timezone-aware timestamps for OTP checks. No endpoint or account lifecycle changes were made.

The pending account remains unverified after failed delivery; request a new OTP after correcting configuration and waiting the existing 60-second cooldown. The Flutter registration sheet retains account creation state while open so retrying delivery does not create a duplicate account.

Automated email tests mock the provider and never send real mail. Real sender verification, provider acceptance, inbox receipt, and physical-device flow must still be tested.

This follow-up uses the official https://api.brevo.com/v3 endpoint and api-key authentication header. Atomic verification attempt claims and conditional OTP consumption prevent exceeding attempt limits and reusing an OTP through concurrent verification requests. No database schema or endpoint changes are required.

For gmail.com senders, Brevo documents that free-provider domains cannot be authenticated with your own DKIM/DMARC DNS records. Brevo may substitute a compliant sender address. A verified mailbox is not an authenticated domain, and inbox delivery is not guaranteed. See https://help.brevo.com/hc/en-us/articles/17286219877778-FAQs-About-domain-authentication-Brevo-code-DKIM-DMARC and https://help.brevo.com/hc/en-us/articles/14925263522578-Comply-with-Gmail-Yahoo-and-Microsoft-s-requirements-for-email-senders. No custom domain or DNS configuration was created.
