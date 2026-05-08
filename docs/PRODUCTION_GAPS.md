# Production Gaps

Remaining before real TestFlight/App Store:

1. Connect production auth provider.
2. Connect production retail catalog provider and licensed product image CDN.
3. Connect production checkout provider or intentionally disable checkout.
4. Connect production scan/photo provider with retention and deletion behavior.
5. Configure real OpenRouter key/model in backend secret manager.
6. Review prompt/model behavior with legal/privacy/safety stakeholders.
7. Replace generated generic visuals with final licensed assets.
8. Connect analytics/crash SDKs after privacy review.
9. Run full Xcode build/test on macOS.
10. Run simulator and physical-device QA.
11. Complete accessibility QA.
12. Prepare public privacy/support/account deletion URLs.
13. Verify `/ready` reports no production blockers.

The project must not be described as App Store-ready until these are complete.
