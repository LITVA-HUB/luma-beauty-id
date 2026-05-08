# Обновление staging backend на REG.RU VPS

Staging backend:

```text
https://api-staging.lumatestdomen.online
```

Сервер:

```text
ssh root@185.46.11.61
cd /opt/luma
docker compose -f docker-compose.staging.yml
```

Важно:

- Не перезаписывать `/opt/luma/.env`.
- Не копировать secrets в репозиторий, архивы или отчёты.
- Не делать `docker compose down -v`.
- Не удалять Docker volume PostgreSQL.
- Не делать destructive reset базы.
- Перед rebuild делать backup PostgreSQL.
- После deploy проверять `/health`, `/ready`, каталог и static assets.

На текущем сервере `/opt/luma` не является git repo, поэтому основной способ обновления сейчас — вариант B через `rsync` с Mac.

## Вариант A: если `/opt/luma` станет git repo

На сервере:

```bash
ssh root@185.46.11.61
cd /opt/luma
git status
./scripts/backup_postgres.sh
git pull
docker compose -f docker-compose.staging.yml up -d --build
docker compose -f docker-compose.staging.yml ps
docker compose -f docker-compose.staging.yml logs --tail=100 backend
curl https://api-staging.lumatestdomen.online/health
curl https://api-staging.lumatestdomen.online/ready
curl -I https://api-staging.lumatestdomen.online/assets/cards/001_FD-BUD-01.png
```

Если есть `deploy_check.sh`:

```bash
BASE_URL=https://api-staging.lumatestdomen.online ./scripts/deploy_check.sh
```

## Вариант B: обновление с Mac через rsync

Запускать с Mac из корня проекта.

Самый безопасный вариант без удаления старых файлов на сервере:

```bash
rsync -avz \
  --exclude ".env" \
  --exclude ".env.save" \
  --exclude "*.env.local" \
  --exclude "backend/.env" \
  --exclude ".git" \
  --exclude ".data" \
  --exclude "__pycache__" \
  --exclude ".pytest_cache" \
  --exclude ".venv" \
  --exclude "DerivedData" \
  --exclude "xcuserdata" \
  --exclude "backups" \
  --exclude "backend/.data" \
  --exclude ".DS_Store" \
  ./ root@185.46.11.61:/opt/luma/
```

Вариант с `--delete` можно использовать только если excludes проверены и понятно, что на сервере нет нужных runtime-файлов вне excludes:

```bash
rsync -avz --delete \
  --exclude ".env" \
  --exclude ".env.save" \
  --exclude "*.env.local" \
  --exclude "backend/.env" \
  --exclude ".git" \
  --exclude ".data" \
  --exclude "__pycache__" \
  --exclude ".pytest_cache" \
  --exclude ".venv" \
  --exclude "DerivedData" \
  --exclude "xcuserdata" \
  --exclude "backups" \
  --exclude "backend/.data" \
  --exclude ".DS_Store" \
  ./ root@185.46.11.61:/opt/luma/
```

После rsync на сервере:

```bash
ssh root@185.46.11.61
cd /opt/luma
./scripts/backup_postgres.sh
docker compose -f docker-compose.staging.yml up -d --build
docker compose -f docker-compose.staging.yml ps
docker compose -f docker-compose.staging.yml logs --tail=100 backend
curl https://api-staging.lumatestdomen.online/health
curl https://api-staging.lumatestdomen.online/ready
curl -I https://api-staging.lumatestdomen.online/assets/cards/001_FD-BUD-01.png
```

Если есть `deploy_check.sh`:

```bash
BASE_URL=https://api-staging.lumatestdomen.online ./scripts/deploy_check.sh
```

## Удобный update script

С Mac из корня проекта:

```bash
./scripts/update_staging_server.sh
```

Скрипт:

- использует `STAGING_HOST=185.46.11.61`;
- использует `STAGING_USER=root`;
- использует `STAGING_PATH=/opt/luma`;
- не копирует `.env`, `backend/.env`, backups, caches и локальные runtime-файлы;
- по умолчанию не удаляет лишние файлы на сервере;
- делает backup PostgreSQL перед rebuild;
- выполняет `docker compose -f docker-compose.staging.yml up -d --build`;
- проверяет локальные endpoint-ы backend внутри сервера.

Опциональные переменные:

```bash
STAGING_HOST=185.46.11.61 \
STAGING_USER=root \
STAGING_PATH=/opt/luma \
./scripts/update_staging_server.sh
```

Удаление лишних файлов на сервере через rsync включается только явно:

```bash
DELETE_REMOTE=1 ./scripts/update_staging_server.sh
```

Перед `DELETE_REMOTE=1` проверь excludes. Никогда не удаляй PostgreSQL volume и backups.

## Проверка после deploy

С Mac:

```bash
curl https://api-staging.lumatestdomen.online/health
curl https://api-staging.lumatestdomen.online/ready
curl -I https://api-staging.lumatestdomen.online/assets/cards/001_FD-BUD-01.png
BASE_URL=https://api-staging.lumatestdomen.online ./scripts/deploy_check.sh
```

Ожидаемо:

- `/health` возвращает `status: ok`;
- `/ready` возвращает успешный readiness ответ;
- sample image возвращает `200 OK` и `Content-Type: image/png`;
- backend logs не показывают traceback на startup.

## Если deploy не поднялся

На сервере:

```bash
cd /opt/luma
docker compose -f docker-compose.staging.yml ps
docker compose -f docker-compose.staging.yml logs --tail=200 backend
docker compose -f docker-compose.staging.yml logs --tail=100 postgres
```

Если проблема в новом backend-коде, откати файлы предыдущим способом доставки и снова выполни:

```bash
docker compose -f docker-compose.staging.yml up -d --build
```

Не выполняй `down -v` и не удаляй volume PostgreSQL.
