#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.staging.yml}"
SERVICE="${POSTGRES_SERVICE:-postgres}"
DB_NAME="${POSTGRES_DB:-luma_staging}"
DB_USER="${POSTGRES_USER:-luma_user}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${BACKUP_DIR:-./backups}"
OUT_FILE="${OUT_DIR}/luma_staging_${STAMP}.sql.gz"

mkdir -p "${OUT_DIR}"

docker compose -f "${COMPOSE_FILE}" exec -T "${SERVICE}" \
  pg_dump -U "${DB_USER}" -d "${DB_NAME}" --no-owner --no-privileges \
  | gzip -c > "${OUT_FILE}"

chmod 600 "${OUT_FILE}"
echo "Backup written: ${OUT_FILE}"
