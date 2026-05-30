# Золотое Яблоко rebrand pass — 2026-05-29

A targeted brand pass: in-app name, brand accent colour, and typeface only. No
architecture, business-logic, bundle-id, app-icon, launch-screen, or
navigation changes — this is **not** a redesign of layouts.

## 1. Typeface — Onest (SIL OFL 1.1)

**Chosen: Onest.** Of the three candidates (Manrope / Inter / Onest), Onest was
picked because:

- It is a clean, neutral grotesque — the closest free match to Goldapple's
  proprietary **GA Sans** seen in the reference shots (heavy, even-weight caps;
  double-story `a`; humanist digits in prices like `791 ₽` / `798 ₽`).
- Its Cyrillic is purpose-built (the project is Russian-first), so tracked
  uppercase category labels («МУСС ДЛЯ ГУБ И ЩЕК», «КИСТЬ ДЛЯ РУМЯН И ПУДРЫ»)
  and prices render correctly without fallback to the system font.
- Manrope reads more geometric/rounded and Inter more "UI-utility"; Onest sits
  closest to the brand's editorial grotesque.

GA Sans itself is proprietary and is **not** redistributable, so it was not an
option to bundle.

**Files** (`ios/BeautyConcierge/Resources/Fonts/`), instanced from the upstream
variable font with `fontTools.varLib.instancer` and given unique PostScript
names:

| File | PostScript name | Weight |
| --- | --- | --- |
| `Onest-Regular.ttf` | `Onest-Regular` | 400 |
| `Onest-Medium.ttf` | `Onest-Medium` | 500 |
| `Onest-Bold.ttf` | `Onest-Bold` | 700 |

- License: `Resources/Fonts/LICENSE.txt` (SIL Open Font License 1.1, upstream
  `OFL.txt`, "Copyright 2021 The Onest Project Authors").
- Registered in `Info.plist` → `UIAppFonts` and added to the Xcode project
  (`PBXBuildFile` + `PBXFileReference` + group + Resources build phase).
- Verified embedded in the built `.app` and listed in `UIAppFonts`.

## 2. Brand accent colour — Goldapple lime

Sampled the centre of the official spring-promo banner
(`IMG_6406.jpeg`) with Pillow:

```
rgb(226, 254, 82)  →  #E2FE52
```

Applied to `BeautyColor.lime` in `DesignSystem/BeautyDesignSystem.swift` as a
constant brand fill (identical in light and dark — it is a fixed brand colour,
like the real banner). The accessibility-tuned `limeTint` (foreground accent for
tab tint) and `limeInk` (text-on-lime) were left as-is.

**WCAG (sRGB relative-luminance contrast):**

| Foreground | On `#E2FE52` | Verdict |
| --- | --- | --- |
| `ink` (near-black `rgb(19,18,16)`) | **16.52 : 1** | passes AA & AAA |
| `limeInk` (`rgb(20,22,13)`) | **16.11 : 1** | passes AA & AAA |
| white | 1.13 : 1 | fails — dark text kept, never white |

So text on the brand lime stays dark, per requirement.

## 3. Typography system swap

`BeautyFont` tokens moved from `Font.system(...)` to `Font.custom("Onest-…")`.
Point sizes are unchanged 1:1 so the hierarchy and layout are preserved — only
family/weight change. The two former serif display levels become the Onest bold
grotesque, matching the reference shots.

| Token | Before | After |
| --- | --- | --- |
| `display` | `.system(42, .semibold, .serif)` | `Onest-Bold 42` |
| `title` | `.system(30, .semibold, .serif)` | `Onest-Bold 30` |
| `title2` | `.system(24, .semibold, .serif)` | `Onest-Bold 24` |
| `headline` | `.system(18, .semibold)` | `Onest-Bold 18` |
| `body` | `.system(16, .regular)` | `Onest-Regular 16` |
| `callout` | `.system(14, .regular)` | `Onest-Regular 14` |
| `caption` | `.system(12, .semibold)` | `Onest-Medium 12` |
| `caption2` | `.system(10, .semibold)` | `Onest-Medium 10` |

A helper `BeautyFont.sized(_ size:_ weight:)` was added and **44** one-off
`.system(size:weight:[design:])` call sites across the feature views were
rewritten to it (weight → nearest Onest face: bold/semibold→Bold, medium→Medium,
else→Regular), so ad-hoc text is also on-brand. `.weight()`/`.bold()` overrides
at call sites resolve within the Onest typographic family.

**Prices / labels:** prices already render bold via Onest (`caption.weight(.bold)`),
and tracked uppercase category labels keep their `.textCase(.uppercase)` +
`.tracking(...)`. A struck-through *old* price (the `3 990 ₽` style on the
CHICNIE shot) is a **discount-data** feature — there is no old/compare-at price
field in the model (`Product.priceValue: Int` only), so it was not fabricated.
It is a one-line `.strikethrough(color: .gray)` away once the backend exposes an
old price; noted here as ready-to-wire rather than inventing fake discounts.

## 4. User-facing name → «Золотое Яблоко»

All visible `Luma` / `Luma Beauty ID` mentions renamed (25 strings across 11
files), with Russian grammar handled (genitive «Золотого Яблока», neuter
past-tense verbs «сохранило» / «собирало» / «добавило»):

- `App/AppEnvironment.swift` — `appName`
- `App/AppState.swift` — dev account name, checkout message
- `App/RootView.swift` — splash wordmark
- `Features/Settings/SettingsView.swift` — safety blurb
- `Features/Advisor/AdvisorView.swift` — advisor copy
- `Features/Auth/AuthView.swift` — welcome title + default name
- `Features/Shared/HomeView.swift` — nav title + 6 body strings
- `Features/Scan/FaceGateView.swift`, `Features/Scan/PhotoScanView.swift` — camera/photo copy
- `Features/BeautyID/BeautyIDSetupView.swift` — setup copy
- `Features/Profile/ProfileView.swift` — default name
- `Models/BeautyModels.swift` — routine/selection copy

`Info.plist` `CFBundleDisplayName` was already «Золотое Яблоко». **Not touched:**
bundle id (`com.dimalitin.lumabeautyid.*`), target/scheme/product names, Swift
file/type names, the internal `[Luma]` debug log tag in `Observability.swift`,
AppIcon, launch screen, README.

## 5. Verification

- Backend: `cd backend && python3 -m pytest -q` → 61 passed.
- iOS: `xcodebuild test -scheme BeautyConcierge` → 38 tests passed.
- iOS: `xcodebuild build` → BUILD SUCCEEDED; Onest TTFs embedded and listed in
  `UIAppFonts`; `CFBundleDisplayName = Золотое Яблоко`.
- Screenshots: `docs/assets/zol-rebrand-2026-05-29/` (rebranded build,
  iPhone 17 Pro, light + dark): `01_welcome`, `02_home`, `03_advisor`,
  `04_cart`, `05_profile` (each `_light`/`_dark`), plus
  `06_beautyid_reveal_light` (Onest display type on the «Естественная
  гармония» Beauty-ID result). They show the lime accent, the Onest
  wordmark/headings and the «Золотое Яблоко» nav title in place.

## 6. Out of scope (unchanged, by design)

AppState/stores/providers, advisor/scan/Beauty-ID logic, bundle id, AppIcon,
launch screen, navigation structure, screen layouts.
