# Maturity pass — 2026-05-29

A focused hardening pass that closes the App Store / production blockers raised
in review and starts paying down the largest architectural debt. Each block was
shipped as its own commit with `pytest` and `xcodebuild test` green.

## Commits

| Commit | Block | Summary |
| --- | --- | --- |
| `fd0dc0e` | 1 | Phone-based register/login, guest mode, phone upgrade |
| `9ef8350` | 2 | Real sliding-window rate limiting with 429 + `Retry-After` |
| `e14b09e` | 3 | Hard account deletion (`DELETE /v1/account/me`) for App Store compliance |
| `8334d78` | 4 | Environment config split into `.xcconfig` files |
| `d852cab` | 5 | Extract recommendation math from the `AppState` monolith (down-payment) |
| `c69ec19` | 6 | Alembic migrations with env-gated startup upgrade |
| `16af9be` | 7 | Gate checkout CTA by provider; surface legal/support links |

## What's closed

### Block 1 — Auth UX
Phone-first registration and login, country picker, guest mode, and guest →
phone upgrade. No real SMS verification by design — what the user enters is what
is stored.

### Block 2 — Rate limiting (P0)
Real in-memory sliding-window limiter (`backend/app/rate_limit.py`) behind a
`RateLimiter` interface so it can be swapped for Redis. Per-IP and
per-phone/account buckets: register 5/min/IP + 3/hour/phone, login 10/min/IP +
5/min/phone, dev-login 30/min/IP, advisor 30/min/account, scan 10/min/account.
Returns `429` with a `Retry-After` header. Gated by `RATE_LIMIT_ENABLED`
(default on; off in the test suite). Unit + endpoint tests.

### Block 3 — Account deletion (App Store 5.1.1(v) / 152-ФЗ)
`DELETE /v1/account/me` cascade-deletes every account-scoped table and the
account row, returns `204`. Real delete, no soft delete. iOS: confirm dialog →
call → logout → onboarding. Backend test asserts the account, Beauty ID, and
sessions are all gone.

### Block 4 — xcconfig split (P0)
API host and bundle id moved out of `project.pbxproj` into
`ios/Config/{Shared,Dev,Staging,Production}.xcconfig`, read at runtime via
`Info.plist` → `AppEnvironment.current`. Debug→Dev (`localhost:8010`, `.dev`
bundle), Release→Production (`com.dimalitin.lumabeautyid`). Documented in
`docs/build-configs.md`. Production `API_BASE_URL` is still a placeholder
(`https://api.lumabeautyid.app`) — see "remaining".

### Block 6 — Alembic migrations (P1)
Alembic is now the canonical Postgres schema manager. `001_initial_schema`
ports the full DDL from `PostgresStore._init_db`; `migrations/env.py` resolves
the URL from the app's `DATABASE_URL` (psycopg3 dialect). A startup hook runs
`alembic upgrade head` only when `RUN_DB_MIGRATIONS=true` **and** a Postgres
`DATABASE_URL` is set, failing closed on error. SQLite/dev and the test suite
keep using the runtime `_init_db` self-bootstrap and never touch Alembic.
Documented in `docs/database-migrations.md`. Guard tests added.

### Block 7 — Checkout gate + legal URLs + CI
- **Checkout gating:** the cart's CTA branches on the backend checkout mode.
  Only a real provider (`mode != development_handoff/unavailable`) shows an
  "Оформить заказ" purchase flow; otherwise the honest "Сохранить набор" action
  is shown, so the app never implies a purchase it cannot fulfil.
- **Legal/support URLs:** `PrivacyPolicyURL`, `SupportURL`, and
  `AccountDeletionURL` placeholders added to `Info.plist`
  (`https://lumabeautyid.app/{privacy,support,account-deletion}`), surfaced in
  Settings → "Документы" so the privacy policy and account-deletion pages are
  reachable in-app for review.
- **CI:** `.github/workflows/ci.yml` was inspected and is complete — backend
  (pytest with Pydantic warnings as errors, compileall, `rc_checks.py`, Docker
  build + compose validation) and iOS (test + unsigned release build) jobs on
  push/PR to `main`. No fix required; `scripts/rc_checks.py` passes locally
  (`missing_from_pbxproj=[]`, no secret hits). Alembic was added to
  `backend/requirements.txt` so CI installs it.

## What remains (follow-up debt)

### Block 5 — AppState decomposition (partial, intentionally deferred)
The original intent was to split the ~2.1k-line `AppState` monolith into six
stores (Auth, Onboarding, Advisor, Cart, BeautyID, Theme). A full split would
require rewriting ~150 property accesses across 15 view files, re-plumbing
environment injection, and promoting many file-private cross-cutting helpers
(`trackBackendEvent`, `resetAccountScopedState`, `userFacing`, `authTask`) — a
high-risk change for an auto-mode pass whose contract is "green after every
step, don't destabilize," on work that is **not** release-blocking.

Shipped as a safe down-payment (`d852cab`): the pure, stateless
selection/merge math was extracted into `AppState+Recommendations.swift` with no
behavior change. The remaining store extraction should be done incrementally,
one store per PR, each behind a green build, when there is room to also touch
the dependent views.

### Other open items
- **Production API host:** replace the `Production.xcconfig` `API_BASE_URL`
  placeholder (`https://api.lumabeautyid.app`) with the real host before
  submission. The release-mode guard in
  `AppEnvironment.releaseConfigurationError` already fails closed on
  `localhost`/`api.example.com`/`.invalid`.
- **Legal pages:** the privacy / support / account-deletion URLs are
  placeholders pointing at `lumabeautyid.app`; the actual pages must be
  published at those paths.
- **Real provider adapters:** auth, catalog, checkout, and scan production
  adapters are still contract-only (`validate_settings` rejects them in
  production). The checkout UI gate (Block 7) is ready for a real provider once
  one is wired.
- **Rate limiter backing store:** `InMemoryRateLimiter` is per-process; move to
  the Redis-backed implementation before running more than one API replica.
- **SMS verification:** intentionally not implemented — phone numbers are
  trusted as entered.

## Verification

- Backend: `cd backend && python3 -m pytest -q` → 61 passed.
- iOS: `xcodebuild test -scheme BeautyConcierge` → 38 tests passed.
- `python3 scripts/rc_checks.py` → clean.
