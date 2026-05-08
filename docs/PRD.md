# Product Requirements

## Audience

Beauty retail users who want a premium, low-friction way to build skincare/makeup routines without random catalog browsing or medical-sounding analysis.

## Core value

Beauty ID + optional photo/questionnaire + catalog-grounded advisor produces explainable product matches, routine steps and cart-ready selections.

## Release-candidate journey

Launch → onboarding → auth → Beauty ID → optional scan/questionnaire → advisor → recommendations → product detail → cart → checkout handoff/unavailable state → profile/settings/privacy.

## Included foundation

Native iPhone SwiftUI app, FastAPI backend, provider-based auth/catalog/scan/advisor/checkout contracts, development/staging seed catalog, product-aware concierge UI, cart, profile, privacy/safety copy and release-readiness docs.

## Out of scope until external integrations

Real retail inventory, real checkout/order lifecycle, production identity provider, approved scan provider, approved LLM provider, production analytics/crash SDKs and final licensed product photography.

## Privacy/safety

Photo is optional; no early permission request; backend does not persist raw photos by default; Beauty ID is a cosmetic preference profile only; advisor refuses diagnosis/treatment prompts.

## Success metrics

Onboarding completion, Beauty ID completion, scan/questionnaire completion, recommendation detail opens, add-to-cart, saved routine, advisor refine usage, checkout starts/unavailable rate and privacy control usage.
