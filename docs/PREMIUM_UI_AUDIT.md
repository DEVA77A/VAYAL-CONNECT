# Premium UI page inventory — 15 October 2026

Session baseline: `C:/VAYAL CONNECT/artifacts/premium-ui-20261015-120442`.
All existing uncommitted files are retained. This pass builds on the prior UI work.
Architecture: MaterialApp + imperative Navigator, stateful screens, SessionManager,
LanguageRebuild, S/VayalStrings, existing HTTP services. No migration required.

Inventory recorded before implementation. I = inspected; R = presentation reviewed
and improved in this pass through direct layout changes and/or shared components. Shared design changes apply to every
reachable screen. Screens already styled in the baseline receive incremental polish.

| Existing page / surface | Source | Inspected | Redesigned this pass |
|---|---|---|---|
| Splash / role destination | splash_screen.dart | I | R |
| Login | auth_gateway_screen.dart | I | R |
| Registration / role choice | auth_gateway_screen.dart | I | R |
| OTP / resend / recovery | auth_gateway_screen.dart | I | R |
| Development server / demo sheets | auth_gateway_screen.dart | I | R |
| Location permission gate | location_gate_screen.dart | I | R |
| Buyer home / marketplace / search / categories / sorting / pagination | buyer_home_screen.dart | I | R |
| Product details + quantity + checkout + delivery selection | product_details_screen.dart | I | R |
| Address list / selection | addresses_screen.dart | I | R |
| Address editor | addresses_screen.dart | I | R |
| Payment / server verification presentation | payment_screen.dart | I | R |
| Order history / filters (all roles) | orders_screen.dart | I | R |
| Order details / existing lifecycle actions (all roles) | orders_screen.dart | I | R |
| Farmer dashboard | farmer_home_screen.dart | I | R |
| My crops / edit entry | farmer_home_screen.dart | I | R |
| Sales / earnings | farmer_home_screen.dart | I | R |
| Farmer payouts | farmer_home_screen.dart | I | R |
| Add / edit crop / stock / photo / price reference | add_product_screen.dart | I | R |
| Farmer application | farmer_application_screen.dart | I | R |
| Farmer bank form | farmer_bank_screen.dart | I | R |
| Market prices / search / reference records | market_prices_screen.dart | I | R |
| Admin dashboard / period filters | admin_dashboard_screen.dart | I | R |
| Farmer management / filter | admin_dashboard_screen.dart | I | R |
| Farmer application review | admin_dashboard_screen.dart | I | R |
| Buyer management | admin_dashboard_screen.dart | I | R |
| User products / orders activity | admin_dashboard_screen.dart | I | R |
| Commission configuration | admin_dashboard_screen.dart | I | R |
| Admin payout list / review | admin_dashboard_screen.dart | I | R |
| Profile / edit / password / logout / bank status | profile_screen.dart | I | R |
| Shared app bars / language toggle / dialogs / loading / errors | widgets + app_theme.dart | I | R |

There is no separate cart, product-detail route before checkout, standalone settings,
language selection page, or standalone admin product management page in this app.
Do not invent those pages. Product details and checkout are one existing route.
Unused legacy widgets (produce_card, bottom_nav_bar, market_price_card, mandi_ticker,
stats_kpi_card, state_views, demo_banner) are not reachable pages in current screens.

## Image contract inspection

AddProductScreen._photo uses image_picker (1600px / JPEG quality 82) and the existing
POST /api/v1/media multipart upload with session authorization. The returned relative
image_url is included in existing publish/edit payloads. Backend validates ownership,
stores compressed JPEG bytes in MongoDB, and returns image_url in buyer product lists
and details. BuyerProduct parses image_url; marketplace and checkout use CropImage.
GET /api/v1/media/{id} needs session authorization. Keep that contract intact.

Order schemas/router do not currently return an image URL or status-history events.
Use image_url only when present in an existing record; use branded fallback otherwise.
Do not fetch current product imagery for historical orders or fabricate a timeline.

## Scope

Frontend presentation and localized strings/tests/docs only. Preserve API calls,
roles, financial arithmetic, validation, state transitions, Razorpay callbacks,
verification and production data. No new dependencies, backend edits or deployment.


## Completed presentation work

- All 27 existing Screen classes retained across the 15 screen source files.
  The inventory above includes their existing modal/subflow surfaces separately.
- Shared green/black/white/brown Material theme, rounded white surfaces, warm
  canvas, quieter typography/detail strips, consistent sections and status badges.
- Safe page bodies constrain wide layouts to comfortable reading widths, while
  preserving each original scroll view and callback. Forms stay scrollable with
  keyboards; marketplace uses lazy sliver rows with 1/2/3 responsive columns.
- Marketplace category/sort controls share a row where space and text size permit.
  All search/category/sort/pagination queries remain unchanged.
- Actual product image URLs now share one presentation adapter across marketplace,
  checkout, crop editor, farmer crops, admin activity and legacy ProduceCard.
  CropImage validates URL shape, resolves root-relative URLs, authenticates media
  on the configured backend origin for both relative and absolute URLs, and never
  sends bearer tokens to external image hosts. No hardcoded crop/photo mapping.
- Fixed aspect ratios and BoxFit.cover prevent stretching; the farmer editor uses
  BoxFit.contain to show the full uploaded photograph. Bounded 128–1600px decode
  buckets use Flutter's existing in-memory ImageCache. Successful cached images
  render immediately; newly decoded images fade for 180ms. Missing/malformed/
  failed images use the official local logo on light green, including old orders.
  A successful photo no longer exposes the unavailable-image semantic label.
  No persistent disk-cache dependency or new upload mechanism was added.
- Orders use separate summary, payment and delivery cards. Existing numeric fields
  are shown without inventing missing zero amounts. Buyer totals are shown only
  to buyer/admin; farmer amounts use the existing authorized response. Existing
  earnings/commission information remains available. Order/payment badges stay
  distinct; dates use Flutter locale formatting. Long crop names get the full card
  width at large text sizes. Addresses wrap. Existing lifecycle actions remain.
- No status timeline is drawn because the inspected order response has no event
  history. No current-product lookup substitutes imagery for historical orders.
- Farmer/admin secondary pages gain matching section headings, icons, photo
  thumbnails where supported, readable metrics and constrained layouts. The
  administrator farmer filter now fits 320px at 200% text size.
- Registration email/age fields stack and role options wrap. Registration/recovery
  sheet headings wrap; recovery and OTP content scroll with large text/keyboards.
  Display labels/errors added by this pass use the existing S Tamil catalog.
- MaterialPageRoute continues using the existing Navigator. Shared Android/desktop
  transitions add a subtle fade and 2.5% vertical slide using the route animation.
  Splash retains its original authentication/role choice and 900ms startup timing;
  its exit fade is shortened to 240ms. Splash, page transitions and image fades
  respect disableAnimations. Existing Material ink/press feedback is retained.

## Scope verification

The session baseline includes copies of the original lib/test folders, git diff,
status and SHA-256 hashes. `scope-audit.json` confirms services, models, API config,
fixtures and dependencies are untouched. Existing backend/service/deployment git
changes exactly match the session-start diff. Screen classes are unchanged.
The external backend root's image/product/order routers, schemas and order service
match the inspected nested copies byte-for-byte. Neither backend root was edited.

Existing routes, auth/role permissions, API contracts, payment callbacks and server
verification, financial arithmetic, market suggestion/manual-price behavior,
validation, product publishing and order state transitions were preserved. All 107
pre-existing tests pass unchanged in their assertions. No product feature, page or
route was added or removed. No mock is used in application code. Test-only fixtures
and a local HTTP server isolate checks from production. No production data was
modified. No commit, push, deployment, Render setting or credential change occurred.

## Test evidence

- Baseline: `flutter analyze` = 14 informational lints, no errors/warnings;
  `flutter test --no-pub` = 107 passed.
- Final: `flutter analyze` executed, exit 1 due to the same 14 pre-existing info
  lints (library doc comments / legacy widget super parameters); no errors/warnings
  or new analyzer findings. The lints were left outside this presentation scope.
- Final: `flutter test` executed, exit 0, **132 passed, 0 failed** (107 existing +
  25 new). Existing tests include payment verification/failure, auth/role behavior,
  publishing, delivery, stock updates and verified-price/manual-override handling.
- New checks cover per-product URL propagation from marketplace to checkout,
  relative/absolute media authorization, rejection of malformed image URLs, no
  bearer token on external image hosts, actual JPEG decode/cache reuse/404 fallback
  using a local server, historical orders without images, buyer/farmer/admin
  detail layouts and the existing farmer acceptance transition.
- English/Tamil tests use 320px at 200% text and 390/800px layouts; secondary pages
  and registration/recovery with keyboard insets are exercised. Tests scroll
  through form/list content. No device frame-time or memory profiling was done.
- Preview run: **33 tests passed** with local test-only fonts. Screenshots cover
  role homes, auth, splash, checkout, crop/address forms, profiles, orders, payment,
  onboarding/bank, sales, admin farmer/review/commission/payout and location gate.
  Representative English/Tamil images and 200% layouts were opened and visually
  inspected. These are fixture-based Flutter widget renders, not device captures.
- `flutter devices`: Windows, Chrome and Edge targets only. `adb devices -l` showed
  no Android device; emulator AVD list was empty. No native Android/device testing,
  real Razorpay transaction, live authenticated image upload or production end-to-end
  workflow was performed. Physical-device acceptance is still required.
- At very large text sizes long app-bar titles/field labels may use existing
  ellipsis behavior. App-bar tooltips retain full titles; detail text wraps.
- `git diff --check` passes.

## Files changed in this pass

The following list is relative to the Flutter root and compares against the actual
session-start hashes, not HEAD (which already contained substantial user edits).

- `lib/screens/addresses_screen.dart`
- `lib/screens/add_product_screen.dart`
- `lib/screens/admin_dashboard_screen.dart`
- `lib/screens/auth_gateway_screen.dart`
- `lib/screens/buyer_home_screen.dart`
- `lib/screens/farmer_application_screen.dart`
- `lib/screens/farmer_bank_screen.dart`
- `lib/screens/farmer_home_screen.dart`
- `lib/screens/location_gate_screen.dart`
- `lib/screens/market_prices_screen.dart`
- `lib/screens/orders_screen.dart`
- `lib/screens/payment_screen.dart`
- `lib/screens/product_details_screen.dart`
- `lib/screens/profile_screen.dart`
- `lib/screens/splash_screen.dart`
- `lib/theme/app_theme.dart`
- `lib/utils/commerce_strings.dart`
- `lib/widgets/brand_widgets.dart`
- `lib/widgets/commerce_widgets.dart`
- `lib/widgets/produce_card.dart`
- `lib/widgets/vayal_app_bar.dart`
- `test/ui_redesign_test.dart`
- `lib/utils/presentation_format.dart`
- `lib/widgets/marketplace_product_card.dart`
- `test/premium_secondary_test.dart`
- `test/premium_ui_test.dart`
- `docs/PREMIUM_UI_AUDIT.md` (this inventory and report)


`test/ui_redesign_test.dart` only gains a configurable screenshot output directory;
its existing assertions remain intact. The two new test files contain all new
fixtures/checks. The original `docs/UI_REDESIGN.md` is retained as a prior-session
report; this document describes the current pass.

Evidence folder: `C:/VAYAL CONNECT/artifacts/premium-ui-20261015-120442`.
Relevant logs: `baseline-analyze.log`, `baseline-tests.log`, `final-analyze.log`,
`final-tests.log`, `previews-verified.log`, `scope-audit.json`, and `previews/`.

## APK build

`flutter build apk --release` succeeded (exit 0) in a fresh versioned source
snapshot. The snapshot's lib/assets match the working frontend byte-for-byte
(0 mismatches). Existing signing configuration was used without credential edits.
`apksigner verify --verbose` succeeded (exit 0), v2 signature, one signer.

APK: `C:/VAYAL CONNECT/releases/premium-ui-20261015-123255/vayalconnect-premium-release.apk`

- Size: 58,169,115 bytes.
- SHA-256: `CF97644A6B3E61AB2FD7EF65184D186187D7B7E29B378F84567D5A8CFB3B0A05`.
- All **34 pre-existing APKs** still exist with exactly their original hashes.
  Original project build APKs and all earlier release directories were untouched.
- No APK was deleted or overwritten. No package version/signing configuration
  was changed. No install, commit, push, publish or deployment was performed.
- Build has the existing Razorpay Java deprecated-API compiler note.

Build evidence: `release-build.log`, `release-artifact.json`, `apk-signature.log`,
`apk-preservation.json`, `release-verification.json`. Preview folder contains
92 PNGs from isolated widget tests. The remaining acceptance work is native Android
visual/performance testing and authenticated live upload/purchase verification in
an appropriate test environment; these are not claimed as completed.
