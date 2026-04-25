#!/usr/bin/env bash
# Tests for scripts/populate_prod_secrets.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

failures=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${description} (expected '${expected}', got '${actual}')"
    failures=$((failures + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: ${description} (missing '${needle}')"
    failures=$((failures + 1))
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "FAIL: ${description} (unexpected '${needle}')"
    failures=$((failures + 1))
  fi
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${description} (expected exit ${expected}, got ${actual})"
    failures=$((failures + 1))
  fi
}

# Create a minimal secret source fixture with all required keys.
create_secret_source_fixture() {
  local temp_dir="$1"
  local firebase_json="${temp_dir}/firebase-admin.json"

  cat > "${firebase_json}" <<'FJSON'
{
  "type": "service_account",
  "project_id": "uff-prod-test",
  "client_email": "firebase-adminsdk@uff-prod-test.iam.gserviceaccount.com",
  "private_key": "-----BEGIN PRIVATE KEY-----\nTEST_KEY\n-----END PRIVATE KEY-----\n",
  "private_key_id": "test-key-id",
  "client_id": "12345",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
FJSON

  cat > "${temp_dir}/.env.secret" <<EOF
SUPABASE_uff_prod_project__SECRET_KEY=test-service-role-key
SUPABASE_uff_prod_project__DB_PASSWORD=test-db-password
SUPABASE_ACCESS_TOKEN_uff_mar23=test-access-token
NOTIFICATION_WEBHOOK_SECRET=test-webhook-secret
firebase_keys_path=${firebase_json}
UNRELATED_KEY=should-not-appear
EOF
}

expected_private_key_single_line() {
  printf '%s' '-----BEGIN PRIVATE KEY-----TEST_KEY-----END PRIVATE KEY-----'
}

# Create a baseline .env.prod with only tracked non-secret values.
create_baseline_env_prod() {
  local temp_dir="$1"
  cat > "${temp_dir}/.env.prod" <<'EOF'
SUPABASE_URL=https://jtzohitezwhbkxkvhtty.supabase.co
SUPABASE_ANON_KEY=sb_publishable_test
MAPBOX_ACCESS_TOKEN=
GOOGLE_WEB_CLIENT_ID=<google-oauth-web-client-id>
GOOGLE_IOS_CLIENT_ID=<google-oauth-ios-client-id>
APPLE_SERVICE_ID=com.gridl.uff
EOF
}

assert_populates_all_six_secrets() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  create_secret_source_fixture "$temp_dir"
  create_baseline_env_prod "$temp_dir"

  local status=0
  local output
  output="$(
    "${REPO_ROOT}/scripts/populate_prod_secrets.sh" \
      --secret-source "${temp_dir}/.env.secret" \
      --env-file "${temp_dir}/.env.prod"
  )" || status=$?

  assert_exit_code 0 "$status" "populate succeeds with valid inputs"

  # Source the deployment_common helpers to read the populated file the same
  # way preflight_check.sh will.
  source "${REPO_ROOT}/scripts/lib/deployment_common.sh"

  local val
  val="$(read_env_value "${temp_dir}/.env.prod" "SUPABASE_SERVICE_ROLE_KEY")"
  assert_eq "test-service-role-key" "$val" "SUPABASE_SERVICE_ROLE_KEY populated"

  val="$(read_env_value "${temp_dir}/.env.prod" "SUPABASE_DB_PASSWORD")"
  assert_eq "test-db-password" "$val" "SUPABASE_DB_PASSWORD populated"

  val="$(read_env_value "${temp_dir}/.env.prod" "FCM_PROJECT_ID")"
  assert_eq "uff-prod-test" "$val" "FCM_PROJECT_ID populated from firebase JSON"

  val="$(read_env_value "${temp_dir}/.env.prod" "FCM_CLIENT_EMAIL")"
  assert_eq "firebase-adminsdk@uff-prod-test.iam.gserviceaccount.com" "$val" "FCM_CLIENT_EMAIL populated from firebase JSON"

  val="$(read_env_value "${temp_dir}/.env.prod" "FCM_PRIVATE_KEY")"
  assert_eq "$(expected_private_key_single_line)" "$val" "FCM_PRIVATE_KEY stays env-safe and round-trippable"

  val="$(read_env_value "${temp_dir}/.env.prod" "NOTIFICATION_WEBHOOK_SECRET")"
  assert_eq "test-webhook-secret" "$val" "NOTIFICATION_WEBHOOK_SECRET populated"

  local contents
  contents="$(cat "${temp_dir}/.env.prod")"
  assert_contains "$contents" "FCM_PRIVATE_KEY=$(expected_private_key_single_line)" "FCM_PRIVATE_KEY written as a single env line"
  assert_not_contains "$contents" $'\nTEST_KEY\n' "FCM_PRIVATE_KEY is not split into standalone file lines"

  rm -rf "$temp_dir"
}

assert_preserves_tracked_baseline() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  create_secret_source_fixture "$temp_dir"
  create_baseline_env_prod "$temp_dir"

  local status=0
  "${REPO_ROOT}/scripts/populate_prod_secrets.sh" \
    --secret-source "${temp_dir}/.env.secret" \
    --env-file "${temp_dir}/.env.prod" >/dev/null || status=$?

  assert_exit_code 0 "$status" "populate succeeds for baseline preservation test"

  source "${REPO_ROOT}/scripts/lib/deployment_common.sh"

  local val
  val="$(read_env_value "${temp_dir}/.env.prod" "SUPABASE_URL")"
  assert_eq "https://jtzohitezwhbkxkvhtty.supabase.co" "$val" "SUPABASE_URL preserved"

  val="$(read_env_value "${temp_dir}/.env.prod" "SUPABASE_ANON_KEY")"
  assert_eq "sb_publishable_test" "$val" "SUPABASE_ANON_KEY preserved"

  val="$(read_env_value "${temp_dir}/.env.prod" "APPLE_SERVICE_ID")"
  assert_eq "com.gridl.uff" "$val" "APPLE_SERVICE_ID preserved"

  rm -rf "$temp_dir"
}

assert_no_duplicate_keys() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  create_secret_source_fixture "$temp_dir"
  create_baseline_env_prod "$temp_dir"

  # Run populate twice to test idempotency — second run must update, not append.
  "${REPO_ROOT}/scripts/populate_prod_secrets.sh" \
    --secret-source "${temp_dir}/.env.secret" \
    --env-file "${temp_dir}/.env.prod" >/dev/null

  "${REPO_ROOT}/scripts/populate_prod_secrets.sh" \
    --secret-source "${temp_dir}/.env.secret" \
    --env-file "${temp_dir}/.env.prod" >/dev/null

  source "${REPO_ROOT}/scripts/lib/deployment_common.sh"

  local count
  for key in SUPABASE_SERVICE_ROLE_KEY SUPABASE_DB_PASSWORD FCM_PROJECT_ID \
             FCM_CLIENT_EMAIL FCM_PRIVATE_KEY NOTIFICATION_WEBHOOK_SECRET; do
    count="$(count_env_key_occurrences "${temp_dir}/.env.prod" "$key")"
    assert_eq "1" "$count" "no duplicate ${key} after double populate"
  done

  rm -rf "$temp_dir"
}

assert_excludes_unrelated_keys() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  create_secret_source_fixture "$temp_dir"
  create_baseline_env_prod "$temp_dir"

  "${REPO_ROOT}/scripts/populate_prod_secrets.sh" \
    --secret-source "${temp_dir}/.env.secret" \
    --env-file "${temp_dir}/.env.prod" >/dev/null

  local contents
  contents="$(cat "${temp_dir}/.env.prod")"
  assert_not_contains "$contents" "UNRELATED_KEY" "unrelated source keys excluded from .env.prod"
  assert_not_contains "$contents" "SUPABASE_ACCESS_TOKEN" "SUPABASE_ACCESS_TOKEN not written to .env.prod (shell export only)"
  assert_not_contains "$contents" "firebase_keys_path" "firebase_keys_path not written to .env.prod"

  rm -rf "$temp_dir"
}

assert_fails_when_source_missing_required_key() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  create_baseline_env_prod "$temp_dir"

  # Create a source missing NOTIFICATION_WEBHOOK_SECRET
  cat > "${temp_dir}/.env.secret" <<EOF
SUPABASE_uff_prod_project__SECRET_KEY=test-service-role-key
SUPABASE_uff_prod_project__DB_PASSWORD=test-db-password
firebase_keys_path=${temp_dir}/firebase-admin.json
EOF
  cat > "${temp_dir}/firebase-admin.json" <<'FJSON'
{
  "project_id": "uff-prod-test",
  "client_email": "test@example.com",
  "private_key": "test-key"
}
FJSON

  local status=0
  local output
  output="$(
    "${REPO_ROOT}/scripts/populate_prod_secrets.sh" \
      --secret-source "${temp_dir}/.env.secret" \
      --env-file "${temp_dir}/.env.prod" 2>&1
  )" || status=$?

  assert_exit_code 1 "$status" "populate fails when source lacks required key"
  assert_contains "$output" "NOTIFICATION_WEBHOOK_SECRET" "error message names the missing key"

  rm -rf "$temp_dir"
}

assert_fails_when_firebase_json_missing() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  create_baseline_env_prod "$temp_dir"

  cat > "${temp_dir}/.env.secret" <<EOF
SUPABASE_uff_prod_project__SECRET_KEY=test-service-role-key
SUPABASE_uff_prod_project__DB_PASSWORD=test-db-password
NOTIFICATION_WEBHOOK_SECRET=test-secret
firebase_keys_path=${temp_dir}/nonexistent.json
EOF

  local status=0
  local output
  output="$(
    "${REPO_ROOT}/scripts/populate_prod_secrets.sh" \
      --secret-source "${temp_dir}/.env.secret" \
      --env-file "${temp_dir}/.env.prod" 2>&1
  )" || status=$?

  assert_exit_code 1 "$status" "populate fails when firebase JSON is missing"
  assert_contains "$output" "firebase" "error mentions firebase"

  rm -rf "$temp_dir"
}

main() {
  assert_populates_all_six_secrets
  assert_preserves_tracked_baseline
  assert_no_duplicate_keys
  assert_excludes_unrelated_keys
  assert_fails_when_source_missing_required_key
  assert_fails_when_firebase_json_missing

  if [[ "$failures" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "populate_prod_secrets_test: PASS"
}

main "$@"
