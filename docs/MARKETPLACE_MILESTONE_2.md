# Marketplace milestone 2: applications, chosen selling prices, fulfillment

Based on commit 03464035325250471de75d473177ff003633720d. The versioned backend is the Flutter repository's vayalconnect-backend directory. The sibling backend is source only, not a separate Git repository.

## Implemented behavior

- Farmer Home and Profile open a real application form. Required farm name, farm address, buyer pickup address, crops, and delivery availability are persisted in MongoDB. Email verification is required for submission. Rejected applications expose the administrator's reason and can be corrected/resubmitted. Approved applications are read-only in this milestone.
- Administrators review submitted farm details, active/email-verified identity, and application revision. Approval requires a complete submitted application. Conditional MongoDB updates reject stale reviews and duplicate decisions. Rejection can revoke an existing approval. Existing approved farmers remain approved; pending legacy profiles must submit an application before approval.
- Profile supports adding/replacing payout bank details through the existing encryption API. Responses remain masked and saving resets verification. Bank setup is separate from trading approval; no automatic bank/KYC verification is claimed.
- New listings require a farmer-selected positive integer paise payout price per listing unit, up to ₹1,000,000 per unit. Flutter parses decimal rupees exactly. Commission is added by the server as a percentage of that chosen payout, rounded once per unit. For example, a synthetic 4,321-paise payout at 15% commission becomes 648-paise commission and a 4,969-paise buyer unit price. This is arithmetic, not a market-price claim.
- Reference lookup and publication require a directly reported official modal price, exact commodity/market match, valid non-future date, and a supported unit conversion. Source, raw units, comparison units, date, cached status, and age status are disclosed. Historical means older than one UTC day. References never replace the chosen payout. KG, quintal, and ton are converted with 1/100/1000 kg factors. Weight references cannot be compared to piece/dozen listings; an appropriately matching count-unit source is required.
- The old provider's invented modal-price fallback was removed. Legacy cached records without the direct-modal provenance marker are excluded and require an official refresh. If no verified live/cache record exists, listing publication returns MARKET_PRICE_UNAVAILABLE. Unknown units are not guessed in the new pricing path.
- Buyer listings preview the current commission for farmer-selected products. New orders freeze the chosen payout, commission/configuration version, totals, and fulfillment details. Checkout rejects a changed preview price with PRICE_CHANGED. Existing product/order financial snapshots are preserved and no legacy products are silently repriced.
- Buyers explicitly select pickup or, when offered by the farmer, delivery. Delivery requires recipient, mobile number, full address, and postal code. Pickup location comes from the approved farmer application (legacy listings fall back to their location). Delivery is included in the farmer's selected selling price; a separate delivery fee is zero. No distance, ETA, or carrier booking is fabricated.
- Fulfillment details appear in role-scoped order history and remain private to the owning buyer/farmer and administrators. Invalid fulfillment is rejected before inventory reservation. Sequential retries from the same checkout service retain a cryptographically random key and cannot change the persisted order's fulfillment details.
- Checkout displays PENDING_PAYMENT and the actual payment status. It no longer claims paid escrow, fake certifications, sample farmer identities, fabricated ratings, or guaranteed savings. The existing server verifies provider capture, amount, currency, association, and signature before confirming payment.
- A failure after a successful order insert no longer restores inventory for that persisted order. Farmers cannot cancel another participant's order through the generic cancellation route.

## Verification on 2026-10-11

- All backend regressions: 148 passed, including opt-in isolated localhost MongoDB tests; uniquely named disposable databases only.
- Flutter regressions: 49 passed, including application corrections/submission, delivery validation, pending payment messaging, exact money parsing, protected service contracts, and retry-key retention.
- Flutter analyze --no-fatal-infos: passed, with informational style hints and no warnings/errors.
- Real MongoDB/ASGI test exercises application rejection/resubmission/approval/revocation, encrypted bank storage and masked responses, listing creation, unit-aware reference snapshots, both fulfillment choices, price-change rejection, ownership, sequential retries, commission changes, and historical order preservation. Government/payment responses in automated tests are synthetic fixtures. They do not certify real provider success.
- A read-only official government API probe using the existing local backend configuration returned ConnectError/unreachable, including an independent request to the public official host without credentials. No live prices were returned. TLS validation remains enabled.

## External blockers and remaining scope

Live government connectivity remains blocked in this environment. Valid current prices for a specific farmer commodity/market are not certified. Real Brevo inbox delivery, Razorpay test payment capture, bank settlement, and deployed production behavior were not tested. The app does not yet launch a Razorpay gateway checkout; orders remain pending and the UI states this. Presence of configured credentials proves none of these services work.

Concurrent checkout/payment idempotency, inventory reservation expiry, coordinated multi-document audit/identity writes, saved address management, refunds, full translation coverage, secure persistent mobile sessions, delivery logistics, and editing approved farm details remain subsequent work. Retry keys currently live in a checkout service instance and do not survive application restart. A gateway-creation failure can leave a pending reserved order; check order history and retry the unchanged checkout rather than assume payment or reservation release.

No production deployment or APK rebuild is part of this change. A phone build and the updated backend must be deployed together before device verification: new listings require selling_price_per_unit_paise and checkout requires fulfillment_method.

## Operational commands

Run tests from the versioned backend with VAYALCONNECT_RUN_MONGO_TESTS=1 and the existing sibling backend venv Python executable. Run Flutter tests from the repository root.

The read-only scripts/check_market_reference.py accepts --env-file, --commodity, and --state. It only prints public provider status and reference metadata; it never logs secrets or modifies a database.

The scripts/sync_local_backend.py utility accepts --target and --base. It dry-runs by default and verifies destination files match the requested Git baseline before overwriting. --apply copies only changed source/tests/scripts/docs and aborts before writing if it detects a destination conflict. It never copies .env, venv, logs, releases, or the sibling milestone-onboarding folder.
