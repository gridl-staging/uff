#!/usr/bin/env bash
# Shared helpers for Stage 3 auth test scripts.
# Source this file — do not execute directly.
#
# Provides: Supabase config defaults, HTTP request helpers, shared
#           assertions, principal sign-in helpers, preflight checks,
#           DB access, and auth admin cleanup.
#
# Environment variables (optional — defaults target local Supabase):
#   SUPABASE_URL              API base URL
#   SUPABASE_ANON_KEY         Anonymous (publishable) key
#   SUPABASE_SERVICE_ROLE_KEY Service role key for admin operations
#   SUPABASE_DB_URL           PostgreSQL connection string
#   SUPABASE_DB_CONTAINER     Docker container name for local DB fallback

# ---------------------------------------------------------------------------
# Configuration — defaults target local Supabase stack
# ---------------------------------------------------------------------------

DEFAULT_API_URL="http://127.0.0.1:54321"
DEFAULT_DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
DEFAULT_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
DEFAULT_SERVICE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"

API_URL="${SUPABASE_URL:-$DEFAULT_API_URL}"
ANON_KEY="${SUPABASE_ANON_KEY:-$DEFAULT_ANON_KEY}"
SERVICE_KEY="${SUPABASE_SERVICE_ROLE_KEY:-$DEFAULT_SERVICE_KEY}"
DB_URL="${SUPABASE_DB_URL:-$DEFAULT_DB_URL}"

AUTH_URL="${API_URL}/auth/v1"

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

http_request() {
  curl -sS -w "\n%{http_code}" "$@" 2>/dev/null || printf "\n000"
}

http_post_json() {
  local url="$1" payload="$2"
  shift 2
  http_request -X POST "$url" "$@" -H "Content-Type: application/json" -d "$payload"
}

http_get() {
  local url="$1"
  shift
  http_request -X GET "$url" "$@"
}

split_http_response() {
  RESPONSE_STATUS="${1##*$'\n'}"
  RESPONSE_BODY="${1%$'\n'*}"
}

json_field() {
  printf '%s' "$1" | jq -er "$2" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Shared test assertions (pass/fail counters are script-owned globals)
# ---------------------------------------------------------------------------

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  printf "  PASS: %s\n" "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  printf "  FAIL: %s\n" "$1" >&2
}

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label (expected='${expected}', got='${actual}')"
  fi
}

assert_not_empty() {
  local value="$1" label="$2"
  if [ -n "$value" ]; then
    pass "$label"
  else
    fail "$label (value was empty)"
  fi
}

assert_http_ok() {
  local status="$1" label="$2"
  if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
    pass "$label"
  else
    fail "$label (HTTP ${status})"
  fi
}

assert_http_error() {
  local status="$1" label="$2"
  if [ "$status" -ge 400 ]; then
    pass "$label"
  else
    fail "$label (expected >=400, got HTTP ${status})"
  fi
}

assert_row_count() {
  local body="$1" expected="$2" label="$3"
  local actual
  actual=$(json_array_length "$body")
  assert_eq "$actual" "$expected" "$label"
}

require_auth_test_commands() {
  local missing_commands=()
  local cmd
  for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      missing_commands+=("$cmd")
    fi
  done

  if [ "${#missing_commands[@]}" -gt 0 ]; then
    printf "ABORT: required command(s) not found: %s\n" "${missing_commands[*]}" >&2
    return 1
  fi
}

auth_health_status() {
  curl -sf -o /dev/null -w "%{http_code}" "${AUTH_URL}/health" 2>/dev/null || echo "000"
}

require_auth_service_health() {
  local health_status
  health_status=$(auth_health_status)
  if [ "$health_status" -lt 200 ] || [ "$health_status" -ge 300 ]; then
    printf "ABORT: Auth service not reachable at %s (HTTP %s)\n" "${AUTH_URL}/health" "$health_status" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# DB access — prefer psql; docker fallback only for default local stack
# ---------------------------------------------------------------------------

if command -v psql &>/dev/null; then
  DB_METHOD="psql"
elif command -v docker &>/dev/null && [ "$API_URL" = "$DEFAULT_API_URL" ] && [ "$DB_URL" = "$DEFAULT_DB_URL" ]; then
  DB_METHOD="docker"
  DB_CONTAINER="${SUPABASE_DB_CONTAINER:-supabase_db_uff_dev}"
elif command -v docker &>/dev/null; then
  printf "ABORT: psql is required when targeting a non-default SUPABASE_URL/SUPABASE_DB_URL\n" >&2
  exit 1
else
  printf "ABORT: neither psql nor docker found for database access\n" >&2
  exit 1
fi

db_query() {
  if [ "$DB_METHOD" = "psql" ]; then
    psql "$DB_URL" -tAc "$1" 2>/dev/null
  else
    docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -tAc "$1" 2>/dev/null
  fi
}

# ---------------------------------------------------------------------------
# Auth admin helpers
# ---------------------------------------------------------------------------

delete_auth_user() {
  local user_id="$1"
  if [ -n "$user_id" ]; then
    curl -sf -o /dev/null -X DELETE \
      "${AUTH_URL}/admin/users/${user_id}" \
      -H "Authorization: Bearer ${SERVICE_KEY}" \
      -H "apikey: ${SERVICE_KEY}" 2>/dev/null || true
  fi
}

signup_email_password() {
  local email="$1" password="$2"
  http_post_json "${AUTH_URL}/signup" \
    "{\"email\":\"${email}\",\"password\":\"${password}\"}" \
    -H "apikey: ${ANON_KEY}"
}

signin_email_password() {
  local email="$1" password="$2"
  http_post_json "${AUTH_URL}/token?grant_type=password" \
    "{\"email\":\"${email}\",\"password\":\"${password}\"}" \
    -H "apikey: ${ANON_KEY}"
}

require_principals_file() {
  local principals_file="$1" missing_file_hint="${2:-}"
  if [ ! -f "$principals_file" ]; then
    printf "ABORT: %s not found.%s\n" "$principals_file" "$missing_file_hint" >&2
    exit 1
  fi
}

load_test_principal_credentials() {
  local principals_file="$1" role="$2"

  TEST_PRINCIPAL_ID=$(jq -r ".principals.${role}.auth_user_id" "$principals_file")
  TEST_PRINCIPAL_EMAIL=$(jq -r ".principals.${role}.email" "$principals_file")
  TEST_PRINCIPAL_PASSWORD=$(jq -r ".principals.${role}.password" "$principals_file")
}

sign_in_test_principal() {
  local principals_file="$1" role="$2" label="$3"
  local response

  load_test_principal_credentials "$principals_file" "$role"
  response=$(signin_email_password "$TEST_PRINCIPAL_EMAIL" "$TEST_PRINCIPAL_PASSWORD")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "${label} sign-in"

  TEST_PRINCIPAL_TOKEN=$(json_field "$RESPONSE_BODY" '.access_token')
  assert_not_empty "$TEST_PRINCIPAL_TOKEN" "${label} access token obtained"
}

sign_in_test_principal_pair() {
  local principals_file="$1" missing_file_hint="${2:-}"

  require_principals_file "$principals_file" "$missing_file_hint"

  sign_in_test_principal "$principals_file" owner "owner"
  SIGNED_IN_OWNER_ID="$TEST_PRINCIPAL_ID"
  SIGNED_IN_OWNER_TOKEN="$TEST_PRINCIPAL_TOKEN"

  sign_in_test_principal "$principals_file" other "other user"
  SIGNED_IN_OTHER_ID="$TEST_PRINCIPAL_ID"
  SIGNED_IN_OTHER_TOKEN="$TEST_PRINCIPAL_TOKEN"
}

# ---------------------------------------------------------------------------
# PostgREST API helpers (for RLS testing and data operations)
# ---------------------------------------------------------------------------

REST_URL="${API_URL}/rest/v1"

json_array_length() {
  printf '%s' "$1" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo "0"
}

rest_select() {
  local table="$1" token="$2" query="${3:-}"
  local url="${REST_URL}/${table}${query:+?${query}}"
  http_get "$url" -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${token}"
}

rest_select_anon() {
  local table="$1" query="${2:-}"
  local url="${REST_URL}/${table}${query:+?${query}}"
  http_get "$url" -H "apikey: ${ANON_KEY}"
}

rest_select_service() {
  local table="$1" query="${2:-}"
  local url="${REST_URL}/${table}${query:+?${query}}"
  http_get "$url" -H "apikey: ${SERVICE_KEY}" -H "Authorization: Bearer ${SERVICE_KEY}"
}

rest_insert() {
  local table="$1" payload="$2" token="$3"
  http_post_json "${REST_URL}/${table}" "$payload" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${token}" \
    -H "Prefer: return=representation"
}

rest_insert_service() {
  local table="$1" payload="$2"
  http_post_json "${REST_URL}/${table}" "$payload" \
    -H "apikey: ${SERVICE_KEY}" -H "Authorization: Bearer ${SERVICE_KEY}" \
    -H "Prefer: return=representation"
}

rest_update() {
  local table="$1" query="$2" payload="$3" token="$4"
  http_request -X PATCH "${REST_URL}/${table}?${query}" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" -H "Prefer: return=representation" \
    -d "$payload"
}

rest_delete() {
  local table="$1" query="$2" token="$3"
  http_request -X DELETE "${REST_URL}/${table}?${query}" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${token}" \
    -H "Prefer: return=representation"
}

rest_delete_service() {
  local table="$1" query="$2"
  http_request -X DELETE "${REST_URL}/${table}?${query}" \
    -H "apikey: ${SERVICE_KEY}" -H "Authorization: Bearer ${SERVICE_KEY}" \
    -H "Prefer: return=representation"
}

# ---------------------------------------------------------------------------
# Storage API helpers (for bucket/object operations)
# ---------------------------------------------------------------------------

STORAGE_URL="${API_URL}/storage/v1"

storage_upload() {
  local bucket="$1" path="$2" file="$3" mime_type="$4" token="$5"
  http_request -X POST "${STORAGE_URL}/object/${bucket}/${path}" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${token}" \
    -H "Content-Type: ${mime_type}" \
    --data-binary "@${file}"
}

storage_upload_upsert() {
  local bucket="$1" path="$2" file="$3" mime_type="$4" token="$5"
  http_request -X POST "${STORAGE_URL}/object/${bucket}/${path}" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${token}" \
    -H "Content-Type: ${mime_type}" \
    -H "x-upsert: true" \
    --data-binary "@${file}"
}

storage_download() {
  local bucket="$1" path="$2" token="$3"
  http_request -X GET "${STORAGE_URL}/object/${bucket}/${path}" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${token}"
}

storage_download_public() {
  local bucket="$1" path="$2"
  http_request -X GET "${STORAGE_URL}/object/public/${bucket}/${path}"
}

storage_delete() {
  local bucket="$1" path="$2" token="$3"
  http_request -X DELETE "${STORAGE_URL}/object/${bucket}" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "{\"prefixes\":[\"${path}\"]}"
}

storage_delete_service() {
  local bucket="$1" paths_json="$2"
  http_request -X DELETE "${STORAGE_URL}/object/${bucket}" \
    -H "apikey: ${SERVICE_KEY}" -H "Authorization: Bearer ${SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d "$paths_json"
}

storage_list() {
  local bucket="$1" prefix="$2" token="$3"
  http_post_json "${STORAGE_URL}/object/list/${bucket}" \
    "{\"prefix\":\"${prefix}\",\"limit\":100}" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${token}"
}
