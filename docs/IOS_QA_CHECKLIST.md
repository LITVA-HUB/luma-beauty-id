# iOS QA Checklist

Run on iPhone SE-size simulator, iPhone 15 and at least one Pro Max size.

## Build/config

- Debug/development shows development sign-in.
- Release/production hides development sign-in.
- Release API URL is not localhost or placeholder.
- Bundle ID/signing configured for team.

## Flow

- Launch → onboarding → auth.
- Register/login/dev login in allowed builds.
- Session restore and refresh.
- Logout clears session.
- Beauty ID save/load.
- Continue without photo.
- Camera permission allowed/denied.
- Photo library allowed/limited/denied.
- Scan upload cancel/retry/error.
- Advisor loading, fallback and unavailable states.
- Recommendations grid, empty and error states.
- Product detail image failure/unavailable state.
- Cart add/update/delete.
- Checkout unavailable/handoff state.
- Profile/settings/privacy deletion request.

## Accessibility

- VoiceOver labels for key CTAs and product cards.
- Tap targets feel at least 44x44.
- Dynamic Type does not clip primary flows.
- Contrast acceptable on ivory/lime/orange surfaces.
- Reduced motion does not break flow.

## Safety/privacy

- No “AI detected” or diagnosis wording.
- Medical prompts are refused softly.
- Photo copy says optional and non-medical.
- Placeholder/seed visuals are not presented as real product photography.
