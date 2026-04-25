#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_auth_helpers.sh
source "${SCRIPT_DIR}/_auth_helpers.sh"

PRINCIPALS_FILE="${SCRIPT_DIR}/stage3_test_principals.json"
RUN_ID="$(date +%s)-$$"

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

OWNER_ID=""
OWNER_TOKEN=""
OTHER_ID=""

assert_policy_exists() {
  local table_name="$1" policy_name="$2"
  local policy_count
  policy_count=$(db_query "
    SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = '${table_name}'
      AND policyname = '${policy_name}';
  ")
  assert_eq "$policy_count" "1" "policy exists: ${table_name}.${policy_name}"
}

assert_select_count_service() {
  local table="$1" query="$2" expected="$3" label="$4"
  local response
  response=$(rest_select_service "$table" "$query")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "${label} status"
  assert_row_count "$RESPONSE_BODY" "$expected" "$label"
}

assert_single_row_mutation() {
  local response="$1" status_label="$2" row_label="$3"
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "$status_label"
  assert_row_count "$RESPONSE_BODY" "1" "$row_label"
}

assert_noop_mutation() {
  local response="$1" status_label="$2" row_label="$3"
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "$status_label"
  assert_row_count "$RESPONSE_BODY" "0" "$row_label"
}

load_and_sign_in() {
  printf "\n== Load principals and sign in ==\n"
  sign_in_test_principal_pair "$PRINCIPALS_FILE" \
    " Run stage3_provision_test_principals.sh first."
  OWNER_ID="$SIGNED_IN_OWNER_ID"
  OWNER_TOKEN="$SIGNED_IN_OWNER_TOKEN"
  OTHER_ID="$SIGNED_IN_OTHER_ID"
}

# TODO: Document preflight.
preflight() {
  printf "\n== Preflight ==\n"
  require_auth_test_commands

  local db_check
  db_check=$(db_query "SELECT 1;" 2>/dev/null || echo "")
  assert_eq "$db_check" "1" "database reachable"

  local column_exists
  column_exists=$(db_query "
    SELECT count(*)
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'fcm_token';
  ")
  assert_eq "$column_exists" "1" "profiles.fcm_token column exists"

  assert_policy_exists "profiles" "profiles_update_own"

  local profile_update_policy_count
  profile_update_policy_count=$(db_query "
    SELECT count(*)
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND cmd = 'UPDATE';
  ")
  assert_eq "$profile_update_policy_count" "1" \
    "profiles has one update policy"
}

# TODO: Document test_owner_can_update_own_token.
test_owner_can_update_own_token() {
  printf "\n== Owner token update ==\n"
  local response
  local owner_token_value="stage5-owner-token-${RUN_ID}"

  response=$(rest_update "profiles" "id=eq.${OWNER_ID}" \
    "{\"fcm_token\":\"${owner_token_value}\"}" "$OWNER_TOKEN")
  assert_single_row_mutation \
    "$response" \
    "owner updates own fcm_token" \
    "owner fcm_token update affects one row"
  assert_select_count_service \
    "profiles" \
    "id=eq.${OWNER_ID}&fcm_token=eq.${owner_token_value}" \
    "1" \
    "owner fcm_token persisted"
}

test_owner_cannot_update_other_token() {
  printf "\n== Cross-user token update blocked ==\n"
  local response

  response=$(rest_update "profiles" "id=eq.${OTHER_ID}" \
    "{\"fcm_token\":\"stage5-other-token-${RUN_ID}\"}" "$OWNER_TOKEN")
  assert_noop_mutation \
    "$response" \
    "owner cannot update other fcm_token status" \
    "owner other-user token update affects zero rows"
}

cleanup_test_data() {
  printf "\n== Cleanup ==\n"
  if [ -n "${OWNER_ID:-}" ] && [ -n "${OWNER_TOKEN:-}" ]; then
    rest_update "profiles" "id=eq.${OWNER_ID}" \
      '{"fcm_token":null}' \
      "$OWNER_TOKEN" >/dev/null 2>&1 || true
  fi
  printf "  cleanup complete\n"
}

print_summary() {
  printf "\n========================================\n"
  printf "Stage 5 FCM Token RLS Verification: %d/%d passed\n" \
    "$PASS_COUNT" \
    "$TOTAL_COUNT"
  if [ "$FAIL_COUNT" -gt 0 ]; then
    printf "%d FAILED\n" "$FAIL_COUNT"
    printf "========================================\n"
    return 1
  fi
  printf "ALL PASSED\n"
  printf "========================================\n"
}

main() {
  printf "Stage 5 FCM Token RLS Verification\n"
  printf "API: %s\n" "$API_URL"

  trap 'printf "\n== Emergency cleanup ==\n"; cleanup_test_data' EXIT

  load_and_sign_in
  preflight
  test_owner_can_update_own_token
  test_owner_cannot_update_other_token
  cleanup_test_data

  trap - EXIT
  print_summary
}

main "$@"
