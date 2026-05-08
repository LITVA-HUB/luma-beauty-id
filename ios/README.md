# Luma Beauty ID iOS

Native SwiftUI iPhone app for Luma Beauty ID.

## Run

1. Open `ios/BeautyConcierge.xcodeproj` in Xcode 15+.
2. Select the shared `BeautyConcierge` scheme.
3. Run a backend or staging API.
4. Build on an iPhone simulator.

## Config

Build settings inject:

- `API_BASE_URL`
- `APP_ENVIRONMENT`

Debug defaults to local development. Release defaults to a placeholder production URL and must be replaced before TestFlight.

The app never contains LLM provider keys and never calls LLM providers directly. Advisor requests go to backend `POST /v1/advisor/message`.

## macOS checks

```bash
xcodebuild -project ios/BeautyConcierge.xcodeproj -scheme BeautyConcierge -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -project ios/BeautyConcierge.xcodeproj -scheme BeautyConcierge -destination 'platform=iOS Simulator,name=iPhone 15' test
```
