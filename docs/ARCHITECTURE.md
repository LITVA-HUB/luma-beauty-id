# Architecture

## iOS

```text
ios/BeautyConcierge
  App/                AppState, environment, root navigation, local fallback catalog
  DesignSystem/       tokens, buttons, chips, cards, loading/error/empty states
  Models/             Codable API models
  Services/           APIClient, KeychainStore, image cache, camera capture, haptics, observability hooks
  Features/           Onboarding, Auth, BeautyID, Scan, Advisor, Recommendations, Product, Cart, Profile, Settings
  Resources/          Assets.xcassets, asset licensing notes
```

`AppState` coordinates session, Beauty ID, recommendations, scan result, advisor, cart and profile state. Networking is `URLSession` + async/await. Tokens are stored in Keychain. Local fallback behavior is restricted to development builds and is labeled in UI.

## Backend

```text
backend/app
  main.py             routes, auth dependency, request ids and error envelopes
  schemas.py          typed request/response contracts
  config.py           development/staging/production settings validation
  security.py         token and password-hash helpers
  store.py            SQLite accounts, sessions, Beauty ID, cart, history and privacy requests
  auth_provider.py    local development auth and production contract
  catalog.py          synthetic Luma catalog and production catalog contract
  checkout.py         development handoff and production checkout contract
  scan.py             multipart validation, dev scan and production scan contract
  recommendations.py  deterministic routine/product scoring grounded to catalog
  advisor.py          advisor provider contract, prompt versioning and safety rules
```

## Providers

Production integrations are defined as contracts, not faked:

- `AuthProvider`
- `CatalogProvider`
- `CheckoutProvider`
- `ScanProvider`
- `AdvisorProvider`

Production mode blocks local/dev providers through readiness validation and clean provider-unavailable errors.

## Development catalog

`backend/app/data/catalog.json` is generated from `luma-catalog-recut-proper-v3.zip` and replaces the old seed catalog. It contains 94 synthetic Luma products based on generated packshot-card images.

Runtime product identity uses unique backend SKUs `LUMA-001` through `LUMA-094`. The non-unique SKU from the source card is stored as `source_sku` only so duplicate source labels do not collide in cart, product detail, recommendations or advisor grounding.

Product cards are copied to `backend/app/static/assets/cards/` and served by FastAPI from `/assets/cards/`. This catalog is still development/staging synthetic data; production must connect the external licensed catalog/CDN.

## API

See `docs/API_CONTRACTS.md` for routes and DTOs.

## AI/advisor

Recommendations are catalog-first. Advisor responses are grounded to known available SKUs. Medical diagnosis/treatment prompts return safe refusal. External LLM provider wiring is isolated behind `LLMAdvisorProvider`.
