# Luma Beauty ID Backend

FastAPI backend for the Luma Beauty ID iPhone app. It owns auth/session, Beauty ID, catalog contracts, cart, scan contracts, checkout contracts and advisor provider integration.

## Run

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python3 -m app.main
```

## Provider separation

- `AuthProvider`: local development provider plus external production contract.
- `CatalogProvider`: local seed provider plus production catalog contract.
- `CheckoutProvider`: development handoff plus production handoff contract.
- `ScanProvider`: dev no-store provider plus production scan contract.
- `AdvisorProvider`: deterministic fallback plus real OpenRouter adapter.

Production mode does not treat local/dev adapters as live integrations. Missing production providers are surfaced through `/ready` and structured errors.

## OpenRouter advisor

Set `ADVISOR_PROVIDER=openrouter` and provide these environment variables on the backend only:

```env
ADVISOR_PROVIDER=openrouter
OPENROUTER_API_KEY=
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_MODEL=
OPENROUTER_TIMEOUT_SECONDS=30
OPENROUTER_MAX_RETRIES=2
OPENROUTER_RESPONSE_FORMAT=json_schema
```

The provider uses Chat Completions at `/chat/completions`, requests JSON-schema structured output, sends only minimized Beauty ID and catalog subset context, validates returned SKUs against the catalog, and falls back to deterministic catalog-grounded advice for transient provider failures. Missing credentials in production return a clean provider-unconfigured error.


## Real OpenRouter smoke test

Normal unit tests do not require an API key. To test the live OpenRouter path, put the key only in local `backend/.env` or shell environment and run:

```bash
# Optional: start a real local backend process
python3 -m app.main

# From repository root in another shell
SMOKE_BASE_URL=http://127.0.0.1:8010 python3 scripts/smoke_openrouter.py
```

The smoke script checks `/v1/advisor/message`, SKU grounding, medical refusal and backend stability. Use `--require-openrouter-direct` to fail when the endpoint falls back to deterministic advice.

## Tests

```bash
python3 ../scripts/check_backend.py
python3 -m pytest -q
python3 -m compileall app
```
