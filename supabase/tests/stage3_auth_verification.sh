#!/usr/bin/env bash
set -euo pipefail

# Stage 3 Auth Verification — Email/Password Lifecycle
#
# Exercises the complete email/password auth lifecycle against the Supabase
# Auth API and verifies the Stage 2 profile-creation trigger fires correctly.
#
# Usage:
#   ./supabase/tests/stage3_auth_verification.sh
#
# Requirements: curl, jq, and either psql or docker (docker fallback is local-only;
# hosted verification requires psql plus `SUPABASE_DB_URL`)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_auth_helpers.sh
source "${SCRIPT_DIR}/_auth_helpers.sh"

# Unique test emails to avoid collisions across concurrent runs
RUN_ID="$(date +%s)-$$-$RANDOM"
TEST_EMAIL_1="stage3-user1-${RUN_ID}@test.local"
TEST_EMAIL_2="stage3-user2-${RUN_ID}@test.local"
TEST_PASSWORD="Stage3TestPass!42"

# ---------------------------------------------------------------------------
# Counters and test helpers
# ---------------------------------------------------------------------------

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

assert_http_status_in() {
  local status="$1" label="$2"
  shift 2

  local expected
  for expected in "$@"; do
    if [ "$status" = "$expected" ]; then
      pass "$label"
      return
    fi
  done

  fail "$label (expected one of '$*', got HTTP ${status})"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

# TODO: Document preflight.
preflight() {
  printf "\n== Pre-flight ==\n"

  require_auth_test_commands
  pass "required commands available (curl, jq, ${DB_METHOD})"

  # Verify DB connectivity
  local db_check
  db_check=$(db_query "SELECT 1;" 2>/dev/null || echo "")
  assert_eq "$db_check" "1" "database reachable via ${DB_METHOD}"

  local health_status
  health_status=$(auth_health_status)
  assert_http_ok "$health_status" "Auth service reachable at ${AUTH_URL}/health"

  local profile_table_exists
  profile_table_exists=$(db_query "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='profiles');")
  assert_eq "$profile_table_exists" "t" "public.profiles table exists"

  local trigger_exists
  trigger_exists=$(db_query "SELECT EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name='on_auth_user_created');")
  assert_eq "$trigger_exists" "t" "on_auth_user_created trigger exists"

  BASELINE_PROFILE_COUNT=$(db_query "SELECT count(*) FROM public.profiles;")
  assert_not_empty "$BASELINE_PROFILE_COUNT" "baseline profile count captured"
}

# ---------------------------------------------------------------------------
# Test 1: Sign up creates auth user + profile
# ---------------------------------------------------------------------------

# TODO: Document test_signup_creates_user_and_profile.
test_signup_creates_user_and_profile() {
  printf "\n== Test 1: Sign-up creates auth user + profile ==\n"

  local response
  response=$(signup_email_password "$TEST_EMAIL_1" "$TEST_PASSWORD")
  split_http_response "$response"

  assert_http_ok "$RESPONSE_STATUS" "sign-up returns 2xx"

  USER1_ID=$(json_field "$RESPONSE_BODY" '.id // .user.id // empty')
  assert_not_empty "$USER1_ID" "response contains user id"

  USER1_ACCESS=$(json_field "$RESPONSE_BODY" '.access_token // empty')
  assert_not_empty "$USER1_ACCESS" "response contains access_token"

  USER1_REFRESH=$(json_field "$RESPONSE_BODY" '.refresh_token // empty')
  assert_not_empty "$USER1_REFRESH" "response contains refresh_token"

  # Verify profile trigger fired
  local profile_count
  profile_count=$(db_query "SELECT count(*) FROM public.profiles WHERE id = '${USER1_ID}';")
  assert_eq "$profile_count" "1" "trigger created exactly one profiles row"

  # Verify profile defaults
  local preferred_units
  preferred_units=$(db_query "SELECT preferred_units FROM public.profiles WHERE id = '${USER1_ID}';")
  assert_eq "$preferred_units" "metric" "profile default preferred_units is metric"

  local default_visibility
  default_visibility=$(db_query "SELECT default_activity_visibility FROM public.profiles WHERE id = '${USER1_ID}';")
  assert_eq "$default_visibility" "public" "profile default visibility is public"
}

# ---------------------------------------------------------------------------
# Test 2: Sign in returns valid session
# ---------------------------------------------------------------------------

# TODO: Document test_signin_returns_session.
test_signin_returns_session() {
  printf "\n== Test 2: Sign-in returns valid session ==\n"

  local response
  response=$(signin_email_password "$TEST_EMAIL_1" "$TEST_PASSWORD")
  split_http_response "$response"

  assert_http_ok "$RESPONSE_STATUS" "sign-in returns 2xx"

  local access_token
  access_token=$(json_field "$RESPONSE_BODY" '.access_token // empty')
  assert_not_empty "$access_token" "sign-in returns access_token"

  local refresh_token
  refresh_token=$(json_field "$RESPONSE_BODY" '.refresh_token // empty')
  assert_not_empty "$refresh_token" "sign-in returns refresh_token"

  local token_user_id
  token_user_id=$(json_field "$RESPONSE_BODY" '.user.id // empty')
  assert_eq "$token_user_id" "$USER1_ID" "sign-in user id matches sign-up user id"

  # Store for subsequent tests
  USER1_ACCESS="$access_token"
  USER1_REFRESH="$refresh_token"
}

# ---------------------------------------------------------------------------
# Test 3: Token refresh works
# ---------------------------------------------------------------------------

# TODO: Document test_token_refresh.
test_token_refresh() {
  printf "\n== Test 3: Token refresh ==\n"

  local response
  response=$(http_post_json "${AUTH_URL}/token?grant_type=refresh_token" \
    "{\"refresh_token\":\"${USER1_REFRESH}\"}" \
    -H "apikey: ${ANON_KEY}")
  split_http_response "$response"

  assert_http_ok "$RESPONSE_STATUS" "refresh returns 2xx"

  local new_access
  new_access=$(json_field "$RESPONSE_BODY" '.access_token // empty')
  assert_not_empty "$new_access" "refresh returns new access_token"

  local new_refresh
  new_refresh=$(json_field "$RESPONSE_BODY" '.refresh_token // empty')
  assert_not_empty "$new_refresh" "refresh returns new refresh_token (rotation enabled)"

  # Update tokens for sign-out test
  USER1_ACCESS="$new_access"
  USER1_REFRESH="$new_refresh"
}

# ---------------------------------------------------------------------------
# Test 4: Sign out invalidates session
# ---------------------------------------------------------------------------

# TODO: Document test_signout_invalidates_session.
test_signout_invalidates_session() {
  printf "\n== Test 4: Sign-out invalidates session ==\n"

  local signout_status
  signout_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${AUTH_URL}/logout" \
    -H "Authorization: Bearer ${USER1_ACCESS}" \
    -H "apikey: ${ANON_KEY}" || echo "000")

  assert_http_ok "$signout_status" "sign-out returns 2xx"

  # Stale refresh token should be rejected
  local stale_status
  stale_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${AUTH_URL}/token?grant_type=refresh_token" \
    -H "Content-Type: application/json" \
    -H "apikey: ${ANON_KEY}" \
    -d "{\"refresh_token\":\"${USER1_REFRESH}\"}")

  assert_http_error "$stale_status" "stale refresh token rejected after sign-out"
}

# ---------------------------------------------------------------------------
# Test 5: Duplicate sign-up with same email is rejected
# ---------------------------------------------------------------------------

# TODO: Document test_duplicate_signup_rejected.
test_duplicate_signup_rejected() {
  printf "\n== Test 5: Duplicate sign-up rejected ==\n"

  local response
  response=$(signup_email_password "$TEST_EMAIL_1" "$TEST_PASSWORD")
  split_http_response "$response"

  assert_http_status_in "$RESPONSE_STATUS" \
    "duplicate sign-up returns an expected duplicate-safe status" 200 400 422

  local duplicate_access
  duplicate_access=$(json_field "$RESPONSE_BODY" '.access_token // empty')
  assert_eq "$duplicate_access" "" "duplicate sign-up does not issue an access token"

  local duplicate_refresh
  duplicate_refresh=$(json_field "$RESPONSE_BODY" '.refresh_token // empty')
  assert_eq "$duplicate_refresh" "" "duplicate sign-up does not issue a refresh token"

  local auth_user_count
  auth_user_count=$(db_query "SELECT count(*) FROM auth.users WHERE email = '${TEST_EMAIL_1}';")
  assert_eq "$auth_user_count" "1" "exactly one auth user exists for test email"

  local profile_count
  profile_count=$(db_query "SELECT count(*) FROM public.profiles WHERE id = '${USER1_ID}';")
  assert_eq "$profile_count" "1" "no duplicate profile created for same email"

  local total_profiles_for_email
  total_profiles_for_email=$(db_query "
    SELECT count(*) FROM public.profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE u.email = '${TEST_EMAIL_1}';
  ")
  assert_eq "$total_profiles_for_email" "1" "exactly one profile exists for test email"
}

# ---------------------------------------------------------------------------
# Test 6: Second user gets independent profile
# ---------------------------------------------------------------------------

# TODO: Document test_second_user_independent_profile.
test_second_user_independent_profile() {
  printf "\n== Test 6: Second user gets independent profile ==\n"

  local response
  response=$(signup_email_password "$TEST_EMAIL_2" "$TEST_PASSWORD")
  split_http_response "$response"

  assert_http_ok "$RESPONSE_STATUS" "second user sign-up returns 2xx"

  USER2_ID=$(json_field "$RESPONSE_BODY" '.id // .user.id // empty')
  assert_not_empty "$USER2_ID" "second user has an id"

  if [ "$USER2_ID" != "$USER1_ID" ]; then
    pass "second user id differs from first user id"
  else
    fail "second user id differs from first user id (both were '${USER1_ID}')"
  fi

  local profile_count
  profile_count=$(db_query "SELECT count(*) FROM public.profiles WHERE id = '${USER2_ID}';")
  assert_eq "$profile_count" "1" "second user has exactly one profile"

  local total_profiles
  local expected_total_profiles
  total_profiles=$(db_query "SELECT count(*) FROM public.profiles;")
  expected_total_profiles=$((BASELINE_PROFILE_COUNT + 2))
  assert_eq "$total_profiles" "$expected_total_profiles" "profile count increased by 2 from baseline"
}

# ---------------------------------------------------------------------------
# Test 7: Admin API fetches the created users directly
# ---------------------------------------------------------------------------

assert_admin_user_lookup() {
  local user_id="$1" expected_email="$2" label="$3"

  local response
  response=$(http_get "${AUTH_URL}/admin/users/${user_id}" \
    -H "Authorization: Bearer ${SERVICE_KEY}" \
    -H "apikey: ${SERVICE_KEY}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "$label returns 2xx"

  local lookup_email
  lookup_email=$(json_field "$RESPONSE_BODY" '.email // empty')
  assert_eq "$lookup_email" "$expected_email" "$label returns expected email"
}

test_admin_user_lookup() {
  printf "\n== Test 7: Admin API fetches both test users ==\n"

  assert_admin_user_lookup "$USER1_ID" "$TEST_EMAIL_1" "admin lookup for first user"
  assert_admin_user_lookup "$USER2_ID" "$TEST_EMAIL_2" "admin lookup for second user"
}

# ---------------------------------------------------------------------------
# Cleanup and summary
# ---------------------------------------------------------------------------

run_cleanup() {
  printf "\n== Cleanup ==\n"
  delete_auth_user "${USER1_ID:-}"
  delete_auth_user "${USER2_ID:-}"

  # Verify cascade deleted profiles
  local remaining
  remaining=$(db_query "
    SELECT count(*) FROM public.profiles
    WHERE id IN ('${USER1_ID:-00000000-0000-0000-0000-000000000000}',
                 '${USER2_ID:-00000000-0000-0000-0000-000000000000}');
  ")
  assert_eq "$remaining" "0" "cleanup: test profiles cascade-deleted"
}

print_summary() {
  printf "\n========================================\n"
  printf "Stage 3 Auth Verification: %d/%d passed\n" "$PASS_COUNT" "$TOTAL_COUNT"
  if [ "$FAIL_COUNT" -gt 0 ]; then
    printf "%d FAILED\n" "$FAIL_COUNT"
    printf "========================================\n"
    return 1
  fi
  printf "ALL PASSED\n"
  printf "========================================\n"
  return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# TODO: Document main.
main() {
  printf "Stage 3 Auth Verification\n"
  printf "API: %s\n" "$API_URL"
  printf "Test emails: %s, %s\n" "$TEST_EMAIL_1" "$TEST_EMAIL_2"

  # Initialize user id variables
  USER1_ID=""
  USER1_ACCESS=""
  USER1_REFRESH=""
  USER2_ID=""

  # Ensure test users are cleaned up on unexpected exit (e.g. db_query failure
  # under set -e). The trap runs run_cleanup only if at least one user was created.
  trap 'if [ -n "${USER1_ID:-}" ] || [ -n "${USER2_ID:-}" ]; then printf "\n== Emergency cleanup (unexpected exit) ==\n"; delete_auth_user "${USER1_ID:-}"; delete_auth_user "${USER2_ID:-}"; fi' EXIT

  preflight
  test_signup_creates_user_and_profile
  test_signin_returns_session
  test_token_refresh
  test_signout_invalidates_session
  test_duplicate_signup_rejected
  test_second_user_independent_profile
  test_admin_user_lookup
  run_cleanup
  # Disarm the emergency cleanup trap — run_cleanup already deleted the users
  trap - EXIT
  print_summary
}

main "$@"
