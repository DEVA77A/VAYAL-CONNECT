# UI redesign audit

## Existing application

The app uses MaterialApp, imperative Navigator routes, stateful screens, a
SessionManager notifier, LanguageRebuild, VayalStrings and the S commerce
catalog. HTTP services and role permissions remain in their existing layers.
No routing, state-management or dependency migration is planned.

Buyer: marketplace search/category/sort/pagination, checkout, delivery address
selection and estimate, orders/detail, Razorpay test checkout, profile.
Farmer: approval/onboarding, bank details, dashboard, crops/add/edit, stock
adjustment, availability, sales, payouts, market references, orders, profile.
Admin: dashboard/date filters, farmer review, buyers/activity, commission,
orders and payout review. Shared: auth/register/OTP/password recovery,
location gate, language toggle, errors/retries and market-price search.

Brand artwork: assets/branding/vayalconnect-logo.jpeg, including the approved
Tamil tagline. Existing splash chooses the destination using SessionManager.
Android launch configuration and startup destination logic are preserved.

## Safety baseline

Before work, admin_dashboard_screen.dart and farmer_application_screen.dart
already had user edits, as did admin_service.dart, api_client.dart, render.yaml
and several backend files. There were untracked onboarding tests and backend
files. Existing screen diffs were saved under artifacts outside this repo.
Those changes are retained; services, backend and deployment configuration
are outside this redesign. No commits, pushes or deployments are authorized.

## Design

Green actions, deep green headers, black typography, white cards, warm neutral
canvas and brown secondary accents. Shared controls retain their callbacks.
Cards grow with text; forms scroll with keyboards; headings and sections use
the existing bilingual catalog. Product photography uses real image URLs
and the existing media authorization pattern, with a neutral crop fallback.
No verification or freshness claim is inferred from an image or product.

## Implemented presentation changes

- Shared Material 3 palette, Roboto typography with Tamil system fallback,
  48–52px minimum button sizes, rounded outlined cards, quieter dividers,
  consistent input borders and multiline validation/helper messages.
- Deep green role-aware app bars retain back, language persistence and supplied
  actions. Existing navigation chips wrap; no destinations or routing architecture
  were replaced. The unused bottom-navigation component was left intact.
- Approved original artwork sits fully contained inside a white circle and green
  ring. Splash fades/scales gently, respects reduced motion, uses existing brand
  strings, and retains the same role-based destination selection. Its original
  artificial 2.2-second wait is shortened to 0.9 seconds; no fake progress is shown.
- Buyer marketplace: greeting panel, labelled filters, consistent real-photo
  cards, seller/location/stock details and prominent actual prices. Missing images
  have an agricultural icon fallback without fabricated product imagery.
- Checkout: responsive image, grouped quantity/price information, readable
  original price breakdown, delivery controls and existing ordering action.
- Farmer: dashboard hierarchy, approval/publishing panel, responsive metrics,
  all existing module links, crop form sections, readable stock/price/location/
  harvest groups, and application/bank form headings.
- Market references: distinct brown unavailable panel and green available panel;
  existing verification conditions, stale labels, quote units, source links,
  timestamps, observations, conversion and manual-price handling are unchanged.
- Admin: management header, wrapped module actions, responsive metric cards.
  Farmer review, buyers/activity, commission and payout review receive the shared
  typography, controls, cards and detail-row styling. Review permissions unchanged.
- Orders: labelled filters and an actual-lifecycle status badge in order detail.
  Record lists, empty/error/retry panels, payment and profile share the new styling.
- Login: original controls reflow for small phones and large Tamil text. Login,
  registration, OTP, recovery, development configuration and preview actions remain.

## Files changed by this redesign

All paths below are relative to the Flutter repository. Pre-existing edits in
other files shown by `git status` do not belong to this redesign.

| Area | Files |
| --- | --- |
| Design system | `lib/theme/app_theme.dart` |
| Shared presentation | `lib/widgets/brand_widgets.dart` (new), `commerce_widgets.dart`, `market_reference_view.dart`, `vayal_app_bar.dart`, `vayal_logo.dart` |
| Buyer | `lib/screens/buyer_home_screen.dart`, `product_details_screen.dart`, `addresses_screen.dart` |
| Farmer | `lib/screens/farmer_home_screen.dart`, `add_product_screen.dart`, `farmer_application_screen.dart`, `farmer_bank_screen.dart` |
| Admin | `lib/screens/admin_dashboard_screen.dart` |
| Shared screens | `lib/screens/auth_gateway_screen.dart`, `splash_screen.dart`, `market_prices_screen.dart`, `orders_screen.dart`, `payment_screen.dart`, `profile_screen.dart` |
| Localization | `lib/utils/commerce_strings.dart`: Tamil translation for the Price filter label |
| Tests | `test/ui_redesign_test.dart` (new); scroll-to-control adjustments in `commerce_workflows_test.dart`, `login_screen_test.dart`, `milestone_screens_test.dart`, and the user's pre-existing untracked `onboarding_errors_test.dart` |
| Documentation | `docs/UI_REDESIGN.md` |

Existing test assertions are retained. Scroll adjustments accommodate taller,
accessible controls and lazy list construction; no tests were removed.

## Scope verification

The per-file audit at `../artifacts/ui-redesign-scope-audit.json` compares the
current services, models, API configuration and fixtures byte-for-byte against
the session-start backup. All are unchanged, including the user's pre-existing
service edits. Backend files, schemas, credentials, deployment configuration,
API contracts, endpoints, permissions, payment/commission calculations and
market-price business logic were not edited. No product feature, route or
workflow was added or removed. No package was added or upgraded. No commit,
push or deployment was performed.

## Verification and limitations

`flutter pub get` succeeded. Baseline analysis reported 17 informational lints
and baseline tests passed 99 tests. Final analysis reports 14 informational
lints, all present in the original baseline; no errors or warnings. Analysis
therefore still exits nonzero under the project's default lint policy. Model
doc-comment and unused shared-widget constructor lints were left outside scope.

The new layout tests exercise buyer/farmer/admin, crop form, checkout, orders,
profile, address form, login and splash in English and Tamil, at 390px width and
at 320px with 200% text. Explicit splash tests assert signed-out, buyer, farmer
and admin destinations. Existing tests cover services, authentication, approval,
market suggestions/manual overrides, stock changes, delivery, server-confirmed
test payments and failure handling. They use isolated fixtures, not production
transactions.

Rendered-widget PNGs are in `../artifacts/ui-redesign-20261015-previews`.
Buyer, farmer, admin, login, checkout, crop/address forms, profile, orders and
splash were rendered in both languages. Representative images were opened and
visually inspected. Optional PNG generation loads locally installed fonts in the
test process only; no test fixtures or preview fonts are shipped in the app.

No Android device/emulator was connected. Browser automation reported no
available browsers; a local web-server run was stopped after this check. There
was no live end-to-end verification against production, no real payment, and no
native-device visual verification. Device acceptance of all role workflows,
network images, keyboards, native launch and the payment SDK remains necessary
before calling the redesign production-verified. Some long app-bar titles retain
the existing ellipsis presentation; their underlying text and routes are intact.

Final `flutter test --no-pub`: **107 passed, 0 failed** (99 existing tests and
8 new layout/startup tests). `git diff --check` passed. No existing assertions
were removed. English and Tamil layout runs both passed; manual-price, stale
reference, payment verification and approval regression tests passed.

Both final APK builds exited 0. Release signing was already configured and
`apksigner verify --verbose` confirms a valid v2 signature with one signer.
The existing Razorpay dependency emits a Java deprecated-API compiler note;
it does not prevent either build.

New output directory:
`C:\VAYAL CONNECT\releases\ui-redesign-20261015-100357`

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `vayalconnect-ui-debug.apk` | 186102458 | `A4F70CD5FA20A967F4E12A54BE5DB114C05A7F59C8C8C2D4123F4CD9CF5B46A1` |
| `vayalconnect-ui-release.apk` | 58037627 | `24B7AD0AD3EE83A9036C966D7C1DA480AC19E6604A4D1A2E24E3B9C560056F47` |

Existing APKs from the standard build output directory were copied into this
new directory's `prior-build-outputs` before the final builds. Existing release
directories were not overwritten or deleted. Standard Flutter build outputs
were regenerated normally. No production configuration or signing credentials
were changed.

Check evidence under `C:\VAYAL CONNECT\artifacts`:
`ui-redesign-analyze.log`, `ui-redesign-tests.log`,
`ui-redesign-previews.log`, `ui-redesign-debug-build.log`,
`ui-redesign-release-build.log`, `ui-redesign-scope-audit.json`.
