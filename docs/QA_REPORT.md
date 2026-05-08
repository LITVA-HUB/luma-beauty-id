# QA Report

## Completed in this environment

```text
Backend pytest: 25 passed, 1 dependency warning
Backend compile: python3 -m compileall backend/app passed
OpenRouter smoke script: endpoint flow passed with explicit OpenRouter fallback in this Linux container; direct OpenRouter response could not be verified because DNS resolution for openrouter.ai failed in the container
Swift parse check: Foundation-only models/environment/observability/API client/local catalog/AppState parsed with swiftc on Linux
Xcode project reference check: 26 Swift files, missing from pbxproj: []
Shared scheme: present
Info.plist/config check: camera, photo library, API_BASE_URL and APP_ENVIRONMENT keys present
OpenRouter secret grep: no real key pattern found; only .env.production.example placeholder remains
OpenRouter in iOS grep: no OpenRouter env/key references in iOS source/docs folder
Authorization logging grep: no logger/logging references to Authorization header
Branding grep: no third-party retail branding in app identity/source/docs
```

Backend test coverage includes:

- auth register/login/refresh/logout;
- protected routes without token and expired token;
- dev auth disabled in production;
- production readiness reports unimplemented provider contracts;
- Beauty ID save/load;
- catalog list/detail/search/unavailable state;
- production catalog unconfigured error;
- recommendation SKU grounding;
- advisor medical refusal;
- OpenRouter success JSON response;
- OpenRouter invalid JSON fallback;
- OpenRouter unknown SKU guard;
- OpenRouter provider error fallback without secret leakage;
- OpenRouter medical request refusal without provider call;
- OpenRouter missing key in production clean error;
- cart add/update/delete/unavailable product;
- checkout mode behavior;
- scan MIME/size validation;
- scan provider unavailable in production;
- privacy export/delete request;
- structured error request IDs.

Observed warning:

- `python_multipart` package import deprecation warning from dependencies.

## Not available in this Linux environment

- Xcode build.
- Xcode test.
- iOS Simulator runtime navigation.
- Camera/photo permission runtime behavior.
- VoiceOver/runtime accessibility QA.

## Required macOS commands

```bash
xcodebuild -project ios/BeautyConcierge.xcodeproj -scheme BeautyConcierge -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -project ios/BeautyConcierge.xcodeproj -scheme BeautyConcierge -destination 'platform=iOS Simulator,name=iPhone 15' test
```

Use `docs/IOS_QA_CHECKLIST.md` for manual simulator/device QA.


## OpenRouter real smoke attempt

Command used with a local `backend/.env` containing the API key only at runtime:

```bash
SMOKE_BASE_URL=http://127.0.0.1:8024 python3 scripts/smoke_openrouter.py
```

Result in this environment:

```json
{
  "ok": true,
  "model": "openai/gpt-4o-mini",
  "provider": "openrouter_fallback:deterministic",
  "fallback_reason": "advisor_provider_network_error",
  "medical_safety_note": "medical_boundary"
}
```

The backend was started and `/health` confirmed `advisor_provider=openrouter` and `openrouter_configured=true`. The advisor endpoint did not crash, returned catalog-grounded SKUs only, and medical intent returned a refusal. Direct OpenRouter completion was not verified here because the container cannot resolve `openrouter.ai` (`Temporary failure in name resolution`). Run the same smoke script with `--require-openrouter-direct` from a network-enabled machine to require a direct `provider=openrouter` response.

The local `.env` used for the smoke test was not committed and must not be archived.
