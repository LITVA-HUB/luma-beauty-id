# API Contracts

Base path: `/v1`. Protected endpoints require `Authorization: Bearer <access_token>`.

Errors:

```json
{
  "error": {
    "code": "machine_code",
    "message": "Human safe message.",
    "request_id": "uuid",
    "details": {}
  }
}
```

Authorization headers, tokens, provider keys, raw photos and emails must not be logged.

## Health/readiness

- `GET /health` returns non-secret mode data and storage stats.
- `GET /ready` returns `ready` or `not_ready` plus missing provider/config blockers.

## Auth

- `POST /auth/register` → `AuthSessionResponse`
- `POST /auth/login` → `AuthSessionResponse`
- `POST /auth/dev-login` → development/staging only; disabled in production
- `POST /auth/refresh` → rotates access and refresh tokens
- `POST /auth/logout` → revokes access token and optional refresh token
- `GET /auth/me` → current account

`AuthSessionResponse` includes access token, refresh token, expiry timestamps, public account, dev mode flag and provider name.

## Beauty ID

- `GET /beauty-id`
- `PUT /beauty-id`

Beauty ID stores cosmetic preferences only. It is not a medical profile.

## Catalog

- `GET /catalog/products?q=&category=&domain=&include_unavailable=`
- `GET /catalog/products/{sku}`

Product DTO fields include: `sku`, `brand`, `name`, `category`, `domain`, `price_segment`, `price_value`, `currency`, `image_url`, `gallery`, `availability`, `inventory_status`, `ingredients`, `ingredient_highlights`, `warnings`, `source`, `updated_at`.

Production catalog requires an external provider. Local seed catalog is development/staging only.

## Recommendations

- `POST /recommendations`

Recommendations are filtered to known, available catalog SKUs. No unknown SKU may be returned.

## Photo / scan

- `POST /photo/scan` multipart fields: `source`, optional `beauty_id_json`, optional `photo`.
- `DELETE /photo/scan/{scan_id}` accepts a deletion request.

The backend validates file size, MIME type and basic JPEG/PNG signatures. Raw photos are not stored by default. Production scan requires an external provider contract with retention/deletion behavior.

## Advisor

- `POST /advisor/message`
- `GET /advisor/history`
- `DELETE /advisor/history`

Request:

```json
{
  "message": "Need SPF and glow",
  "beauty_id": {},
  "current_skus": ["SKU"]
}
```

Response includes:

```json
{
  "answer": "short concierge answer",
  "quick_actions": ["SPF", "без отдушек"],
  "recommendations": [],
  "recommended_skus": [],
  "routine_steps": [],
  "why_this_works": "catalog-grounded explanation",
  "safety_note": null,
  "fallback_reason": null,
  "prompt_version": "luma-advisor-2026-05-rc2",
  "provider": "openrouter"
}
```

OpenRouter is called only by backend. The backend sends minimized context: user message, Beauty ID summary and an allowed catalog subset. It never sends raw photos, base64 image data, tokens, emails or secrets.

The OpenRouter adapter tries the configured JSON response mode first, then compatible JSON fallback modes (`json_schema`, `json_object`, then prompt-only JSON) before falling back to deterministic advice. The backend validates returned SKUs against the allowed catalog subset and removes/blocks unknown products.

Medical diagnosis/treatment requests return `safety_note=medical_boundary` without calling OpenRouter. Transient OpenRouter failures return a deterministic catalog-grounded fallback with `provider=openrouter_fallback:deterministic` and a `fallback_reason`. Auth/config failures are reported separately and must not be treated as a successful live provider check.

Advisor conversation history is stored per authenticated account as typed user/assistant messages. The backend stores only sanitized text, timestamps, provider metadata and catalog-grounded `recommended_skus`; it does not store raw OpenRouter payloads, secrets, tokens, emails, raw photos or base64 image data.

History response:

```json
{
  "messages": [
    {
      "id": "msg_uuid",
      "role": "assistant",
      "content": "short concierge answer",
      "recommended_skus": ["LUMA-001"],
      "created_at": "2026-05-07T10:00:00Z",
      "provider": "openrouter",
      "prompt_version": "luma-advisor-2026-05-rc2",
      "safety_note": null,
      "fallback_reason": null
    }
  ]
}
```

## Cart / checkout

- `GET /cart`
- `POST /cart/items`
- `PATCH /cart/items/{sku}`
- `DELETE /cart/items/{sku}`
- `DELETE /cart`
- `POST /checkout/handoff`

Production checkout requires a configured external checkout provider. Without it, checkout is unavailable rather than faked.

Cart is backend-authoritative and scoped to the authenticated account. Items use primary LUMA SKUs only (`LUMA-001`...`LUMA-094`); source SKUs printed on generated cards are never accepted as cart primary keys. iOS should call `GET /cart` after login, token refresh/session restore and when opening the cart tab.

## Session restore

On app launch iOS restores tokens from Keychain, calls `/auth/refresh` if the access token is stale, then loads `/profile/me`, `/beauty-id` through profile data, `/cart`, `/advisor/history` and `/recommendations`. If refresh fails, local auth state is cleared and the user is returned to login without keeping a half-authenticated state.

## Privacy

- `POST /privacy/export`
- `POST /privacy/delete-request`

Production integrations must connect identity/order/catalog erasure workflows before release.
