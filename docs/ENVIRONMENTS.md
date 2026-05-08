# Environments

## Development

- Backend: `APP_ENV=development`.
- iOS Debug: `APP_ENVIRONMENT=development`, `API_BASE_URL=http://127.0.0.1:8010`.
- Allowed: local auth, Debug development sign-in, local seed catalog, deterministic advisor, dev scan provider, development checkout handoff.
- OpenRouter is optional; if configured, errors can fall back to deterministic behavior.

## Staging

- Backend: `APP_ENV=staging`.
- iOS: `APP_ENVIRONMENT=staging`, staging API URL.
- Staging can use OpenRouter with a staging key/model.
- Seed catalog/dev scan/dev checkout may be used only if clearly labeled and not used for production claims.
- iOS development sign-in is hidden except Debug + development.

## Production

- Backend: `APP_ENV=production`.
- iOS Release: `APP_ENVIRONMENT=production`.
- `ALLOW_DEV_AUTH=false`.
- Local auth, seed catalog, dev scan, development checkout and deterministic primary advisor are blockers.
- `ADVISOR_PROVIDER=openrouter` requires `OPENROUTER_API_KEY` on backend only.
- Release config must not point to localhost. `ios/BeautyConcierge/App/AppEnvironment.swift` ignores localhost fallbacks in non-Debug builds.

## OpenRouter env

```env
OPENROUTER_API_KEY=
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_MODEL=
OPENROUTER_TIMEOUT_SECONDS=30
OPENROUTER_MAX_RETRIES=2
OPENROUTER_RESPONSE_FORMAT=json_schema
```

Backend only: never expose these values to iOS. Use a secret manager for real production values. Do not commit `.env`.


## Local .env loading

The backend now loads `backend/.env` for local commands such as `python3 -m app.main` without overriding environment variables injected by deployment platforms. Production deployments should still use a secret manager or runtime environment variables. `APP_ENVIRONMENT` is accepted as a backend fallback for local parity with the iOS build setting, but `APP_ENV` remains the canonical backend variable.

## OpenRouter smoke

Run `python3 scripts/smoke_openrouter.py` from the repository root after configuring `backend/.env`. Set `SMOKE_BASE_URL` to test a running backend process. Use `--require-openrouter-direct` only in an environment with outbound DNS/network access to OpenRouter.
