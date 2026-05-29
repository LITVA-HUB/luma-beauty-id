# DEV_SETUP — local bring-up

Tested on macOS, Python 3.13, Xcode 26 + iOS 26 simulator (`iPhone 17 Pro`).
Run everything from the repo root unless noted.

> Note: the project uses **Postgres** in staging (`DATABASE_URL` in `.env` points to the
> docker service `postgres:5432`). For **local dev** we run the backend with the SQLite
> fallback via runtime overrides — `.env` is never edited.

---

## 1. Backend

### One-time setup
```bash
python3 -m venv .venv
./.venv/bin/pip install --upgrade pip
./.venv/bin/pip install -r backend/requirements.txt
```

### Run tests
```bash
./.venv/bin/python -m pytest -q          # expect: 48 passed
```

### Run the API on http://127.0.0.1:8010 (dev / SQLite)
```bash
cd backend
APP_ENV=development DATABASE_URL='' API_HOST=127.0.0.1 API_PORT=8010 \
  ALLOW_DEV_AUTH=true ADVISOR_PROVIDER=deterministic \
  ../.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8010
```
Add `--reload` for auto-restart on file changes.

### Health checks
```bash
curl http://127.0.0.1:8010/health   # -> {"status":"ok",...}
curl http://127.0.0.1:8010/ready    # -> {"status":"ready","catalog_items":94,...}
```

The SQLite store is created at `backend/.data/luma_beauty.sqlite3` (gitignored).

---

## 2. iOS app

### Build (Debug, simulator)
```bash
cd ios
xcodebuild build \
  -scheme BeautyConcierge \
  -project BeautyConcierge.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug
# expect: ** BUILD SUCCEEDED **
```

### Install + launch in the simulator
```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null; open -a Simulator
APP=$(xcodebuild -scheme BeautyConcierge -project ios/BeautyConcierge.xcodeproj \
  -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "iPhone 17 Pro" "$APP"
xcrun simctl launch "iPhone 17 Pro" com.dimalitin.lumabeautyid.dev
```

> Default Debug config points the app at the staging API. To make the simulator talk to the
> **local** backend, build with overrides (no project edits):
> `xcodebuild ... API_BASE_URL='http://127.0.0.1:8010' APP_ENVIRONMENT=development`

### Screenshot the simulator
```bash
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/shot.png
```

---

## 3. Docker (staging only — optional)

`docker-compose.staging.yml` builds the backend image and a Postgres 16 service.
Requires Docker Desktop running and real `.env` secrets. Not needed for local dev.
```bash
docker compose -f docker-compose.staging.yml up -d
```

---

## Quick "is it working?" checklist
- [ ] `git status` → clean
- [ ] `./.venv/bin/python -m pytest -q` → 48 passed
- [ ] backend `/health` → `status: ok`
- [ ] `xcodebuild build ...` → BUILD SUCCEEDED
