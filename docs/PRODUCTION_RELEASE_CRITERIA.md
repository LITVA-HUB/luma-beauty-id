# Production Release Criteria

This repository is a Production Release Candidate foundation, not a completed App Store submission.

## Backend gates

- `APP_ENV=production`.
- `/ready` returns `ready` with no provider/config blockers.
- External auth provider connected.
- External catalog provider connected with licensed image URLs and live availability.
- External checkout provider connected or checkout UI disabled/unavailable by product decision.
- External scan/photo provider connected with retention/deletion SLA.
- `ADVISOR_PROVIDER=openrouter` configured with backend-only `OPENROUTER_API_KEY` and approved model.
- Backend tests pass.
- Structured logs verified to contain no secrets/PII/raw photos.

## iOS gates

- Release `API_BASE_URL` set to production backend, not localhost or placeholder.
- Release `APP_ENVIRONMENT=production`.
- Development sign-in hidden.
- Xcode build and test pass on macOS.
- iPhone simulator/device QA complete.
- VoiceOver/Dynamic Type/reduced motion pass complete.
- Camera/photo permission strings reviewed.
- Final licensed assets and product photos integrated.

## App Store gates

- Privacy policy URL.
- Support URL.
- Account deletion URL/workflow.
- Privacy nutrition labels drafted.
- App Review notes explain non-medical beauty advisor boundary and optional photo use.
- Screenshots do not show dev/staging assets as final retail photography.
