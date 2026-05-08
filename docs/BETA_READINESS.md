# Beta Readiness

Status: P0 beta candidate with one release blocker.

## Release blocker

TestFlight is blocked until a real HTTPS staging API URL is provided in the Release build configuration. Release builds must not use localhost, loopback addresses, placeholder domains, empty URLs, or plain HTTP. When the URL is missing or invalid, the app shows a clean unavailable state instead of silently using a development backend.

## Configuration

- Debug can use the local backend and local development sign-in.
- Release/TestFlight uses a staging-like runtime and hides development sign-in.
- iOS does not contain OpenRouter keys and does not call OpenRouter directly.
- OpenRouter runs backend-only through the advisor endpoint.

## Secrets

`backend/.env` was removed from the workspace because it contained a real OpenRouter key. The key must be rotated before any beta or production use. Keep only placeholder templates:

- `backend/.env.example`
- `backend/.env.production.example`

## Persistence

Backend is the source of truth for:

- Beauty ID
- advisor chat history
- cart
- saved routine
- beta feedback

iOS may cache saved routine state locally for faster display, but logout clears the local cache and does not delete backend data.

## Checkout

Checkout is intentionally beta-only. The cart action is "Сохранить подборку"; it saves the current selection and does not create a payment, order, or fake checkout.

## Catalog

The current LUMA catalog is a demo/staging catalog with 94 products until the real ЗЯ catalog is provided. Do not replace product images or primary LUMA SKU during beta-readiness work.

## Scan

Photo scan is cosmetic context only. It must not be presented as diagnosis, treatment, or medical advice.

## Verification Commands

Run from the repository root unless noted:

```bash
cd backend && python3 -m pytest -q
cd backend && python3 -m compileall app
python3 scripts/rc_checks.py
xcodebuild -project ios/BeautyConcierge.xcodeproj -scheme BeautyConcierge -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project ios/BeautyConcierge.xcodeproj -scheme BeautyConcierge -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild test -project ios/BeautyConcierge.xcodeproj -scheme BeautyConcierge -destination 'platform=iOS Simulator,name=iPhone 17'
```
