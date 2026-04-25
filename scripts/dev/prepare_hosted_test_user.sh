#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: prepare_hosted_test_user.sh [--env staging|prod] [--email <email>] [--password <password>]

Creates a hosted Supabase auth user via the admin API with email confirmation
already marked complete, then prints shell exports for Patrol:

  export E2E_TEST_EMAIL=...
  export E2E_TEST_PASSWORD=...
  export SUPABASE_SERVICE_ROLE_KEY=...

This avoids hosted email confirmation and default-SMTP rate-limit friction for
automated signoff runs.
EOF
}

app_env="prod"
email=""
password=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      app_env="${2:-}"
      shift 2
      ;;
    --email)
      email="${2:-}"
      shift 2
      ;;
    --password)
      password="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$app_env" in
  staging|prod)
    ;;
  *)
    printf 'Unsupported --env value: %s\n' "$app_env" >&2
    exit 1
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

# shellcheck source=/dev/null
source "${repo_root}/scripts/lib/deployment_common.sh"

env_file="${repo_root}/$(resolve_env_file_path "$app_env")"
secret_source_file="${repo_root}/.secret/.env.secret"
if [[ ! -f "$env_file" ]]; then
  printf 'Missing env file: %s\n' "$env_file" >&2
  exit 1
fi

supabase_url="${SUPABASE_URL:-$(read_env_value "$env_file" "SUPABASE_URL")}"
service_role_key="$(resolve_service_role_key "$env_file" "$secret_source_file" 2>/dev/null)" || true

if [[ -z "$supabase_url" || -z "$service_role_key" ]]; then
  printf '%s\n' \
    "Hosted test-user creation requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY." \
    "Set them in the shell, populate them in ${env_file}, or add the UFF prod secret key to ${secret_source_file}." >&2
  exit 1
fi

if ! command -v ruby &>/dev/null; then
  printf 'Ruby not found. This script uses Ruby to build the JSON payload.\n' >&2
  printf 'macOS ships with Ruby; if missing, install via: brew install ruby\n' >&2
  exit 1
fi

random_suffix() {
  python3 - "$@" <<'PY'
import secrets
import string
import sys

length = int(sys.argv[1]) if len(sys.argv) > 1 else 8
alphabet = string.ascii_lowercase + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(length)), end='')
PY
}

if [[ -z "$email" ]]; then
  email="e2e-${app_env}-$(date +%s)-$(random_suffix 8)@example.com"
fi

if [[ -z "$password" ]]; then
  password="Test!$(random_suffix 20)"
fi

create_payload="$(
  TEST_USER_EMAIL="${email}" \
  TEST_USER_PASSWORD="${password}" \
  ruby -rjson -e 'puts({
    email: ENV.fetch("TEST_USER_EMAIL"),
    password: ENV.fetch("TEST_USER_PASSWORD"),
    email_confirm: true,
    user_metadata: { display_name: "E2E Hosted Test" },
  }.to_json)'
)"

response="$(
  curl -sS -w '\n%{http_code}' -X POST \
    "${supabase_url}/auth/v1/admin/users" \
    -H "Authorization: Bearer ${service_role_key}" \
    -H "apikey: ${service_role_key}" \
    -H "Content-Type: application/json" \
    -d "${create_payload}"
)"

http_status="${response##*$'\n'}"
response_body="${response%$'\n'*}"

if [[ "$http_status" -lt 200 || "$http_status" -ge 300 ]]; then
  printf 'Hosted test-user creation failed (HTTP %s).\n' "$http_status" >&2
  printf '%s\n' "$response_body" >&2
  exit 1
fi

printf 'export E2E_TEST_EMAIL=%q\n' "$email"
printf 'export E2E_TEST_PASSWORD=%q\n' "$password"
printf 'export SUPABASE_SERVICE_ROLE_KEY=%q\n' "$service_role_key"
