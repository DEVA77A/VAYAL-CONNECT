# Registration error handling test build

Production API: https://vayal-connect.onrender.com

Confirmed defects fixed:
- FastAPI 422 uses detail/loc; the app previously ignored it and showed Registration failed.
- Phone validation previously checked length only, allowing spaces, letters, and separators rejected by the backend.
- Error text previously depended on server message content. Registration and OTP request errors now use static allowlisted messages.

The documented Indian mobile formats are 10 digits or +91 followed by 10 digits, without internal spaces/hyphens. Validation matches the existing backend's optional plus and 10-15 digits with a nonzero first digit; other backend-supported international numbers remain accepted. Existing boundary trimming is preserved; numbers are never reformatted or given an inferred country code.

Required fields remain name, email, phone, password, address, area_location, gender, age, preferred_language. OTP purpose remains REGISTRATION. Backend uniqueness, OTP expiry, cooldown, invalidation, atomic consumption, verification, and login are unchanged. Existing accounts are never deleted or overwritten.

Verification: 18 focused Flutter tests passed; focused analysis found no issues. Existing 10 backend registration/contract tests passed earlier and backend source is unchanged in this update. Production OpenAPI matched the fields; safe invalid-body probes returned expected 422 field locations. These are not proof of live registration or email delivery.

Manual test:
1. Install the release APK. Open IP and confirm https://vayal-connect.onrender.com (no LAN backend or shared Wi-Fi required).
2. Enter an invalid phone with spaces or letters; expect the phone hint before submission. Use your own real mobile in a documented format.
3. Register with an email you control and a unique phone, valid age 18-120, and a password with 8-128 characters, uppercase and a digit.
4. Check inbox/spam only after provider acceptance. Verify the received OTP, log in, and confirm the selected Farmer/Buyer dashboard. Repeat with another authorized account for the other role.
5. Existing email/phone must show a sign-in/recovery message; the existing account must remain intact. Complete pending verification using the existing account's verification option rather than deleting/recreating it.
6. Provider failure must show that the OTP could not be sent and leave the account unverified. Invalid OTP, expiry, and resend cooldown must still reject safely.

Live authorized registration, OTP receipt, verification, login, and physical device installation remain NOT TESTED for this build. Brevo credentials must be configured securely in Render. No credentials are included in the APK.
