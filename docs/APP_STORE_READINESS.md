# App Store Readiness Notes

## Permission strings

- Camera: optional beauty preference context; not a medical scan or diagnosis.
- Photo Library: selected photo only; user can continue without photo.

## Privacy labels draft areas

Review with counsel/product before submission:

- Account identifiers for login/session.
- User-provided Beauty ID preferences.
- Optional photo upload if user chooses scan flow.
- Product interaction/cart events if analytics is connected.
- Crash diagnostics if crash SDK is connected.

## Review notes

- Luma Beauty ID is a non-medical cosmetic advisor.
- It does not diagnose skin conditions, detect disease, prescribe treatment or promise medical outcomes.
- Photo upload is optional and can be skipped.
- Advisor recommendations are catalog-grounded.
- Checkout must be either real or clearly unavailable.

## Required URLs before submission

- Privacy policy URL.
- Support URL.
- Account deletion URL or in-app deletion workflow connected to backend.

## macOS CI commands

```bash
xcodebuild -project ios/BeautyConcierge.xcodeproj -scheme BeautyConcierge -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -project ios/BeautyConcierge.xcodeproj -scheme BeautyConcierge -destination 'platform=iOS Simulator,name=iPhone 15' test
```

This Linux environment cannot execute those commands.
