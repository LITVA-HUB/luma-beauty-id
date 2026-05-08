# Luma Beauty ID

Production Release Candidate handoff package for a native iPhone AI beauty concierge. The app builds a Beauty ID, accepts optional photo context, asks the backend advisor for catalog-grounded guidance, shows product recommendations, product detail, cart, profile and privacy controls.

This project does not use third-party retail branding, logos, copied assets, scraped product photos or copied site code. Premium beauty retail is used only as UX inspiration.

## Architecture

```text
ios/BeautyConcierge.xcodeproj     SwiftUI iPhone app
backend/                          FastAPI API and provider contracts
docs/                             release, security, API and QA docs
legacy/                           old prototype/reference note
```

The iPhone app never calls OpenRouter or any LLM provider directly. It calls only the backend endpoint `POST /v1/advisor/message`. The backend reads the OpenRouter API key from environment variable `OPENROUTER_API_KEY`.

## Runtime modes

| Mode | Purpose | Local auth | Dev catalog | Dev scan | Dev checkout | OpenRouter |
|---|---|---:|---:|---:|---:|---:|
| `development` | local simulator/dev | allowed | allowed, marked | allowed | allowed, marked | optional |
| `staging` | QA against staging services | backend-configurable | allowed only if marked | backend-configurable | backend-configurable | recommended |
| `production` | real TestFlight/App Store backend | blocked | blocked | blocked | unavailable unless provider configured | required when advisor provider is OpenRouter |

Production mode must not silently present local/dev providers as real integrations. `/ready` reports missing production provider configuration.

## What is implemented now

- SwiftUI iPhone app structure and main navigation flow.
- Keychain token storage, session restore and token refresh flow.
- Backend access/refresh tokens, expiry and logout invalidation.
- Beauty ID save/load.
- Product catalog/provider abstraction, list/search/detail endpoints and unavailable product state.
- Cart add/update/delete and checkout provider contract.
- Multipart photo scan endpoint with size/MIME validation and no raw photo persistence by default.
- Real OpenRouter advisor adapter behind backend provider interface.
- Deterministic catalog-grounded fallback when the OpenRouter provider has a transient failure.
- Medical-intent refusal rules.
- Structured error envelopes with request IDs.
- iOS analytics/crash protocols with no-op implementations and production adapter contracts.
- App Store/security/privacy/release docs.

## Dev/staging only

- Local auth provider and Debug development sign-in.
- Synthetic Luma development catalog.
- Dev scan provider.
- Development checkout handoff.
- Generated generic visuals and product fallback visuals.
- Deterministic advisor as primary provider only outside production.

These are clearly separated from production behavior and must not be marketed as live retail integrations.

## Development catalog

The old synthetic seed catalog has been replaced by the generated Luma packshot-card catalog from `luma-catalog-recut-proper-v3.zip`. The backend source of truth is now `backend/app/data/catalog.json` with 94 products.

Backend primary SKUs are unique `LUMA-001` through `LUMA-094`. The SKU printed in the generated source card is preserved only as `source_sku` for debug/reference because the source sheets contain duplicate SKU labels. Cart, product detail, recommendations and advisor grounding must use only the unique `LUMA-*` SKU.

Generated card images live under `backend/app/static/assets/cards/` and are served at `/assets/cards/<file>.png`. The catalog remains synthetic development/staging data, not a real retail catalog. `LUMA-094` is intentionally marked out of stock to keep unavailable-product UI and API tests covered.

## External services required before real TestFlight/App Store

- Production auth provider: email/phone/social identity.
- Retail catalog API/CDN with licensed product images, prices and availability.
- Checkout handoff/order system.
- Photo/scan provider with documented retention and deletion SLA.
- OpenRouter account/key and approved model, or another approved LLM provider behind the same backend interface.
- Analytics/crash SDKs after privacy review.
- Public privacy policy, support URL and account deletion workflow.

## OpenRouter advisor configuration

The iPhone app never calls OpenRouter directly. The backend reads the API key from environment only and exposes the advisor through `POST /v1/advisor/message`.

Required backend variables when `ADVISOR_PROVIDER=openrouter`:

```env
ADVISOR_PROVIDER=openrouter
OPENROUTER_API_KEY=
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_MODEL=
OPENROUTER_TIMEOUT_SECONDS=30
OPENROUTER_MAX_RETRIES=2
OPENROUTER_RESPONSE_FORMAT=json_schema
```

`OPENROUTER_API_KEY` must come from a secret manager or deployment environment. Do not commit `.env` or put the key into Swift, Xcode configs, docs or tests. In production, `/ready` reports missing OpenRouter configuration as a blocker. Runtime OpenRouter failures fall back to an explicitly labeled catalog-grounded advisor response; missing production configuration does not masquerade as a live LLM.


### OpenRouter smoke test

The real advisor integration can be checked separately without making normal `pytest` require an API key:

```bash
cd backend
cp .env.example .env
# Put the real key only into backend/.env or your shell environment. Do not commit it.
# Set ADVISOR_PROVIDER=openrouter and OPENROUTER_MODEL to the approved model.
python3 -m app.main

# In another shell from repository root:
SMOKE_BASE_URL=http://127.0.0.1:8010 python3 scripts/smoke_openrouter.py
```

For CI or a local in-process check, omit `SMOKE_BASE_URL`; the script imports the FastAPI app after loading `backend/.env`. Use `--require-openrouter-direct` when the environment has outbound network access and the run must fail on deterministic fallback.

## Run backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python3 -m app.main
```

Default development API URL: `http://127.0.0.1:8010`.

```bash
curl http://127.0.0.1:8010/health
curl http://127.0.0.1:8010/ready
```

## Run iPhone app

1. Open `ios/BeautyConcierge.xcodeproj` in Xcode 15+.
2. Select an iPhone simulator.
3. Run the backend locally or point Debug config to a staging backend.
4. Run the shared `BeautyConcierge` scheme.

Debug build settings:

```text
API_BASE_URL = http://127.0.0.1:8010
APP_ENVIRONMENT = development
```

Release build settings currently use a placeholder API URL and must be replaced before TestFlight:

```text
API_BASE_URL = https://api.example.com
APP_ENVIRONMENT = production
```

## Tests

Backend:

```bash
cd backend
python3 -m pytest -q
cd ..
python3 -m compileall backend/app
```

Available Linux iOS structural checks are documented in `docs/QA_REPORT.md`. On macOS/Xcode:

```bash
xcodebuild -project ios/BeautyConcierge.xcodeproj -scheme BeautyConcierge -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -project ios/BeautyConcierge.xcodeproj -scheme BeautyConcierge -destination 'platform=iOS Simulator,name=iPhone 15' test
```

This package is not claimed App Store-ready until Xcode build/test and device QA are completed on macOS.

## Key docs

- `docs/API_CONTRACTS.md`
- `docs/SECURITY_PRIVACY.md`
- `docs/ENVIRONMENTS.md`
- `docs/PRODUCTION_RELEASE_CRITERIA.md`
- `docs/PRODUCTION_GAPS.md`
- `docs/APP_STORE_READINESS.md`
- `docs/IOS_QA_CHECKLIST.md`
- `docs/ASSET_PRODUCTION_GUIDE.md`
- `docs/QA_REPORT.md`
