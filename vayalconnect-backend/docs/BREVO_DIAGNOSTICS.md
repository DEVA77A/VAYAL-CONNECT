# Brevo OTP diagnostics

The deployed source is `vayalconnect-backend/` in DEVA77A/VAYAL-CONNECT.
The sibling Windows backend is a local copy; pushing it alone does not publish changes.

Required Render environment names (case-sensitive):
- `BREVO_API_KEY`: a current Brevo API v3 key, configured directly in Render.
- `BREVO_SENDER_EMAIL`: `vayalconnect@gmail.com`, verified in the same Brevo account.
- `BREVO_SENDER_NAME`: `Vayal Connect`.

Never paste keys into chat, logs, source, or release assets. Rotate previously exposed keys.
The local ignored .env does not configure Render. Environment changes require deploying/restarting the service.

The SDK sends POST https://api.brevo.com/v3/smtp/email with api-key authentication
and sender, to, subject, htmlContent JSON fields. Success requires messageId.
Provider failure still invalidates the OTP and returns the existing safe 503 response.
Expiry, cooldown, verification, login, and atomic consumption are unchanged.

Failure logs include exact HTTP status (when available), an allowlisted provider code,
and a static classification derived from the response. Raw response bodies, exception
strings, headers, recipient details, and OTPs are never logged. Unknown messages are
classified as provider_rejection rather than exposed.

Interpretation:
- invalid_api_key: replace the invalid/revoked key directly in Render, then redeploy.
- ip_not_authorized: inspect Brevo API IP authorization for the service outbound IPs.
- sender_not_validated: verify the configured sender in the key's Brevo account.
- credits_unavailable/account_unavailable: resolve the account restriction with Brevo.
- transport_or_client_error: no HTTP status was available; inspect connectivity safely.

Local read-only checks during this investigation returned HTTP 401, unauthorized,
invalid_api_key for /account and /senders. This does not prove Render has the same key.
No real email was sent and sender verification could not be inspected with that key.

After deployment, confirm /health and the deployed commit in Render. Run one authorized
OTP request, inspect the sanitized failure log if rejected, and confirm inbox receipt
separately if accepted. API acceptance is not proof of delivery.
