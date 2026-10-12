# Farmer onboarding and admin approval fix

Verified on 2026-10-12. Changes are local source changes only. No deployment,
push, APK build, account reset, database migration or production write was performed.

## Failure trace and evidence

The user confirmed that **Submit for review** triggers the reported error.
`FarmerApplicationScreen._submit` calls `FarmerService.submitApplication`, which
sends authenticated `PUT /api/v1/farmers/me/application` with the application
and its revision. The existing `OnboardingService.submit` requires a matching
`farmer_profiles.user_id` record. When it is absent, the endpoint returns
`404`, code `NOT_FOUND`, message `Farmer profile not found.` Flutter's original
`ApiClient` discards this error and substitutes
`Unable to complete this request. Please retry.`

A read-only aggregate of the Atlas database configured in the local backend
environment found one FARMER account and zero farmer profiles. No identifiers,
credentials or account details were included in diagnostics. Running the original
service from repository HEAD against this missing-profile condition reproduced
`404 NOT_FOUND Farmer profile not found.`

The profile GET displays a fallback `PENDING` status when no profile exists.
The original admin list reads only farmer profiles, so this account is absent
there as well. Bank saving has the same missing-profile error. Role selection
previously wrote the user role and created the role profile as separate operations:
failure between these writes can create this inconsistent state. The historical
event that produced the existing record was not established from server logs.

Read-only production checks confirmed the onboarding routes and request schemas
exist and `/health` reports a connected database at commit
`e9aa3c05aa8dda8ee42e1c9598d1fdbb21f7f90d`. No authenticated production submission
was replayed. Local Atlas configuration alone does not establish that Render uses
identical database environment settings.

## Resulting behavior

- Role assignment and role-profile creation now commit together in a MongoDB transaction.
- A verified, authenticated farmer can create their missing PENDING profile through
  an explicit application submission or bank save. Insert-only defaults preserve
  existing applications, decisions and encrypted bank details. GET requests do not repair data.
- Admin lists, pending counts and detail views include farmer accounts missing a
  profile. These views explicitly distinguish an unsubmitted application. Review
  still requires a submitted application, complete payout details, verification
  and an explicit administrator decision.
- Approval/rejection continues to use the farmer's user ID and reviewed revision.
  The profile decision and account approval flag commit atomically. Invalid stored
  application data yields a clear validation response instead of an internal error.
- Existing publishing authorization and buyer list/detail filtering were retained
  and verified: pending/rejected farmers cannot publish; inactive/out-of-stock
  products and products from unapproved farmers are hidden from buyers. Editing an
  approved application resets approval and requires another administrator review.
- Flutter preserves domain error messages and field names, exposes request metadata
  through `ApiException`, and displays messages without the `Exception:` prefix.
  Server internal details stay hidden. Timeout messages tell users to refresh to
  determine whether a write succeeded. Progress indicators and disabled buttons
  protect submission/review; failed admin detail refreshes disable decisions.
- Admin service methods check the response envelope and no longer silently succeed
  in demo mode. Existing demo features elsewhere remain intact.

## Validation

Backend: **159 passed** using all tests in `tests/`, including real MongoDB
integration tests on a new local replica set at `127.0.0.1:27019`. Test fixtures
created and removed only uniquely named disposable local databases. External
government market/payment providers use explicit test fixtures; onboarding,
authorization, transactions and persistence use the real local MongoDB server.

```powershell
$env:VAYALCONNECT_RUN_MONGO_TESTS = '1'
$env:MONGODB_URI = 'mongodb://127.0.0.1:27019/?replicaSet=vayal_verification'
$env:VAYALCONNECT_TEST_MONGO_URI = $env:MONGODB_URI
& .\venv\Scripts\python.exe -m pytest -q tests --tb=short
```

Flutter: **71 passed** with `flutter test --no-pub`. Analysis with
`flutter analyze --no-pub --no-fatal-infos` exits successfully with 19 existing
informational lints outside the changed files; no warnings or errors.
`git diff --check` passes.

New regression coverage verifies application-first and bank-first recovery,
read-only admin visibility, invalid revisions, verification/role enforcement,
submission, rejection, approval of the correct profile, preservation of account
identity/password/session fields, transaction rollback, publishing, marketplace
filtering, renewed approval after edits, useful Flutter errors, loading, and
disabled decisions after a failed refresh.

## Exact changed files

In the Git repository `C:\VAYAL CONNECT\vayalconnect-flutter`:

```text
lib/screens/admin_dashboard_screen.dart
lib/screens/farmer_application_screen.dart
lib/services/admin_service.dart
lib/services/api_client.dart
test/onboarding_errors_test.dart                         (new)
vayalconnect-backend/app/api/v1/admin.py
vayalconnect-backend/app/api/v1/farmers.py
vayalconnect-backend/app/repositories/farmers.py
vayalconnect-backend/app/schemas/farmer.py
vayalconnect-backend/app/services/auth_service.py
vayalconnect-backend/app/services/onboarding_service.py
vayalconnect-backend/app/services/report_service.py
vayalconnect-backend/tests/test_onboarding_recovery_mongo.py (new)
vayalconnect-backend/docs/FARMER_ONBOARDING_FIX.md          (new)
```

The identical backend source, tests and report were also updated in the existing
standalone workspace `C:\VAYAL CONNECT\vayalconnect-backend`:

```text
app/api/v1/admin.py
app/api/v1/farmers.py
app/repositories/farmers.py
app/schemas/farmer.py
app/services/auth_service.py
app/services/onboarding_service.py
app/services/report_service.py
tests/test_onboarding_recovery_mongo.py                   (new)
docs/FARMER_ONBOARDING_FIX.md                             (new)
```

No environment files, secrets, authentication keys, existing accounts, production
data, database names, deployment configuration or existing product features were
changed. The fix will take effect in production only after a separately confirmed
release. There is no automatic approval or bulk data repair.
