# Luma Beauty ID - AI agent and backend architecture

Документ описывает, как в текущем проекте устроены AI-советник, backend, данные, контекст и интеграция с iOS. Это technical audit / documentation pass по состоянию кодовой базы на момент проверки. Секреты, токены, пароли и реальные значения `.env` здесь не приводятся.

## 1. Общая архитектура

Верхнеуровневый поток выглядит так:

```text
iOS app
  -> AppState
  -> APIClient
  -> FastAPI backend
  -> Store: PostgreSQL на staging или SQLite/local dev
  -> Catalog: local seed JSON + static assets
  -> Advisor provider: OpenRouter или deterministic fallback
```

Что где живет:

- iOS содержит UI, локальное состояние экрана, Keychain-сессию, текущую активную подборку в `AppState`, cart view state, camera / scan flow и запросы к API.
- Backend содержит auth/session, Beauty ID, catalog contract, recommendations, advisor orchestration, cart, saved routine, feedback, privacy export/delete request и static assets.
- PostgreSQL используется на staging через `docker-compose.staging.yml`; локально backend может работать через SQLite, если `DATABASE_URL` не задан.
- Каталог товаров сейчас лежит в `backend/app/data/catalog.json`. Это synthetic/test catalog, не live retail catalog.
- Картинки товаров лежат в `backend/app/static/assets/cards/` и отдаются FastAPI как `/assets/cards/...`.
- OpenRouter используется только backend-side в `backend/app/advisor.py`. В iOS нет и не должно быть OpenRouter ключа, потому что mobile app нельзя считать секретным окружением: любой ключ в приложении можно извлечь из binary/runtime.

Основные файлы:

- iOS API layer: `ios/BeautyConcierge/Services/APIClient.swift`
- iOS environment config: `ios/BeautyConcierge/App/AppEnvironment.swift`, `ios/BeautyConcierge/Info.plist`, `ios/BeautyConcierge.xcodeproj/project.pbxproj`
- iOS source of truth: `ios/BeautyConcierge/App/AppState.swift`
- iOS models: `ios/BeautyConcierge/Models/BeautyModels.swift`
- iOS Advisor UI: `ios/BeautyConcierge/Features/Advisor/AdvisorView.swift`
- iOS Recommendations UI: `ios/BeautyConcierge/Features/Recommendations/RecommendationsView.swift`
- iOS Cart/Profile/Home: `ios/BeautyConcierge/Features/Cart/CartView.swift`, `ios/BeautyConcierge/Features/Profile/ProfileView.swift`, `ios/BeautyConcierge/Features/Shared/HomeView.swift`
- Backend app/routes: `backend/app/main.py`
- Backend schemas: `backend/app/schemas.py`
- Backend store: `backend/app/store.py`
- Backend catalog: `backend/app/catalog.py`
- Backend recommendations: `backend/app/recommendations.py`
- Backend advisor/provider integration: `backend/app/advisor.py`
- Backend config/env: `backend/app/config.py`
- Backend scan/photo contract: `backend/app/scan.py`
- Backend auth provider contract: `backend/app/auth_provider.py`
- Backend checkout contract: `backend/app/checkout.py`

Staging backend expected public URL:

```text
https://api-staging.lumatestdomen.online
```

The iOS project currently injects:

```text
API_BASE_URL=https://api-staging.lumatestdomen.online
APP_ENVIRONMENT=staging
```

## 2. AI Advisor: как работает агент

### Endpoint

iOS отправляет сообщение советнику в:

```text
POST /v1/advisor/message
Auth: required, Bearer access token
Backend route: backend/app/main.py
iOS caller: AppState.sendAdvisorMessage(...)
```

### Request payload от iOS

Swift-модель `AdvisorRequest` в `BeautyModels.swift`:

```text
message: String
beautyId: BeautyID?
currentSkus: [String]
currentSelection: [AdvisorSelectionProduct]
currentCart: [AdvisorSelectionProduct]
```

Backend-модель `AdvisorRequest` в `schemas.py`:

```text
message: str
beauty_id: BeautyID | None
current_skus: list[str]
current_selection: list[AdvisorSelectionProduct]
current_cart: list[AdvisorSelectionProduct]
conversation_history: list[AdvisorHistoryMessage] = excluded from external payload
```

`conversation_history` не приходит напрямую от iOS. Backend сам загружает историю из store и inject-ит ее в `AdvisorRequest` перед вызовом `build_advisor_response`.

### Что backend добавляет к запросу

В `backend/app/main.py` endpoint делает:

1. Берет `beauty_id` из payload или загружает сохраненный Beauty ID из store.
2. Чистит user message через `clean_display_message`, чтобы убрать случайно попавший internal prompt-like текст.
3. Загружает последние advisor messages: `store.list_advisor_messages(account.account_id, limit=24)`.
4. Передает в `build_advisor_response(...)` message, Beauty ID, current selection/cart/current SKUs и recent history.
5. После ответа дополнительно фильтрует recommendations по known available catalog SKUs.
6. Сохраняет user message и assistant answer в `advisor_messages`.
7. Сохраняет summary event в generic `histories` kind `advisor_history`.

### Где формируется prompt

Prompt формируется в `backend/app/advisor.py`.

Главная константа:

```text
SYSTEM_PROMPT
```

В ней заданы:

- роль: premium beauty retail concierge;
- тон: кратко, тепло, уверенно, product-aware;
- язык: отвечать на языке пользователя, для русского - компактный русский;
- safety boundary: не диагноз, не лечение, не медицинские заявления;
- catalog grounding: рекомендовать только SKU из `allowed_products`;
- запрет выдумывать продукты, бренды, цены, reviews, claims;
- уважать Beauty ID, бюджет, sensitivity, fragrance preference, exclusions;
- трактовать `current_selection` и `current_cart` как living routine;
- не рекомендовать уже добавленный SKU повторно без объяснения;
- replacement должен быть explicit, а не молчаливый;
- возвращать только JSON object по заданной форме.

Для OpenRouter backend строит payload в `OpenRouterAdvisorProvider._request_payload(...)`:

```text
messages:
  - system: SYSTEM_PROMPT
  - user: JSON-serialized user_context
temperature: 0.22
max_tokens: 650
response_format: json_schema / json_object / none fallback ladder
```

### Response format

Ожидается структурированный JSON:

```json
{
  "message": "short answer",
  "quick_actions": ["short chip"],
  "recommended_skus": ["LUMA-001"],
  "routine_steps": ["очищение", "SPF"],
  "why_this_works": "short explanation",
  "safety_note": null
}
```

JSON schema описана в `ADVISOR_JSON_SCHEMA` в `advisor.py`. Backend просит OpenRouter JSON-schema structured output, если provider/model поддерживает это. Если OpenRouter отвергает формат, backend пробует `json_object`, затем режим без provider-enforced response format, но все равно требует JSON.

### Валидация ответа

Backend защищает output несколькими слоями:

- `_parse_llm_json(...)` парсит JSON и валидирует через `LLMAdvisorPayload`.
- `_recommendations_from_skus(...)` превращает `recommended_skus` в реальные `RecommendationProduct` только из `allowed_products`.
- Если модель вернула SKU, но ни один не совпал с `allowed_products`, выбрасывается `advisor_provider_ungrounded_skus`, затем возможен deterministic fallback.
- `contains_internal_prompt_marker(...)` блокирует ответы, похожие на утечку internal prompt.
- `main.py` после provider response еще раз фильтрует `response.recommendations` по available catalog SKUs из `load_catalog(include_unavailable=False)`.

Итог: агент не должен и практически не может вернуть карточку выдуманного товара в UI, потому что UI получает только продукты, найденные backend в каталоге.

### Fallback, если OpenRouter не отвечает

Если `ADVISOR_PROVIDER=openrouter`, но:

- нет ключа или модели;
- timeout/network error;
- OpenRouter вернул invalid JSON;
- schema не совпала;
- SKU не grounded;
- формат request отклонен;

то `build_advisor_response(...)` в non-production/staging может вернуть deterministic fallback:

```text
provider = "openrouter_fallback:deterministic"
fallback_reason = конкретный код ошибки
safety_note = "advisor_provider_fallback", если применимо
```

В production fallback зависит от `fallback_allowed`. Auth failures и некоторые конфигурационные ошибки не должны тихо скрываться.

### Medical safety

В `advisor.py` есть `MEDICAL_TOKENS` и `is_medical_intent(...)`. Если user message похож на диагностику/лечение, backend возвращает `_medical_refusal(...)` без рекомендаций товаров:

```text
safety_note = "medical_boundary"
recommendations = []
recommended_skus = []
```

Prompt также запрещает диагнозы, treatment plans, medical claims и fake certainty.

### Что агент видит

Текущее состояние:

- Видит user message.
- Видит последние сообщения истории, но только последние 8 в OpenRouter payload.
- Видит Beauty ID summary, но не полный account object.
- Видит current selection из iOS.
- Видит current cart из iOS.
- Видит `current_skus`.
- Видит только subset каталога `allowed_products`, а не весь каталог.
- Видит текущие товары пользователя, если iOS передала их через `advisorContext()`.
- Не видит email/name пользователя в OpenRouter payload.
- Не видит access/refresh tokens.
- Не видит фото, raw image bytes или base64.
- Не видит весь PostgreSQL или всю историю аккаунта.

Важно: deterministic fallback не использует OpenRouter и не "видит" внешний provider, но использует Beauty ID и catalog scoring локально на backend.

## 3. Что именно уходит в AI provider

В OpenRouter user message отправляется JSON `user_context`:

```text
user_message
recent_history
beauty_id_summary
current_selection
current_cart
current_skus
allowed_products
response_language_hint
prompt_version
```

### User message

Отправляется очищенный `message`, максимум 1200 символов на backend schema. Если текст похож на internal prompt leakage, backend пытается извлечь реальное "Новое сообщение пользователя" или обрезает sanitized текст.

### Previous messages

Backend грузит до 24 сообщений из store, но в OpenRouter payload включает только последние 8:

```python
request.conversation_history[-8:]
```

Перед отправкой отбрасываются сообщения, похожие на internal prompt markers.

### Beauty ID/profile

В AI provider уходит не весь profile/account, а сжатый Beauty ID:

```text
skin_type
concerns up to 6
sensitivity
fragrance_sensitivity
preferred_finish up to 4
makeup_preferences up to 6
budget
ingredient_exclusions up to 10
routine_complexity
style_tags up to 6
```

Email/name/account_id не отправляются в OpenRouter.

### Products

AI видит `allowed_products`, сформированные в `_catalog_subset(...)`:

1. Backend вызывает deterministic recommendations по Beauty ID + current message с limit 12.
2. Убирает продукты, нарушающие ingredient exclusions.
3. Добавляет до 8 SKU из `current_skus`, если они есть в каталоге, доступны и еще не попали в subset.
4. Возвращает максимум 16 продуктов.

Поля продукта в AI context:

```text
sku
brand
name
category
domain
price_value
currency
availability
inventory_status
tags up to 10
ingredients up to 12
warnings up to 8
routine_step
match_reason
```

### Current selection/cart/routine

В OpenRouter payload уходит:

- `current_selection`: до 20 продуктов из активной подборки iOS.
- `current_cart`: до 20 продуктов из cart.
- `current_skus`: до 30 SKU, составленных из active selection + cart + savedRoutineSkus.

Поля current product:

```text
sku
brand
name
category
product_type
price_value
currency
routine_step
```

Saved routine как отдельный объект не отправляется; она участвует через `current_skus` на iOS side. Если SKU saved routine нет в active recommendations/cart, provider получает SKU, но не получает полную карточку saved routine как `current_selection`.

### Что не отправляется

- Реальные значения API keys/tokens.
- Access token и refresh token.
- Email/name/account_id.
- Raw photos, base64 photo, image bytes.
- Полный каталог.
- Полная история всех событий.
- Cart quantities как отдельное поле. В `current_cart` есть продукты, но quantity не передается в AdvisorSelectionProduct.

Фото с Beauty Scan не отправляются в OpenRouter. Backend `/v1/photo/scan` может получить фото как multipart upload, но dev provider не сохраняет raw photo и не передает его AI advisor. Scan response явно говорит, что raw photos are not persisted by default unless storage is configured.

## 4. Catalog / Product grounding

Каталог сейчас:

```text
backend/app/data/catalog.json
```

В audit catalog содержит 94 товара. Это synthetic catalog. Каждый товар имеет LUMA SKU формата:

```text
LUMA-001 ... LUMA-094
```

`source_sku` - исходный/референсный SKU вроде `FD-BUD-01`. Он не является public lookup key для API. Тесты прямо проверяют, что `/v1/catalog/products/FD-BUD-01` возвращает 404, а `/v1/catalog/products/LUMA-001` работает.

Основные поля товара:

```text
sku
source_sku
catalog_number
brand
name
variant
display_name
category
domain
price_segment
price_value
currency
image_url
gallery
availability
inventory_status
skin_types
concerns
tags
ingredients
ingredient_highlights
warnings
exclusions
finishes
coverage_levels
color_families
texture
rating
review_count
source
asset_source
card_image_url
product_type
category_group
updated_at
```

Images:

- Product JSON содержит `image_url` и `card_image_url`, например `/assets/cards/001_FD-BUD-01.png`.
- Static files живут в `backend/app/static/assets/cards/`.
- FastAPI монтирует `StaticFiles` на `/assets`.
- iOS строит absolute URL через `AppState.absoluteURL(for:)`, если path относительный.
- Product views используют `preferredImagePath`, где `imageUrl ?? cardImageUrl`.

Backend endpoints:

```text
GET /v1/catalog/products
GET /v1/catalog/products/{sku}
```

`GET /v1/catalog/products` поддерживает `q`, `category`, `domain`, `include_unavailable`.

Advisor grounding:

- Агенту запрещено придумывать товары в prompt.
- Агент видит только `allowed_products`.
- Агент возвращает только `recommended_skus`.
- Backend мапит эти SKU обратно к `allowed_products`.
- Unknown SKU не превращается в product card.
- Если OpenRouter вернул только unknown SKU, включается fallback с `fallback_reason=advisor_provider_ungrounded_skus`.
- После provider response `main.py` еще раз фильтрует recommendations по available catalog.

## 5. Beauty ID / Profile

Beauty ID model описан в `backend/app/schemas.py` и `ios/BeautyConcierge/Models/BeautyModels.swift`.

Поля:

```text
skin_type
concerns
sensitivity
fragrance_sensitivity
preferred_finish
makeup_preferences
budget
ingredient_exclusions
routine_complexity
style_tags
consent
updated_at
```

Где хранится:

- Backend table `beauty_ids`, keyed by `account_id`.
- Payload хранится JSON blob.
- iOS держит текущий `beautyID` в `AppState`.

Endpoints:

```text
GET /v1/beauty-id
PUT /v1/beauty-id
GET /v1/profile/me
```

`PUT /v1/beauty-id` требует `consent=true`; иначе возвращает `beauty_id_consent_required`.

При login/session restore iOS вызывает `loadProfileAndSessionData()`:

1. `GET /v1/profile/me`
2. apply Beauty ID
3. apply saved routine from profile
4. `GET /v1/cart`
5. `GET /v1/advisor/history`
6. `GET /v1/routines/current`
7. `POST /v1/recommendations`

Как Beauty ID влияет:

- `recommendations.py` использует Beauty ID для scoring: skin type, concerns, finish, style tags, budget, fragrance sensitivity, ingredient exclusions, routine complexity.
- Advisor OpenRouter получает summarized Beauty ID.
- Deterministic fallback вызывает `recommend_products(...)` с Beauty ID.
- Profile returns `completion` через `completion_for_beauty_id(...)` и tags через `tags_for_beauty_id(...)`.

Non-medical boundary:

- `BeautyIDResponse.privacy_note`: Beauty ID stores preferences for product matching. It is not a medical profile.
- `RecommendationsResponse.disclaimer`: подбор не диагностика и не медицинская рекомендация.
- `ScanResult.disclaimer`: Beauty Scan cosmetic preference helper, not diagnosis.
- Advisor prompt и medical refusal жестко отделяют косметический подбор от лечения.

## 6. Chat history / Advisor memory

История советника хранится backend-side:

```text
table: advisor_messages
columns: id, account_id, role, content, recommended_skus, provider, prompt_version, safety_note, fallback_reason, created_at
```

Endpoints:

```text
GET /v1/advisor/history
DELETE /v1/advisor/history
POST /v1/advisor/message
```

Поведение:

- После каждого `/v1/advisor/message` backend сохраняет user message и assistant answer.
- `GET /v1/advisor/history` возвращает все сообщения account scope с default limit 100 в store.
- В AI provider отправляется не вся история, а последние 8 сообщений из последних 24, загруженных endpoint-ом.
- History scoped by `account_id`; tests проверяют, что другой аккаунт видит пустую историю.
- Clear history удаляет rows из `advisor_messages` только для текущего account.
- iOS при boot загружает history и фильтрует internal-prompt-looking text на клиенте.

Ограничение: нет отдельной summary memory. История является линейным message log; provider получает короткое окно recent messages.

## 7. Cart / Active selection / Saved routine

### Cart

Backend table:

```text
carts(account_id PRIMARY KEY, payload JSON, updated_at)
```

Payload - JSON map `{sku: quantity}`. Backend возвращает `CartResponse` с product details, subtotal и checkout mode.

Endpoints:

```text
GET /v1/cart
POST /v1/cart/items
PATCH /v1/cart/items/{sku}
DELETE /v1/cart/items/{sku}
DELETE /v1/cart
```

iOS хранит текущий cart в `AppState.cart`; при boot вызывает `loadCart`.

### Active selection

Текущая активная подборка в iOS сейчас представлена через:

```text
AppState.recommendations
  - hero
  - routine
  - products
```

Это главный living selection на клиенте. Home, Advisor tray и Recommendations читают один и тот же `AppState.recommendations`, поэтому последние изменения советника видны на этих экранах.

### Merge/add behavior

После ответа советника iOS делает merge, а не silent replace:

```text
AppState.sendAdvisorMessage(...)
  -> response.recommendations
  -> AppState.mergedRecommendations(existing: recommendations, incoming: response.recommendations)
```

`mergedRecommendations`:

- сохраняет существующий порядок старых `products`;
- добавляет новые SKU в конец;
- если SKU уже есть, обновляет product metadata на incoming version;
- считает duplicates;
- аналогично обновляет/добавляет в `routine`;
- формирует notice: "Добавлено N товара..." или "N уже были в подборке".

Explicit replace есть отдельно:

```text
replaceCurrentSelection(with:)
replaceSelectionWithLastAdvisorRecommendations()
```

В Advisor UI есть action "Заменить", который вызывает explicit replace. Это лучше, чем прежний silent replace.

### Saved routine

Backend table:

```text
saved_routines(account_id PRIMARY KEY, payload JSON list of SKUs, updated_at)
```

Endpoints:

```text
GET /v1/routines/current
PUT /v1/routines/current
DELETE /v1/routines/current
```

`PUT /v1/routines/current` валидирует, что все SKU есть в current LUMA catalog. Unknown SKU и old/source SKU отклоняются.

iOS:

- `saveCurrentRoutine()` сохраняет `recommendations.routine.map(\.sku)`.
- `applySavedRoutine(...)` сохраняет `savedRoutineSkus` в `UserDefaults`.
- `checkout()` в beta не делает real checkout; он сохраняет SKU cart как routine с сообщением о beta.

### Что агент знает

Advisor знает active selection/cart, если iOS передает актуальный `advisorContext()`.

`advisorContext()` собирает:

- unique products from `recommendations.routine + recommendations.products`;
- cart products from `cart.items`;
- current SKUs from active selection + cart + savedRoutineSkus.

Ограничение: saved routine в OpenRouter попадает как SKU list, но не как полные product cards, если эти товары не присутствуют в active selection/cart.

Если пользователь просит "сделай дешевле":

- iOS отправляет message "Сделай подборку дешевле" вместе с current selection/cart context.
- Prompt просит не сносить existing selection, а добавлять или явно предлагать alternatives/replacements.
- Backend не имеет отдельной structured action `replace_product`; response пока только recommendations + text.
- UI может добавить cheaper alternatives в подборку или дать explicit "Заменить" для всей последней рекомендации. Fine-grained "заменить X на Y" как структурированное действие еще не реализовано.

## 8. Backend data layer

Backend выбирает store в `create_app_store()`:

- Если `DATABASE_URL` задан: `PostgresStore`.
- Иначе: `AppStore` на SQLite path `STORE_PATH` или `.data/luma_beauty.sqlite3`.

Таблицы одинаковой формы создаются через `CREATE TABLE IF NOT EXISTS` в `store.py`, отдельной migration system нет.

Основные сущности:

```text
accounts
  account_id TEXT PRIMARY KEY
  name TEXT
  email TEXT UNIQUE
  password_hash TEXT
  created_at TEXT

sessions
  session_id TEXT PRIMARY KEY
  access_token TEXT UNIQUE
  refresh_token TEXT UNIQUE
  account_id TEXT
  access_expires_at TEXT
  refresh_expires_at TEXT
  dev_mode INTEGER
  revoked_at TEXT

beauty_ids
  account_id TEXT PRIMARY KEY
  payload TEXT/JSON
  updated_at TEXT

carts
  account_id TEXT PRIMARY KEY
  payload TEXT/JSON
  updated_at TEXT

histories
  id TEXT PRIMARY KEY
  account_id TEXT
  kind TEXT
  payload TEXT/JSON
  created_at TEXT

advisor_messages
  id TEXT PRIMARY KEY
  account_id TEXT
  role TEXT
  content TEXT
  recommended_skus TEXT/JSON
  provider TEXT
  prompt_version TEXT
  safety_note TEXT
  fallback_reason TEXT
  created_at TEXT

saved_routines
  account_id TEXT PRIMARY KEY
  payload TEXT/JSON list of SKUs
  updated_at TEXT

feedback
  id TEXT PRIMARY KEY
  account_id TEXT
  rating INTEGER
  message TEXT
  context TEXT
  app_version TEXT
  build TEXT
  created_at TEXT

privacy_requests
  id TEXT PRIMARY KEY
  account_id TEXT
  kind TEXT
  status TEXT
  created_at TEXT
```

Account scoping:

- Most protected endpoints depend on `current_account`.
- `current_account` reads bearer token, resolves active non-expired session, then loads account by `account_id`.
- Store operations generally include `account_id` in WHERE/INSERT.

Risks/limitations:

- JSON blobs make schema evolution easy but limit queryability and constraints.
- No Alembic/migration framework; CREATE TABLE handles initial setup but not complex migrations.
- Some foreign keys are not enforced in SQL schema.
- Password auth is local provider; production identity provider adapter is contract-only.

## 9. Auth / Sessions

Auth endpoints:

```text
POST /v1/auth/register
POST /v1/auth/login
POST /v1/auth/dev-login
POST /v1/auth/refresh
POST /v1/auth/logout
GET /v1/auth/me
```

Current provider:

- Non-production default: `LocalDevAuthProvider`.
- Production/external path exists as contract but not implemented.
- `dev-login` works only if `ALLOW_DEV_AUTH=true` and environment is non-production.

iOS:

- Access token and refresh token are stored in Keychain via `KeychainStore`.
- `APIClient.accessToken` attaches `Authorization: Bearer ...`.
- On boot, if access token exists, iOS tries `GET /v1/profile/me`.
- If access expired, iOS uses refresh token via `/v1/auth/refresh`.
- Logout calls `/v1/auth/logout`, then clears local tokens and app state.

Staging currently uses local auth unless `.env` config changes provider. Do not expose or commit `.env`.

## 10. Feedback

Endpoint:

```text
POST /v1/feedback
Auth: required
Request: FeedbackRequest
Response: FeedbackResponse
```

Fields:

```text
rating: 1..5
message: 1..2000 chars
context: optional
app_version: optional
build: optional
```

iOS sends feedback from `AppState.submitFeedback(...)` with `appVersion` and `buildNumber` from bundle info.

Backend stores feedback in `feedback` table with `account_id`, rating, message, context, app version, build and created_at.

## 11. Config / ENV / Deploy

Backend config is in `backend/app/config.py`. It loads environment variables, including local `backend/.env` for local execution without printing values.

Important env variables:

```text
APP_ENV / APP_ENVIRONMENT
API_HOST
API_PORT
PUBLIC_API_BASE_URL / API_PUBLIC_BASE_URL
DATABASE_URL
STORE_PATH
CORS_ALLOW_ORIGINS

ALLOW_DEV_AUTH
AUTH_PROVIDER
AUTH_PROVIDER_URL
AUTH_PROVIDER_API_KEY
ACCESS_TOKEN_TTL_MINUTES
REFRESH_TOKEN_TTL_DAYS

CATALOG_PROVIDER
CATALOG_API_BASE_URL
CATALOG_API_TOKEN

CHECKOUT_PROVIDER
CHECKOUT_HANDOFF_URL
CHECKOUT_API_KEY

SCAN_PROVIDER
SCAN_PROVIDER_URL
SCAN_PROVIDER_API_KEY
MAX_PHOTO_BYTES
ALLOWED_PHOTO_MIME_TYPES

ADVISOR_PROVIDER
ADVISOR_PROMPT_VERSION
ADVISOR_TIMEOUT_SECONDS
OPENROUTER_API_KEY
OPENROUTER_BASE_URL
OPENROUTER_MODEL
OPENROUTER_TIMEOUT_SECONDS
OPENROUTER_MAX_RETRIES
OPENROUTER_RESPONSE_FORMAT
GEMINI_API_KEY

LOG_LEVEL
```

Variables that must not be committed:

- `OPENROUTER_API_KEY`
- `DATABASE_URL` if it includes credentials
- `POSTGRES_PASSWORD`
- provider API keys/tokens
- auth provider credentials
- checkout credentials
- scan provider credentials
- `.env` files

Staging deploy:

- `docker-compose.staging.yml` defines `postgres` and `backend`.
- `postgres` uses named Docker volume `postgres_data`.
- `backend` receives `DATABASE_URL` pointing at `postgres`.
- `nginx/certbot` live outside this repo setup, but public URL is `https://api-staging.lumatestdomen.online`.

Useful checks:

```bash
curl https://api-staging.lumatestdomen.online/health
curl https://api-staging.lumatestdomen.online/ready
curl -I https://api-staging.lumatestdomen.online/assets/cards/001_FD-BUD-01.png
```

Scripts:

- `scripts/rc_checks.py`: checks Swift files in pbxproj, shared scheme, iOS OpenRouter refs and obvious secret patterns.
- `scripts/deploy_check.sh`: checks health, ready, catalog and sample asset.
- `scripts/backup_postgres.sh`: dumps staging Postgres via docker compose to `backups/`.
- `scripts/update_staging_server.sh`: rsync deploy with excludes for `.env`, `.git`, data, backups, caches; then backup + docker compose rebuild + health checks.
- `scripts/smoke_openrouter.py`: live OpenRouter smoke test when key is available in backend environment only.

## 12. API endpoints

### Health / environment

```text
GET /health
Auth: no
Response: dict with status, version, public settings, storage stats, settings_errors, production_ready
Backend: main.py
iOS: mostly diagnostics/settings
```

```text
GET /ready
Auth: no
Response: status, catalog_items, time, errors
Backend: main.py
Use: deploy readiness
```

```text
GET /v1/environment
Auth: no
Response: EnvironmentResponse
Backend: main.py
Use: environment diagnostics
```

### Auth

```text
POST /v1/auth/register
Auth: no
Request: AuthRegisterRequest
Response: AuthSessionResponse
Backend: main.py, auth_provider.py, store.py
iOS: AppState.register
```

```text
POST /v1/auth/login
Auth: no
Request: AuthLoginRequest
Response: AuthSessionResponse
iOS: AppState.login
```

```text
POST /v1/auth/dev-login
Auth: no, non-production only
Request: empty
Response: AuthSessionResponse
iOS: AppState.continueInDevelopmentMode
```

```text
POST /v1/auth/refresh
Auth: no, refresh token in body
Request: TokenRefreshRequest
Response: AuthSessionResponse
iOS: AppState.boot -> refreshSession
```

```text
POST /v1/auth/logout
Auth: required
Request: LogoutRequest optional
Response: {"ok": true}
iOS: AppState.logout
```

```text
GET /v1/auth/me
Auth: required
Response: public account
```

### Profile / Beauty ID

```text
GET /v1/profile/me
Auth: required
Response: ProfileResponse
iOS: AppState.loadProfileAndSessionData, ProfileView
```

```text
GET /v1/beauty-id
Auth: required
Response: BeautyIDResponse
```

```text
PUT /v1/beauty-id
Auth: required
Request: BeautyID
Response: BeautyIDResponse
iOS: AppState.saveBeautyID
```

### Catalog

```text
GET /v1/catalog/products
Auth: no
Query: q, category, domain, include_unavailable
Response: [Product]
Backend: main.py -> catalog.py
```

```text
GET /v1/catalog/products/{sku}
Auth: no
Response: Product
Important: SKU is LUMA SKU, not source_sku
```

### Recommendations / Scan

```text
POST /v1/recommendations
Auth: required
Request: RecommendationsRequest
Response: RecommendationsResponse
Backend: recommendations.py
iOS: AppState.loadRecommendations
```

```text
POST /v1/photo/scan
Auth: required
Request: multipart form: source, beauty_id_json optional, photo optional
Response: ScanResult
Backend: scan.py
iOS: APIClient.uploadPhotoScan, AppState.performScan
```

```text
DELETE /v1/photo/scan/{scan_id}
Auth: required
Response: PrivacyRequestResponse
```

### Advisor

```text
POST /v1/advisor/message
Auth: required
Request: AdvisorRequest
Response: AdvisorResponse
Backend: main.py -> advisor.py -> OpenRouter/deterministic
iOS: AppState.sendAdvisorMessage
```

```text
GET /v1/advisor/history
Auth: required
Response: AdvisorHistoryResponse
iOS: AppState.loadAdvisorHistory
```

```text
DELETE /v1/advisor/history
Auth: required
Response: AdvisorHistoryResponse
iOS: AppState.clearAdvisorHistory
```

### Cart / routine / checkout

```text
GET /v1/cart
Auth: required
Response: CartResponse
iOS: AppState.loadCart
```

```text
POST /v1/cart/items
Auth: required
Request: AddCartItemRequest
Response: CartResponse
iOS: AppState.addToCart
```

```text
PATCH /v1/cart/items/{sku}
Auth: required
Request: UpdateCartItemRequest
Response: CartResponse
iOS: AppState.updateCartItem
```

```text
DELETE /v1/cart/items/{sku}
Auth: required
Response: CartResponse
```

```text
DELETE /v1/cart
Auth: required
Response: CartResponse
```

```text
GET /v1/routines/current
Auth: required
Response: SavedRoutineResponse
iOS: AppState.loadSavedRoutine
```

```text
PUT /v1/routines/current
Auth: required
Request: SavedRoutineRequest
Response: SavedRoutineResponse
iOS: AppState.saveCurrentRoutine / checkout beta save
```

```text
DELETE /v1/routines/current
Auth: required
Response: SavedRoutineResponse
```

```text
POST /v1/checkout/handoff
Auth: required
Response: CheckoutResponse
Backend: checkout.py
Note: current iOS checkout path saves routine in beta rather than doing real checkout handoff.
```

### Feedback / privacy

```text
POST /v1/feedback
Auth: required
Request: FeedbackRequest
Response: FeedbackResponse
iOS: AppState.submitFeedback
```

```text
POST /v1/privacy/export
Auth: required
Response: ExportResponse
```

```text
POST /v1/privacy/delete-request
Auth: required
Response: PrivacyRequestResponse
iOS: AppState.requestPrivacyDeletion
```

### Static assets

```text
GET/HEAD /assets/cards/{filename}.png
Auth: no
Backend: FastAPI StaticFiles mounted in main.py
iOS: product image cards via CachedRemoteImage
```

## 13. iOS integration

### APIClient

`APIClient.swift` provides generic:

```text
get
post
put
patch
delete
uploadPhotoScan
```

It:

- uses JSON encoder/decoder with snake_case conversion;
- decodes ISO8601 dates;
- sends `X-Request-ID`;
- attaches bearer token when `accessToken` is set;
- maps backend errors to user-friendly Russian messages;
- has special multipart upload path for `/v1/photo/scan`.

### Base URL and environment

`AppEnvironment.current` reads:

```text
API_BASE_URL
APP_ENVIRONMENT
```

from Info.plist/build settings.

Debug fallback URL is `http://127.0.0.1:8010` if config is empty. Release builds validate that URL is non-empty, https, and not localhost/example/placeholder.

Current project build settings point to staging:

```text
https://api-staging.lumatestdomen.online
staging
```

### AppState

`AppState` is the main source of truth for iOS runtime state:

```text
account
beautyID
recommendations
cart
scanResult
advisorMessages
quickActions
advisorWhyThisWorks
advisorRoutineSteps
advisorSelectionNotice
savedProducts
savedRoutineSkus
appTheme
selectedTab
```

Screens using backend:

- Home reads Beauty ID, active routine/recommendations, advisor notice, cart count.
- Advisor sends messages, loads/clears history, saves routine, opens recommendations.
- Recommendations loads recommendation response, saves routine, sends refinement requests to advisor.
- Cart loads/adds/updates cart and beta-saves cart SKUs as routine.
- Profile reads account, Beauty ID, saved routine, privacy/settings actions.
- Scan/Beauty ID saves questionnaire and optionally uploads photo to `/v1/photo/scan`.

Restore after restart:

1. Read access token from Keychain.
2. Set `api.accessToken`.
3. `GET /v1/profile/me`.
4. If unauthorized/expired, try refresh token.
5. Load cart, advisor history, saved routine and recommendations.

Local cache:

- Keychain: access/refresh tokens.
- UserDefaults: onboarding, savedProducts, savedRoutineSkus, appTheme.
- `AppState.recommendations` lives in memory and is refreshed from backend recommendations on boot.

Backend source of truth:

- account/session;
- Beauty ID;
- cart;
- saved routine;
- advisor history;
- feedback;
- recommendation/advisor history events.

## 14. Safety / privacy / non-medical guarantees

Non-medical guarantees exist at several layers:

- UI copy says Beauty ID is preferences, not medical profile.
- `RecommendationsResponse.disclaimer` states non-medical recommendation.
- `ScanResult.disclaimer` states scan is cosmetic preference helper.
- Advisor prompt forbids diagnosis/treatment/medical claims.
- `is_medical_intent(...)` returns refusal for diagnosis/treatment/severe symptoms.
- Tests cover medical refusal behavior.

Photo/privacy:

- iOS may upload image bytes to `/v1/photo/scan` if user uses photo scan.
- Dev scan provider does not persist raw photos.
- Store `add_history` strips keys like `photo_b64`, `raw_photo`, `image_bytes`.
- OpenRouter advisor does not receive photos.
- There is a delete request endpoint for scan id, but production storage adapter is not implemented.

Before real testers, verify:

- `.env` and secrets are not in git or iOS bundle.
- OpenRouter payload logging does not include user PII.
- Privacy copy is accurate for actual staging retention.
- If production photo storage is added later, retention/deletion must be implemented for real.

## 15. Current limitations / risks

Honest list:

- Local auth is not production auth. External auth adapter is contract-only.
- Checkout is not live. Current cart checkout flow is beta/save-selection oriented.
- Catalog is synthetic/test catalog, not real Golden Apple live catalog.
- Production catalog adapter is not implemented.
- Product images are generated/static development assets, not final licensed retail imagery.
- No proper migrations framework; tables are created with `CREATE TABLE IF NOT EXISTS`.
- JSON blobs in DB reduce data integrity and queryability.
- OpenRouter is an external dependency; response format compatibility varies by model/provider.
- Advisor fallback can be useful but is deterministic and less conversational.
- Agent context is intentionally limited; it sees only subset catalog, not full catalog.
- Saved routine is only partly represented in AI context as SKU list unless active selection/cart contain full products.
- Structured product actions are still basic: no first-class `replace_product(old_sku,new_sku)` action yet.
- Fine-grained alternatives UX is not fully modeled backend-side.
- Beauty Scan is cosmetic-context only; no real skin analysis or medical inference.
- Photo deletion endpoint creates a request, but real production storage deletion adapter is not connected.
- Observability is minimal: logs/events exist, but no full tracing, metrics dashboard or provider quality analytics.
- No explicit API rate limiting implementation in backend; `enforce_auth_rate_limit` is currently a hook/no-op.
- Before any public pilot beyond controlled staging, add and verify real auth/advisor rate limiting at the reverse proxy or backend middleware layer.
- No admin panel.
- Production readiness checks intentionally report not ready for unimplemented provider contracts.

## 16. Как улучшить AI agent дальше

Recommended next steps:

1. Сделать explicit structured actions from AI:
   - `add_products`
   - `replace_product`
   - `add_alternative`
   - `explain_product`
   - `refine_budget`
   - `save_routine_suggestion`
2. Передавать saved routine как полные product cards, а не только SKU list.
3. Добавить отдельный `current_selection` backend source of truth, если active selection должна жить между устройствами.
4. Сделать safe memory summary вместо роста линейной истории.
5. Ввести жесткий context budget: N messages, M products, max chars per product field.
6. Добавить observability для advisor:
   - provider latency;
   - fallback reason rates;
   - invalid JSON/schema rates;
   - unknown SKU attempts;
   - medical refusal counts;
   - prompt version performance.
7. Добавить backend tests для:
   - hallucinated SKU;
   - medical refusal;
   - no email/token/photo in provider payload;
   - current selection respected;
   - duplicate SKU handling;
   - replace only explicit.
8. Улучшить catalog grounding:
   - retrieval по category/focus;
   - diversity constraints;
   - budget-aware alternatives;
   - explainable score fields.
9. Формализовать `why this product` как per-product reason, а не только общий text.
10. Добавить moderation/safety layer для provider output, если появятся более рискованные категории/claims.

## 17. Diagrams / Flow

### A. Advisor message flow

```text
iOS AdvisorView
  -> AppState.sendAdvisorMessage(text)
  -> advisorContext()
       current selection from recommendations
       current cart from cart.items
       current_skus from selection + cart + savedRoutineSkus
  -> APIClient POST /v1/advisor/message
  -> FastAPI current_account()
  -> load Beauty ID from request or store
  -> clean user message
  -> load advisor_messages limit 24
  -> build_advisor_response()
       if medical intent -> medical refusal
       provider = OpenRouter or deterministic fallback
       build allowed_products subset
       build prompt/user_context
       call OpenRouter /chat/completions
       parse JSON
       map recommended_skus to allowed_products
       fallback if invalid/ungrounded
  -> filter recommendations by known available catalog SKUs
  -> save user + assistant messages
  -> save advisor_history event
  -> return AdvisorResponse
  -> iOS appends assistant message
  -> merge recommendations into active selection
  -> Home/Advisor/Recommendations update from AppState
```

### B. Login/session restore flow

```text
App launch
  -> AppState.boot()
  -> read access token from Keychain
  -> APIClient.accessToken = token
  -> GET /v1/profile/me
       success:
         set account
         set Beauty ID
         apply saved routine preview
         GET /v1/cart
         GET /v1/advisor/history
         GET /v1/routines/current
         POST /v1/recommendations
       failure:
         read refresh token
         POST /v1/auth/refresh
         persist new tokens
         retry profile/session data
       refresh failure:
         clear local session
```

### C. Product recommendation flow

```text
iOS requests POST /v1/recommendations
  -> backend loads Beauty ID from request or store
  -> recommendations.requested_categories()
  -> load_catalog(include_unavailable=False)
  -> score_product() per category/product
  -> choose best routine item per category
  -> add extra ranked products up to limit
  -> return RecommendationsResponse
  -> store recommendation_history event
  -> iOS sets or merges AppState.recommendations
```

### D. Saved routine flow

```text
User taps Save
  -> AppState.saveCurrentRoutine()
  -> skus = recommendations.routine.map(\.sku)
  -> PUT /v1/routines/current
  -> backend validates every SKU against LUMA catalog
  -> store.save_saved_routine(account_id, skus)
  -> return SavedRoutineResponse with products
  -> iOS applySavedRoutine()
  -> savedRoutineSkus persisted in UserDefaults
  -> Profile/Home can show saved routine status
```

## 18. TL;DR

AI agent в этом проекте - это backend-orchestrated beauty concierge. iOS не вызывает OpenRouter напрямую. iOS отправляет user message, Beauty ID и текущий product context на FastAPI backend; backend добавляет account-scoped history, выбирает catalog-grounded `allowed_products`, строит prompt и вызывает OpenRouter или deterministic fallback.

Что agent видит:

- user message;
- последние несколько сообщений диалога;
- сжатый Beauty ID;
- текущую активную подборку;
- текущую корзину;
- список текущих SKU;
- ограниченный subset каталога `allowed_products`;
- system restrictions and response schema.

Что agent НЕ видит:

- OpenRouter/API secrets from iOS;
- access/refresh tokens;
- email/name пользователя;
- raw photos/base64/images;
- весь каталог;
- всю базу;
- полную историю всех действий.

Как backend защищает от выдуманных товаров:

- Prompt разрешает только SKU из `allowed_products`.
- OpenRouter должен вернуть `recommended_skus`, а не произвольные product cards.
- Backend мапит SKU только к `allowed_products`.
- Unknown/unavailable SKU отбрасываются или приводят к fallback.
- Финальная фильтрация в endpoint оставляет только known available catalog SKUs.

Главные слабые места:

- local auth and provider contracts are not production-ready;
- catalog synthetic, no live retail adapter;
- no real checkout;
- no proper migrations;
- limited observability/rate limiting;
- active selection is mostly iOS source of truth;
- saved routine context should be richer in AI payload;
- structured AI actions need to mature before broader beta.

Перед 100 тестерами стоит усилить auth, observability, rate limiting, production catalog/checkout contracts, privacy/photo retention implementation, advisor structured actions and tests around medical refusal / hallucinated SKU / selection merge behavior.
