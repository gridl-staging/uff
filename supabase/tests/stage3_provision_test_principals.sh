#!/usr/bin/env bash
set -euo pipefail

# Stage 3 → Stage 4 Hand-Off: Provision Persistent Test Principals
#
# Creates two email/password auth users with known credentials and saves
# their details to a JSON file that Stage 4 RLS tests can consume.
# Unlike stage3_auth_verification.sh, this script does NOT clean up
# users — they are meant to persist across sessions.
#
# Usage:
#   ./supabase/tests/stage3_provision_test_principals.sh
#
# Output:
#   supabase/tests/stage3_test_principals.json
#
# Idempotent: if users already exist, signs in and refreshes their details.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_auth_helpers.sh
source "${SCRIPT_DIR}/_auth_helpers.sh"

OUTPUT_FILE="${SCRIPT_DIR}/stage3_test_principals.json"

# Deterministic test credentials — same across all runs
USER_A_EMAIL="rls-owner@test.local"
USER_A_PASSWORD="RlsOwnerPass!42"
USER_B_EMAIL="rls-other@test.local"
USER_B_PASSWORD="RlsOtherPass!42"

# ---------------------------------------------------------------------------
# Provision or sign in a user, returning auth user id
# ---------------------------------------------------------------------------

# TODO: Document provision_user.
provision_user() {
  local email="$1" password="$2" label="$3"

  # Try sign-up first
  local response
  response=$(signup_email_password "$email" "$password")
  split_http_response "$response"

  local user_id access_token
  user_id=$(json_field "$RESPONSE_BODY" '.id // .user.id // empty')
  access_token=$(json_field "$RESPONSE_BODY" '.access_token // empty')

  if [ -n "$user_id" ] && [ -n "$access_token" ]; then
    printf "  Created %s: %s\n" "$label" "$user_id"
    PROVISIONED_AUTH_USER_ID="$user_id"
    return 0
  fi

  # User likely exists — sign in instead
  response=$(signin_email_password "$email" "$password")
  split_http_response "$response"

  user_id=$(json_field "$RESPONSE_BODY" '.user.id // empty')
  access_token=$(json_field "$RESPONSE_BODY" '.access_token // empty')

  if [ -n "$user_id" ] && [ -n "$access_token" ]; then
    printf "  Signed in existing %s: %s\n" "$label" "$user_id"
    PROVISIONED_AUTH_USER_ID="$user_id"
    return 0
  fi

  printf "ABORT: could not provision %s (%s)\n" "$label" "$email" >&2
  printf "  Sign-up response: %s\n" "$RESPONSE_BODY" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Resolve profile id for a provisioned auth user
# ---------------------------------------------------------------------------

# TODO: Document resolve_profile_id_for_auth_user.
resolve_profile_id_for_auth_user() {
  local auth_user_id="$1" label="$2"

  local profile_count
  profile_count=$(db_query "SELECT count(*) FROM public.profiles WHERE id = '${auth_user_id}';")
  if [ "$profile_count" = "1" ]; then
    local profile_id
    profile_id=$(db_query "SELECT id FROM public.profiles WHERE id = '${auth_user_id}';")
    if [ -z "$profile_id" ]; then
      printf "ABORT: profile id query returned empty for %s (auth_user_id=%s)\n" "$label" "$auth_user_id" >&2
      return 1
    fi
    printf "  Profile verified for %s: %s\n" "$label" "$profile_id"
    PROVISIONED_PROFILE_ID="$profile_id"
  else
    printf "ABORT: no profile found for %s (auth_user_id=%s, count=%s)\n" "$label" "$auth_user_id" "$profile_count" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Write JSON output
# ---------------------------------------------------------------------------

# TODO: Document write_principals_json.
write_principals_json() {
  local user_a_auth_id="$1" user_a_profile_id="$2" user_b_auth_id="$3" user_b_profile_id="$4"

  cat > "$OUTPUT_FILE" <<EOF
{
  "generated_by": "stage3_provision_test_principals.sh",
  "target": "${API_URL}",
  "principals": {
    "owner": {
      "auth_user_id": "${user_a_auth_id}",
      "user_id": "${user_a_auth_id}",
      "profile_id": "${user_a_profile_id}",
      "email": "${USER_A_EMAIL}",
      "password": "${USER_A_PASSWORD}",
      "provider_type": "email",
      "provider": "email"
    },
    "other": {
      "auth_user_id": "${user_b_auth_id}",
      "user_id": "${user_b_auth_id}",
      "profile_id": "${user_b_profile_id}",
      "email": "${USER_B_EMAIL}",
      "password": "${USER_B_PASSWORD}",
      "provider_type": "email",
      "provider": "email"
    }
  },
  "usage": "Sign in via POST /auth/v1/token?grant_type=password to get fresh tokens for RLS testing."
}
EOF

  printf "\nPrincipals written to %s\n" "$OUTPUT_FILE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# TODO: Document main.
main() {
  printf "Stage 3 → Stage 4: Provisioning test principals\n"
  printf "API: %s\n\n" "$API_URL"

  require_auth_test_commands
  require_auth_service_health

  PROVISIONED_AUTH_USER_ID=""
  provision_user "$USER_A_EMAIL" "$USER_A_PASSWORD" "User A (owner)"
  local user_a_auth_id="$PROVISIONED_AUTH_USER_ID"

  PROVISIONED_PROFILE_ID=""
  resolve_profile_id_for_auth_user "$user_a_auth_id" "User A"
  local user_a_profile_id="$PROVISIONED_PROFILE_ID"

  PROVISIONED_AUTH_USER_ID=""
  provision_user "$USER_B_EMAIL" "$USER_B_PASSWORD" "User B (other)"
  local user_b_auth_id="$PROVISIONED_AUTH_USER_ID"

  PROVISIONED_PROFILE_ID=""
  resolve_profile_id_for_auth_user "$user_b_auth_id" "User B"
  local user_b_profile_id="$PROVISIONED_PROFILE_ID"

  if [ "$user_a_auth_id" = "$user_b_auth_id" ]; then
    printf "ABORT: both users have the same id — something went wrong\n" >&2
    exit 1
  fi

  write_principals_json "$user_a_auth_id" "$user_a_profile_id" "$user_b_auth_id" "$user_b_profile_id"

  printf "\nDone. Stage 4 can sign in as either principal to get fresh access tokens.\n"
}

main "$@"
