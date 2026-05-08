# Security and Privacy

## Secrets

- Real secrets must come from environment variables or a secret manager.
- Never commit `.env` files.
- `OPENROUTER_API_KEY` is backend-only and must never be sent to the iOS app.
- Tests use non-real sentinel strings only.
- Logs must not include Authorization headers, tokens, provider keys, raw request bodies, emails or raw photo data.

## Auth/session

- Access tokens and refresh tokens have separate expiry.
- Logout invalidates the access token and optional refresh token.
- iOS stores tokens in Keychain and clears them on logout/session failure.
- Production auth provider remains a contract until a real identity provider is connected.

## OpenRouter and LLM privacy

- `OPENROUTER_API_KEY` is read only by the backend from environment variables.
- The key must not be committed, logged, sent to iOS or copied into Xcode settings.
- iOS calls only `POST /v1/advisor/message`; it never calls OpenRouter.
- Advisor payloads exclude raw photo/base64 data, account emails, tokens and secrets.
- Provider logs include request ID, provider name, prompt version and error code only.
- OpenRouter response content is parsed into a strict schema and then catalog-grounded by the backend before reaching iOS.
- Medical-intent requests are refused before any LLM provider call.

## Photo lifecycle

- Photo upload is optional and requires explicit user action.
- Backend accepts multipart upload, validates MIME and size, and does not persist raw photos by default.
- Production scan provider must document retention, deletion, storage location and incident response.
- `DELETE /v1/photo/scan/{scan_id}` and `POST /v1/privacy/delete-request` create deletion workflows; production adapters must complete erasure in connected systems.

## Advisor privacy

OpenRouter context is minimized to:

- user message;
- Beauty ID preference summary;
- allowed product catalog subset.

The backend does not send raw photos, base64 image data, account email, tokens, secrets or full account profile to OpenRouter.

## Medical boundary

Luma Beauty ID is a cosmetic advisor. It does not diagnose, detect disease, prescribe treatment or promise medical outcomes. Medical/treatment prompts return a gentle refusal and recommend a qualified professional for symptoms.

## Analytics/crash

- iOS has `AnalyticsService` and `CrashReporter` protocols.
- Current implementations are no-op/dev contracts.
- Production analytics must be consent-aware and must not send PII, raw Beauty ID details, raw messages, tokens, photos or secrets.

## Logging

- Backend logs request IDs, provider names, prompt version and safe provider error codes.
- Provider responses and request bodies are not logged.
- Authorization headers are never logged.
