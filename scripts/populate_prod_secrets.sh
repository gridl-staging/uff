#!/usr/bin/env bash
# populate_prod_secrets.sh — Inject prod secrets into .env.prod from the approved source.
#
# Reads from the secret source file and its referenced Firebase JSON, then
# inserts or updates exactly the six deploy-read secret keys in .env.prod.
# Idempotent: running twice produces the same result with no duplicate keys.
#
# Usage:
#   ./scripts/populate_prod_secrets.sh --secret-source <path> --env-file <path>
#
# The script does NOT write SUPABASE_ACCESS_TOKEN to the env file because
# preflight_check.sh does not read it there — it must be exported in the
# shell session separately.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/deployment_common.sh"

SECRET_SOURCE=""
ENV_FILE=""

print_usage() {
  cat <<EOF
Usage: $0 --secret-source <path> --env-file <path>

Populates the target env file with prod secrets from the approved source.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --secret-source)
      SECRET_SOURCE="$2"
      shift 2
      ;;
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$SECRET_SOURCE" || -z "$ENV_FILE" ]]; then
  echo "Error: --secret-source and --env-file are required" >&2
  print_usage >&2
  exit 1
fi

if [[ ! -f "$SECRET_SOURCE" ]]; then
  echo "Error: secret source not found: ${SECRET_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: env file not found: ${ENV_FILE}" >&2
  exit 1
fi

# Read a value from the secret source (same parsing as read_env_value).
read_source_key() {
  local key="$1"
  read_env_value "$SECRET_SOURCE" "$key"
}

normalize_private_key_for_env() {
  local value="$1"

  # deployment_common.sh reads one KEY=value line at a time, so keep the PEM on
  # a single line before writing it into .env.prod.
  value="${value//$'\r'/}"
  value="${value//$'\n'/}"
  printf '%s' "$value"
}

read_firebase_field() {
  local field_name="$1"
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d[sys.argv[2]])" "$firebase_json" "$field_name"
}

# --- Extract values from approved source ---

firebase_json="$(read_source_key "firebase_keys_path")"
if [[ -z "$firebase_json" || ! -f "$firebase_json" ]]; then
  echo "Error: firebase JSON not found at path from firebase_keys_path: ${firebase_json:-<empty>}" >&2
  exit 1
fi

service_role_key="$(read_source_key "SUPABASE_uff_prod_project__SECRET_KEY")"
db_password="$(read_source_key "SUPABASE_uff_prod_project__DB_PASSWORD")"
webhook_secret="$(read_source_key "NOTIFICATION_WEBHOOK_SECRET")"

# Extract Firebase service account fields via python3 (available on macOS).
fcm_project_id="$(read_firebase_field "project_id")"
fcm_client_email="$(read_firebase_field "client_email")"
fcm_private_key="$(read_firebase_field "private_key")"
fcm_private_key="$(normalize_private_key_for_env "$fcm_private_key")"

# --- Validate all six values are non-empty ---

errors=0
for pair in \
  "SUPABASE_SERVICE_ROLE_KEY:${service_role_key}" \
  "SUPABASE_DB_PASSWORD:${db_password}" \
  "FCM_PROJECT_ID:${fcm_project_id}" \
  "FCM_CLIENT_EMAIL:${fcm_client_email}" \
  "NOTIFICATION_WEBHOOK_SECRET:${webhook_secret}"; do
  key="${pair%%:*}"
  val="${pair#*:}"
  if [[ -z "$val" ]]; then
    echo "Error: required source value for ${key} is empty" >&2
    errors=$((errors + 1))
  fi
done
# FCM_PRIVATE_KEY may contain colons, check separately.
if [[ -z "$fcm_private_key" ]]; then
  echo "Error: required source value for FCM_PRIVATE_KEY is empty" >&2
  errors=$((errors + 1))
fi

if [[ "$errors" -gt 0 ]]; then
  exit 1
fi

for pair in \
  "SUPABASE_SERVICE_ROLE_KEY:${service_role_key}" \
  "SUPABASE_DB_PASSWORD:${db_password}" \
  "FCM_PROJECT_ID:${fcm_project_id}" \
  "FCM_CLIENT_EMAIL:${fcm_client_email}" \
  "FCM_PRIVATE_KEY:${fcm_private_key}" \
  "NOTIFICATION_WEBHOOK_SECRET:${webhook_secret}"; do
  key="${pair%%:*}"
  value="${pair#*:}"
  upsert_env_key "$ENV_FILE" "$key" "$value"
done

echo "Populated 6 prod secrets in ${ENV_FILE}"
