#!/usr/bin/env bash
set -euo pipefail

STAGING_HOST="${STAGING_HOST:-185.46.11.61}"
STAGING_USER="${STAGING_USER:-root}"
STAGING_PATH="${STAGING_PATH:-/opt/luma}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.staging.yml}"
BASE_URL_LOCAL="${BASE_URL_LOCAL:-http://127.0.0.1:8010}"
SAMPLE_IMAGE="${SAMPLE_IMAGE:-/assets/cards/001_FD-BUD-01.png}"

RSYNC_DELETE_ARGS=""
if [[ "${DELETE_REMOTE:-0}" == "1" ]]; then
  RSYNC_DELETE_ARGS="--delete"
fi

echo "Updating staging server ${STAGING_USER}@${STAGING_HOST}:${STAGING_PATH}"
echo "Secrets are excluded. Server .env will not be copied."
if [[ "${DELETE_REMOTE:-0}" != "1" ]]; then
  echo "Remote delete is disabled. Set DELETE_REMOTE=1 only after checking excludes."
fi

rsync -avz ${RSYNC_DELETE_ARGS} \
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
  ./ "${STAGING_USER}@${STAGING_HOST}:${STAGING_PATH}/"

ssh "${STAGING_USER}@${STAGING_HOST}" bash -s <<EOF
set -euo pipefail
cd "${STAGING_PATH}"
echo "Creating PostgreSQL backup before rebuild..."
./scripts/backup_postgres.sh || true
docker compose -f "${COMPOSE_FILE}" up -d --build
docker compose -f "${COMPOSE_FILE}" ps
curl -fsS "${BASE_URL_LOCAL}/health" >/dev/null
echo "OK /health"
curl -fsS "${BASE_URL_LOCAL}/ready" >/dev/null
echo "OK /ready"
curl -fsSI "${BASE_URL_LOCAL}${SAMPLE_IMAGE}" >/dev/null
echo "OK ${SAMPLE_IMAGE}"
EOF

echo "Staging update finished."
