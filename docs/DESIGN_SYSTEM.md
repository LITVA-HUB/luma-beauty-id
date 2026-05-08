# Design System

## Tokens

- Background: `ivory #FAF4EA`, `milk #FFFBF2`, card `#FFFFFF`.
- Text: `ink #131210`, secondary `taupe #7C6D5B`, quiet `warmGray #A39985`.
- Accent: `lime #D5F42D`, soft lime `#E8F891`.
- CTA support: restrained orange `#EA6321`.
- Secondary tones: blush, champagne and beige line colors.
- Radius: 12, 18, 26, 34.
- Spacing: 6, 10, 16, 24, 32, 44.
- Typography: serif display/title, system body/headline/caption with Dynamic Type-friendly sizing.

## Components

Implemented: `PrimaryButton`, `SecondaryButton`, `BeautyChip`, `SectionHeader`, `MatchBadge`, `RoutineStepPill`, `LoadingStateView`, `EmptyStateView`, `ErrorBanner`, `ProductCard`, `ProductMiniRow`, `ProductVisual`, `HorizontalProductRail`, `CachedRemoteImage` fallback states.

## States

- Loading: calm copy, no fake AI loader.
- Empty: soft illustration and one clear next action.
- Error: retryable, human-readable, no stack traces.
- Unavailable product: visible badge, disabled add-to-cart.
- Local seed data: marked as development/staging data when shown.

## Accessibility rules

- Minimum tap target around 44pt.
- VoiceOver labels on key cards/buttons.
- Native navigation/sheets.
- Reduced motion compatible transitions.
- Contrast review required for lime/orange accents before release.

## Screens

Launch, Onboarding, Auth, Beauty ID setup, Scan/Questionnaire, Advisor, Recommendations, Product Detail, Cart, Profile, Settings.
