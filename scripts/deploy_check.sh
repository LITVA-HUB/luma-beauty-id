#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://185.46.11.61:8010}"
SAMPLE_IMAGE="${SAMPLE_IMAGE:-/assets/cards/001_FD-BUD-01.png}"

check_json() {
  local path="$1"
  echo "GET ${BASE_URL}${path}"
  curl -fsS "${BASE_URL}${path}" >/tmp/luma_deploy_check_response.json
  echo "OK ${path}"
}

check_head() {
  local path="$1"
  echo "HEAD ${BASE_URL}${path}"
  curl -fsSI "${BASE_URL}${path}" >/dev/null
  echo "OK ${path}"
}

check_json "/health"
check_json "/ready"
check_json "/v1/catalog/products"
check_head "${SAMPLE_IMAGE}"

echo "deploy_check passed for ${BASE_URL}"
