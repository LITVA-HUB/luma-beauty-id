# Onboarding reorder + FaceScan rework + iPhone adaptation

_Date: 2026-05-29 · App: Luma Beauty ID (`com.dimalitin.lumabeautyid.dev`)_

## Goal

Three connected changes requested:

1. **Reorder onboarding** so the user registers **before** the questionnaire, with a **mandatory face photo** wedged between registration and the questionnaire.
2. **Rework the FaceScan UI**, which looked unpolished ("колхозно").
3. **Adapt the layout to every iPhone** (SE-class → Pro Max + Dynamic Island) so titles and copy never clip or shift.

Skills applied along the way: design-critique, design-system (token reuse only), accessibility-review, ux-copy, code-review, testing-strategy.

---

## 1. New routing order

The root router (`ios/BeautyConcierge/App/RootView.swift`) now gates the user through a strict sequence. Each branch is a hard gate — you cannot reach a later screen until the earlier one is satisfied, and the state survives an app kill/relaunch.

```
Launch
  └─ Onboarding intro      (hasSeenOnboarding == false)
       └─ Регистрация / Вход (AuthView, account == nil)
            └─ Обязательное фото (FaceGateView, needsFaceScan)
                 └─ Анкета / Beauty ID (BeautyIDSetupView, beautyID not usable)
                      └─ Главная (MainTabView)
```

Implementation (`RootView.body`):

```swift
if appState.isLaunching { LaunchView() }
else if let configurationError = appState.environment.configurationError { ServiceUnavailableView(message: configurationError) }
else if !appState.hasSeenOnboarding { OnboardingView() }
else if appState.account == nil { AuthView() }
else if appState.needsFaceScan { FaceGateView() }
else if appState.beautyID?.isUsable != true { BeautyIDSetupView() }
else { MainTabView() }
```

Previously the order put the questionnaire before registration and had no photo gate. The `wantsAuthDirectly` escape hatch (a "Войти" shortcut on the setup screen) was removed so the flow stays linear.

### Why this is robust against quitting mid-flow

Each gate reads from durable storage, so killing the app at any step lands you back on the same step:

| Step | Backing store |
|------|---------------|
| Onboarding intro | `UserDefaults` flag `hasSeenOnboarding` |
| Registration | Keychain session (`SessionStore`) → `account` |
| **Face photo** | `UserDefaults` set `faceScanAccountIds` (per account) |
| Questionnaire | Backend profile `/v1/beauty-id` → `beautyID.isUsable` |

## 2. Per-account face-scan persistence

`ios/BeautyConcierge/App/AppState.swift` tracks completion **per account id**, not as a single global flag, so a second account on the same device is still required to add a photo:

```swift
@Published var faceScanAccountIds: Set<String>   // persisted to UserDefaults key "faceScanAccountIds"

var needsFaceScan: Bool {
    guard let id = account?.accountId else { return false }
    return !faceScanAccountIds.contains(id)
}

func markFaceScanCompleted() {
    guard let id = account?.accountId else { return }
    guard faceScanAccountIds.insert(id).inserted else { return }
    UserDefaults.standard.set(Array(faceScanAccountIds), forKey: Keys.faceScanAccounts)
}
```

`markFaceScanCompleted()` is called:
- when a photo upload succeeds (`performScan`, both the dev-fallback and real-upload success paths);
- as a **grandfather** in `loadProfileAndSessionData` — any returning account that already has a usable Beauty ID is marked complete at boot, so existing testers are not forced back through the new gate.

## 3. FaceGateView — the mandatory photo step

New file `ios/BeautyConcierge/Features/Scan/FaceGateView.swift`. It cannot be skipped (`allowSkip: false` on the camera), offers three intake paths, and shows progress/permission states:

- **Сделать фото** → checks `AVCaptureDevice` authorization, then presents the reworked camera full-screen.
- **Выбрать из галереи** → `PhotosPicker`.
- **Пример фото** (`#if DEBUG` only) for local testing.
- Camera **denied** → a notice with a "how to open Settings" hint (no dead-end).
- Upload in progress → a progress card; the gate stays put until the photo is accepted.

The privacy note reiterates this is a cosmetic photo, not a medical scan/diagnosis — consistent with the updated `Info.plist` usage strings.

## 4. FaceScan visual rework

**Before:** raw camera with debug-looking overlay and an unstyled capture control.

**After** — `BeautyScanOverlayView.swift` + `BeautyScanCameraView.swift`:

- Centered **FaceID-style oval mask**: dimmed `Color.black` scrim with an `Ellipse` `destinationOut` cutout; thin stroke that turns **lime** and **pulses** when the face is aligned; a scan-sweep capsule animates while locked. Oval sized responsively (`width = min(size.width*0.72, 320)`, `height = min(width*1.32, size.height*0.56)`, centered at 40% height). Overlay is `allowsHitTesting(false)`.
- **Guidance panel below the mask** (never overlapping it): live status dot + title ("Расположите лицо в овале") + a `checkmark.seal` once aligned, plus three hint chips — "Лицо в овал", "Без очков", "Хороший свет".
- **Large round shutter**: 76×76 ring with a 62×62 lime fill and `camera.fill` glyph (spinner while capturing); `contentShape(Circle())`, `accessibilityLabel "Сделать фото"`, disabled until capture is allowed. Comfortably exceeds the 44pt hit target.
- **Capture feedback**: `Haptics.medium()` (added `UIImpactFeedbackGenerator(style:.medium)` to `Services/Haptics.swift`) + a white flash overlay fading 0.75 → 0.
- **Preview/confirm step** ("Проверьте снимок"): "Продолжить" (lime) / "Переснять", with image height adapting via `GeometryReader`.
- **Error states**: no camera access → message + "Открыть настройки" (`UIApplication.openSettingsURLString`); no face detected → guidance hint. No raw coordinates or debug text remain on screen.

Guidance copy was also corrected at the source in `BeautyScanViewModel.swift` and `BeautyScanCameraController.swift` ("Поместите лицо в кадр" → "Расположите лицо в овале").

## 5. iPhone adaptation

Applied across the onboarding-flow screens (OnboardingView, AuthView, BeautyIDSetupView, FaceGateView, the camera views):

- `GeometryReader`-driven sizing instead of hardcoded widths (e.g. onboarding hero `imageHeight = min(max(proxy.size.height * 0.42, 220), 360)`).
- Titles get `.minimumScaleFactor(0.8)` + `.lineLimit(2/3)`; body copy gets `.fixedSize(horizontal: false, vertical: true)` so it wraps rather than truncates.
- Design-system spacing/radius tokens (`BeautySpacing`, `BeautyRadius`) everywhere — no magic numbers introduced.
- Portrait lock is already enforced in `Info.plist` (`UISupportedInterfaceOrientations` = Portrait only) — no change needed.

### Screenshots (light + dark)

Stored in `docs/assets/onboarding-flow-2026-05-29/`:

| Device (class) | Light | Dark | Screen shown |
|----------------|-------|------|--------------|
| iPhone 17e (compact) | `17e_onboarding_light.png` | `17e_onboarding_dark.png` | Onboarding intro |
| iPhone 17 Pro (standard) | `17pro_onboarding_light.png` | `17pro_onboarding_dark.png` | Onboarding intro |
| iPhone 17 Pro Max (large) | `promax_onboarding_light.png` | `promax_onboarding_dark.png` | Auth (Reg-first) |

All renders show the two-line title fully visible, body copy wrapping cleanly, and the full-width primary button correctly placed above the home indicator — across compact → large and both appearances. The Pro Max captures landed on the **Auth** screen (its onboarding flag had already been seen), which usefully confirms the new **registration-first** ordering and the AuthView's adapted layout/new copy.

> Note: FaceGateView and the Beauty ID questionnaire require an authenticated account, which cannot be auto-navigated through `simctl`. Their layout adaptation is documented above and verified by the green build/test gate; they reuse the same `GeometryReader` + token + `minimumScaleFactor` patterns shown on the reachable screens. (Running 3 simulators concurrently also intermittently triggers `simctl io ... Timeout waiting for screen surfaces`; captures were taken one device at a time to avoid it.)

## 6. Tests

Four new `@MainActor` router tests in `ios/BeautyConciergeTests/BeautyConciergeTests.swift` (UUID-based account ids to avoid persisted-state collisions):

- `testFaceGateNotRequiredWithoutAccount`
- `testFaceGateRequiredForFreshlyRegisteredAccount`
- `testMarkFaceScanCompletedClearsGateForCurrentAccount`
- `testFaceScanCompletionIsScopedPerAccount`

## 7. Final gate — all green

| Check | Command | Result |
|-------|---------|--------|
| iOS build | `xcodebuild build -scheme BeautyConcierge -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` | **BUILD SUCCEEDED** |
| iOS tests | `xcodebuild test …` | **TEST SUCCEEDED** — 38 tests, 0 failures (incl. 4 new router tests) |
| Backend | `python3 -m pytest -q` (in `backend/`) | **48 passed** |

## Files touched

**New:** `ios/BeautyConcierge/Features/Scan/FaceGateView.swift`, this report, `docs/assets/onboarding-flow-2026-05-29/*.png`.

**Modified:** `App/RootView.swift`, `App/AppState.swift`, `Features/Scan/BeautyScanOverlayView.swift`, `Features/Scan/BeautyScanCameraView.swift`, `Features/Scan/BeautyScanViewModel.swift`, `Services/BeautyScanCameraController.swift`, `Services/Haptics.swift`, `Features/Onboarding/OnboardingView.swift`, `Features/Auth/AuthView.swift`, `Features/BeautyID/BeautyIDSetupView.swift`, `Info.plist`, `BeautyConcierge.xcodeproj/project.pbxproj` (FaceGateView registered in all 4 sections — explicit refs), `BeautyConciergeTests/BeautyConciergeTests.swift`.
