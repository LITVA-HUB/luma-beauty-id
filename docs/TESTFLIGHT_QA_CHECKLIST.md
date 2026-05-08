# TestFlight QA Checklist

Run this before inviting beta testers.

## Build Configuration

- Release/TestFlight has a real HTTPS staging API URL.
- Release/TestFlight does not use localhost, loopback, placeholder domains, empty URL, or HTTP.
- Development sign-in is hidden in Release/TestFlight.
- Settings in Release/TestFlight do not show developer base URL details.
- App shows "Сервис временно недоступен. Staging API URL не настроен." if staging URL is missing.

## Auth And Persistence

- Register a new account.
- Complete Beauty ID.
- Restart the app and confirm session restore.
- Confirm Beauty ID is still present.
- Add products to cart, restart, and confirm cart persists.
- Ask advisor a question, restart, and confirm chat history persists.
- Save a routine/selection, logout, login again, and confirm it loads from backend.

## Advisor Safety

- User bubble shows only what was typed.
- Assistant bubble shows only final user-facing answer.
- No internal prompt text appears.
- No provider, fallback, raw JSON, endpoint, or stacktrace appears in UI.
- Medical diagnosis/treatment request gets a safe refusal.
- Recommended SKUs are valid LUMA primary SKU only.

## Cart And Saved Selection

- Add, update, and remove cart items.
- Badge count and total update correctly.
- Primary action says "Сохранить подборку".
- Success copy says order/payment are not created in beta.

## Feedback

- Open Settings/Profile.
- Tap "Оставить отзыв".
- Submit rating 1-5 with text.
- Confirm success state.
- Try invalid empty text or missing rating if UI allows it; no raw technical error should appear.

## Visual Smoke

- Light, dark, and system themes are readable.
- Product images load in Home, Advisor, Recommendations, Product Detail, and Cart.
- Beauty ID flow hero and question cards fit on small and normal iPhone sizes.
- Buttons remain accessible above the keyboard.

## Privacy

- Camera and photo permission prompts are in Russian.
- Scan copy says cosmetic context, not medical diagnosis.
- Logout clears local state but does not delete backend account data.
