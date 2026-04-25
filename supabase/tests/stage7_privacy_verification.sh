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

rpc_call() {
  local fn_name="$1" payload="$2" token="$3"
  http_post_json "${REST_URL}/rpc/${fn_name}" "$payload" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${token}"
}

rpc_call_anon() {
  local fn_name="$1" payload="$2"
  http_post_json "${REST_URL}/rpc/${fn_name}" "$payload" \
    -H "apikey: ${ANON_KEY}"
}

edge_function_call() {
  local fn_name="$1" token="$2" payload="${3:-{}}"
  http_post_json "${API_URL}/functions/v1/${fn_name}" "$payload" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${token}"
}

create_temp_jpeg() {
  local path
  path=$(mktemp)
  printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\xff\xd9' > "$path"
  printf '%s' "$path"
}

OWNER_ID="" OWNER_TOKEN="" OTHER_ID="" OTHER_TOKEN=""
PENDING_ID="" PENDING_TOKEN="" UNRELATED_ID="" UNRELATED_TOKEN=""
PUBLIC_ACTIVITY_ID="" PRIVATE_ACTIVITY_ID="" FOLLOWERS_ACTIVITY_ID="" PRIVACY_ZONE_ID=""
OWNER_AVATAR_PATH="" OWNER_PHOTO_PATH=""
ACCEPTED_FOLLOW_ID="" PENDING_FOLLOW_ID=""
DELETE_USER_ID="" DELETE_TOKEN="" DELETE_AVATAR_PATH="" DELETE_PHOTO_PATH=""
PARTIAL_USER_ID="" VICTIM_USER_ID="" ATTACKER_USER_ID=""
load_and_sign_in() {
  printf "\n== Load principals and sign in ==\n"
  local response pending_email unrelated_email
  sign_in_test_principal_pair "$PRINCIPALS_FILE"
  OWNER_ID="$SIGNED_IN_OWNER_ID"
  OWNER_TOKEN="$SIGNED_IN_OWNER_TOKEN"
  OTHER_ID="$SIGNED_IN_OTHER_ID"
  OTHER_TOKEN="$SIGNED_IN_OTHER_TOKEN"

  pending_email="s7-pending-${RUN_ID}@test.local"
  response=$(signup_email_password "$pending_email" "PendingUser!42")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "pending requester sign-up succeeds"
  PENDING_ID=$(json_field "$RESPONSE_BODY" '.id // .user.id // empty')
  assert_not_empty "$PENDING_ID" "pending requester user id obtained"
  response=$(signin_email_password "$pending_email" "PendingUser!42")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "pending requester sign-in succeeds"
  PENDING_TOKEN=$(json_field "$RESPONSE_BODY" '.access_token')
  assert_not_empty "$PENDING_TOKEN" "pending requester access token obtained"

  unrelated_email="s7-unrelated-${RUN_ID}@test.local"
  response=$(signup_email_password "$unrelated_email" "UnrelatedUser!42")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "unrelated viewer sign-up succeeds"
  UNRELATED_ID=$(json_field "$RESPONSE_BODY" '.id // .user.id // empty')
  assert_not_empty "$UNRELATED_ID" "unrelated viewer user id obtained"
  response=$(signin_email_password "$unrelated_email" "UnrelatedUser!42")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "unrelated viewer sign-in succeeds"
  UNRELATED_TOKEN=$(json_field "$RESPONSE_BODY" '.access_token')
  assert_not_empty "$UNRELATED_TOKEN" "unrelated viewer access token obtained"
}

preflight() {
  printf "\n== Preflight: Stage 7 schema ==\n"
  require_auth_test_commands
  local db_check
  db_check=$(db_query "SELECT 1;" 2>/dev/null || echo "")
  assert_eq "$db_check" "1" "database reachable"
  local pz_rls
  pz_rls=$(db_query "
    SELECT rowsecurity FROM pg_tables
    WHERE schemaname = 'public' AND tablename = 'privacy_zones';
  ")
  assert_eq "$pz_rls" "t" "privacy_zones table exists with RLS"

  local pz_policy_count
  pz_policy_count=$(db_query "
    SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'privacy_zones';
  ")
  assert_eq "$pz_policy_count" "4" "4 RLS policies on privacy_zones"

  local tp_own_policy
  tp_own_policy=$(db_query "
    SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'track_points'
      AND policyname = 'track_points_select_own';
  ")
  assert_eq "$tp_own_policy" "1" "track_points_select_own policy exists"

  local tp_old_policy
  tp_old_policy=$(db_query "
    SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'track_points'
      AND policyname = 'track_points_select_via_activity';
  ")
  assert_eq "$tp_old_policy" "0" "old track_points_select_via_activity removed"

  local consent_table_rls
  consent_table_rls=$(db_query "
    SELECT rowsecurity FROM pg_tables
    WHERE schemaname = 'public' AND tablename = 'profile_consent';
  ")
  assert_eq "$consent_table_rls" "t" "profile_consent table exists with RLS"

  local consent_cols
  consent_cols=$(db_query "
    SELECT count(*) FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profile_consent'
      AND column_name IN ('terms_accepted_at', 'terms_version');
  ")
  assert_eq "$consent_cols" "2" "consent fields exist on profile_consent"

  local fn_export
  fn_export=$(db_query "
    SELECT count(*) FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'export_my_data';
  ")
  assert_eq "$fn_export" "1" "export_my_data function exists"

  local fn_rpc
  fn_rpc=$(db_query "
    SELECT count(*) FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'read_activity_track_points';
  ")
  assert_eq "$fn_rpc" "1" "read_activity_track_points function exists"
}

seed_test_data() {
  printf "\n== Seed test data ==\n"
  local response tiny_jpg
  response=$(rest_insert_service "profile_consent" \
    "{\"user_id\":\"${OWNER_ID}\",\"terms_accepted_at\":\"2026-03-14T07:55:00Z\",\"terms_version\":\"2026-03-14\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: owner consent row"

  response=$(rest_insert_service "activities" \
    "{\"user_id\":\"${OWNER_ID}\",\"sport_type\":\"run\",\"started_at\":\"2026-03-14T08:00:00Z\",\"distance_meters\":5000,\"duration_seconds\":1500,\"visibility\":\"public\",\"title\":\"S7 Public Run ${RUN_ID}\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: public activity"
  PUBLIC_ACTIVITY_ID=$(json_field "$RESPONSE_BODY" '.[0].id')

  response=$(rest_insert_service "activities" \
    "{\"user_id\":\"${OWNER_ID}\",\"sport_type\":\"ride\",\"started_at\":\"2026-03-14T09:00:00Z\",\"distance_meters\":20000,\"duration_seconds\":3600,\"visibility\":\"private\",\"title\":\"S7 Private Ride ${RUN_ID}\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: private activity"
  PRIVATE_ACTIVITY_ID=$(json_field "$RESPONSE_BODY" '.[0].id')

  response=$(rest_insert_service "activities" \
    "{\"user_id\":\"${OWNER_ID}\",\"sport_type\":\"run\",\"started_at\":\"2026-03-14T10:00:00Z\",\"distance_meters\":3500,\"duration_seconds\":980,\"visibility\":\"followers\",\"title\":\"S7 Followers Run ${RUN_ID}\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: followers activity"
  FOLLOWERS_ACTIVITY_ID=$(json_field "$RESPONSE_BODY" '.[0].id')

  response=$(rest_insert_service "track_points" \
    "[{\"activity_id\":\"${PUBLIC_ACTIVITY_ID}\",\"timestamp\":\"2026-03-14T08:00:01Z\",\"latitude\":37.7750,\"longitude\":-122.4195,\"elevation\":10},{\"activity_id\":\"${PUBLIC_ACTIVITY_ID}\",\"timestamp\":\"2026-03-14T08:00:06Z\",\"latitude\":37.7800,\"longitude\":-122.4100,\"elevation\":15}]")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: track points for public activity"

  response=$(rest_insert_service "track_points" \
    "{\"activity_id\":\"${PRIVATE_ACTIVITY_ID}\",\"timestamp\":\"2026-03-14T09:00:01Z\",\"latitude\":37.7751,\"longitude\":-122.4196}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: track point for private activity"

  response=$(rest_insert_service "track_points" \
    "[{\"activity_id\":\"${FOLLOWERS_ACTIVITY_ID}\",\"timestamp\":\"2026-03-14T10:00:01Z\",\"latitude\":37.7740,\"longitude\":-122.4180,\"elevation\":12},{\"activity_id\":\"${FOLLOWERS_ACTIVITY_ID}\",\"timestamp\":\"2026-03-14T10:00:06Z\",\"latitude\":37.7745,\"longitude\":-122.4175,\"elevation\":14}]")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: track points for followers activity"

  response=$(rest_insert_service "splits" \
    "{\"activity_id\":\"${PUBLIC_ACTIVITY_ID}\",\"split_number\":1,\"distance_meters\":1000,\"duration_seconds\":300}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: split for public activity"

  tiny_jpg=$(create_temp_jpeg)
  OWNER_AVATAR_PATH="${OWNER_ID}/export-avatar-${RUN_ID}.jpg"
  response=$(storage_upload "avatars" "$OWNER_AVATAR_PATH" "$tiny_jpg" "image/jpeg" "$OWNER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: owner avatar for export"
  OWNER_PHOTO_PATH="${OWNER_ID}/${PUBLIC_ACTIVITY_ID}/export-photo-${RUN_ID}.jpg"
  response=$(storage_upload "activity-photos" "$OWNER_PHOTO_PATH" "$tiny_jpg" "image/jpeg" "$OWNER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: owner activity photo for export"
  rm -f "$tiny_jpg"

  response=$(rest_insert_service "follows" \
    "{\"follower_id\":\"${OTHER_ID}\",\"following_id\":\"${OWNER_ID}\",\"status\":\"accepted\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: accepted follower relationship"
  ACCEPTED_FOLLOW_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$ACCEPTED_FOLLOW_ID" "seed: accepted follower relationship id obtained"

  response=$(rest_insert_service "follows" \
    "{\"follower_id\":\"${PENDING_ID}\",\"following_id\":\"${OWNER_ID}\",\"status\":\"pending\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: pending follower relationship"
  PENDING_FOLLOW_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$PENDING_FOLLOW_ID" "seed: pending follower relationship id obtained"
}

test_privacy_zone_crud() {
  printf "\n== Privacy zone CRUD ==\n"
  local response
  response=$(rest_insert "privacy_zones" \
    "{\"user_id\":\"${OWNER_ID}\",\"label\":\"Home\",\"latitude\":37.7749,\"longitude\":-122.4194,\"radius_meters\":200}" "$OWNER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "owner creates privacy zone"
  PRIVACY_ZONE_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$PRIVACY_ZONE_ID" "privacy zone id obtained"

  response=$(rest_select "privacy_zones" "$OWNER_TOKEN" "id=eq.${PRIVACY_ZONE_ID}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "owner reads privacy zone status"
  assert_row_count "$RESPONSE_BODY" "1" "owner reads own privacy zone"

  response=$(rest_select "privacy_zones" "$OTHER_TOKEN" "id=eq.${PRIVACY_ZONE_ID}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "other reads privacy zone status"
  assert_row_count "$RESPONSE_BODY" "0" "other cannot read owner's privacy zone"

  response=$(rest_insert "privacy_zones" \
    "{\"user_id\":\"${OWNER_ID}\",\"label\":\"Hacked\",\"latitude\":0,\"longitude\":0}" "$OTHER_TOKEN")
  split_http_response "$response"
  assert_http_error "$RESPONSE_STATUS" "other cannot create zone for owner"

  response=$(rest_update "privacy_zones" "id=eq.${PRIVACY_ZONE_ID}" \
    "{\"label\":\"Home Updated\"}" "$OWNER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "owner updates privacy zone"

  response=$(rest_insert "privacy_zones" \
    "{\"user_id\":\"${OWNER_ID}\",\"label\":\"Bad\",\"latitude\":0,\"longitude\":0,\"radius_meters\":0}" "$OWNER_TOKEN")
  split_http_response "$response"
  assert_http_error "$RESPONSE_STATUS" "radius_meters check rejects 0"
}

test_track_points_direct_access() {
  printf "\n== Track points direct access (owner-only) ==\n"
  local response
  response=$(rest_select "track_points" "$OWNER_TOKEN" \
    "activity_id=eq.${PUBLIC_ACTIVITY_ID}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "owner reads raw track_points status"
  assert_row_count "$RESPONSE_BODY" "2" "owner reads 2 raw track_points"

  response=$(rest_select "track_points" "$OTHER_TOKEN" \
    "activity_id=eq.${PUBLIC_ACTIVITY_ID}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "other raw track_points status"
  assert_row_count "$RESPONSE_BODY" "0" "other gets 0 raw track_points"

  response=$(rest_select "track_points" "$OTHER_TOKEN" \
    "activity_id=eq.${FOLLOWERS_ACTIVITY_ID}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "accepted follower raw track_points status"
  assert_row_count "$RESPONSE_BODY" "0" "accepted follower gets 0 raw track_points for followers activity"

  response=$(rest_select "track_points" "$PENDING_TOKEN" \
    "activity_id=eq.${FOLLOWERS_ACTIVITY_ID}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "pending requester raw track_points status"
  assert_row_count "$RESPONSE_BODY" "0" "pending requester gets 0 raw track_points for followers activity"

  response=$(rest_select "track_points" "$UNRELATED_TOKEN" \
    "activity_id=eq.${FOLLOWERS_ACTIVITY_ID}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "unrelated raw track_points status"
  assert_row_count "$RESPONSE_BODY" "0" "unrelated viewer gets 0 raw track_points for followers activity"
}

test_masked_rpc() {
  printf "\n== Masked RPC read path ==\n"
  local response
  response=$(rpc_call "read_activity_track_points" \
    "{\"p_activity_id\":\"${PUBLIC_ACTIVITY_ID}\"}" "$OWNER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "owner RPC call status"
  assert_row_count "$RESPONSE_BODY" "2" "owner sees 2 points via RPC"

  local owner_lat
  owner_lat=$(json_field "$RESPONSE_BODY" '.[0].latitude')
  assert_not_empty "$owner_lat" "owner sees real latitude via RPC"

  response=$(rpc_call "read_activity_track_points" \
    "{\"p_activity_id\":\"${PUBLIC_ACTIVITY_ID}\"}" "$OTHER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "other RPC call status"
  assert_row_count "$RESPONSE_BODY" "2" "other sees 2 points via RPC"

  local masked_lat
  masked_lat=$(json_field "$RESPONSE_BODY" '.[0].latitude // "NULL"')
  assert_eq "$masked_lat" "NULL" "point inside zone has null latitude"

  local unmasked_lat
  unmasked_lat=$(json_field "$RESPONSE_BODY" '.[1].latitude')
  assert_not_empty "$unmasked_lat" "point outside zone has real latitude"

  response=$(rpc_call "read_activity_track_points" \
    "{\"p_activity_id\":\"${PRIVATE_ACTIVITY_ID}\"}" "$OTHER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "other private RPC call status"
  assert_row_count "$RESPONSE_BODY" "0" "other sees 0 points for private activity"

  response=$(rpc_call "read_activity_track_points" \
    "{\"p_activity_id\":\"${FOLLOWERS_ACTIVITY_ID}\"}" "$OTHER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "accepted follower followers RPC call status"
  assert_row_count "$RESPONSE_BODY" "2" "accepted follower sees followers activity points via RPC"

  response=$(rpc_call "read_activity_track_points" \
    "{\"p_activity_id\":\"${FOLLOWERS_ACTIVITY_ID}\"}" "$PENDING_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "pending requester followers RPC call status"
  assert_row_count "$RESPONSE_BODY" "0" "pending requester cannot read followers activity points via RPC"

  response=$(rpc_call "read_activity_track_points" \
    "{\"p_activity_id\":\"${FOLLOWERS_ACTIVITY_ID}\"}" "$UNRELATED_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "unrelated viewer followers RPC call status"
  assert_row_count "$RESPONSE_BODY" "0" "unrelated viewer cannot read followers activity points via RPC"

  response=$(rpc_call_anon "read_activity_track_points" \
    "{\"p_activity_id\":\"${PUBLIC_ACTIVITY_ID}\"}")
  split_http_response "$response"
  assert_http_error "$RESPONSE_STATUS" "anon cannot call RPC"
}

test_consent_field_visibility() {
  printf "\n== Consent field visibility ==\n"
  local response

  response=$(rest_select "profiles" "$OTHER_TOKEN" "id=eq.${OWNER_ID}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "other profile read status"
  assert_row_count "$RESPONSE_BODY" "1" "other can still read owner's public profile row"

  local other_has_terms other_has_terms_version
  other_has_terms=$(json_field "$RESPONSE_BODY" '.[0] | has("terms_accepted_at")')
  assert_eq "$other_has_terms" "false" "other cannot read owner's terms_accepted_at"
  other_has_terms_version=$(json_field "$RESPONSE_BODY" '.[0] | has("terms_version")')
  assert_eq "$other_has_terms_version" "false" "other cannot read owner's terms_version"

  response=$(rest_select "profiles" "$OWNER_TOKEN" "id=eq.${OWNER_ID}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "owner direct profile read status"
  local owner_has_terms owner_has_terms_version
  owner_has_terms=$(json_field "$RESPONSE_BODY" '.[0] | has("terms_accepted_at")')
  assert_eq "$owner_has_terms" "false" "owner direct profile read omits terms_accepted_at"
  owner_has_terms_version=$(json_field "$RESPONSE_BODY" '.[0] | has("terms_version")')
  assert_eq "$owner_has_terms_version" "false" "owner direct profile read omits terms_version"

  response=$(rest_select "profile_consent" "$OWNER_TOKEN" "user_id=eq.${OWNER_ID}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "owner consent read status"
  assert_row_count "$RESPONSE_BODY" "1" "owner can read own consent row"

  response=$(rest_select "profile_consent" "$OTHER_TOKEN" "user_id=eq.${OWNER_ID}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "other consent read status"
  assert_row_count "$RESPONSE_BODY" "0" "other cannot read owner's consent row"
}

test_export() {
  printf "\n== Self-service export ==\n"
  local response
  response=$(rpc_call "export_my_data" "{}" "$OWNER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "export_my_data call status"

  local profile_id
  profile_id=$(json_field "$RESPONSE_BODY" '.profile.id')
  assert_eq "$profile_id" "$OWNER_ID" "export contains caller's profile"

  local export_has_terms export_has_terms_version
  export_has_terms=$(json_field "$RESPONSE_BODY" '.profile | has("terms_accepted_at")')
  assert_eq "$export_has_terms" "true" "export retains terms_accepted_at for owner"
  export_has_terms_version=$(json_field "$RESPONSE_BODY" '.profile | has("terms_version")')
  assert_eq "$export_has_terms_version" "true" "export retains terms_version for owner"
  local export_terms_version
  export_terms_version=$(json_field "$RESPONSE_BODY" '.profile.terms_version')
  assert_eq "$export_terms_version" "2026-03-14" "export contains owner consent version"

  local activity_count
  activity_count=$(json_field "$RESPONSE_BODY" '.activities | length')
  if [ "$activity_count" -ge 2 ]; then
    pass "export contains activities (got ${activity_count})"
  else
    fail "export contains activities (expected >=2, got ${activity_count})"
  fi

  local tp_count
  tp_count=$(json_field "$RESPONSE_BODY" '.activities[0].track_points | length')
  if [ "$tp_count" -ge 1 ]; then
    pass "export contains nested track_points (got ${tp_count})"
  else
    fail "export contains nested track_points (expected >=1, got ${tp_count})"
  fi

  local pz_count
  pz_count=$(json_field "$RESPONSE_BODY" '.privacy_zones | length')
  if [ "$pz_count" -ge 1 ]; then
    pass "export contains privacy_zones (got ${pz_count})"
  else
    fail "export contains privacy_zones (expected >=1, got ${pz_count})"
  fi

  local storage_matches
  storage_matches=$(json_field "$RESPONSE_BODY" ".storage_objects | map(select((.bucket == \"avatars\" and .path == \"${OWNER_AVATAR_PATH}\") or (.bucket == \"activity-photos\" and .path == \"${OWNER_PHOTO_PATH}\"))) | length")
  assert_eq "$storage_matches" "2" "export contains seeded storage object paths"

  response=$(rpc_call "export_my_data" "{}" "$OTHER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "other export call status"
  local other_profile_id
  other_profile_id=$(json_field "$RESPONSE_BODY" '.profile.id')
  assert_eq "$other_profile_id" "$OTHER_ID" "other export contains only their profile"

  response=$(rpc_call_anon "export_my_data" "{}")
  split_http_response "$response"
  assert_http_error "$RESPONSE_STATUS" "anon cannot call export_my_data"
}

test_account_deletion() {
  printf "\n== Account deletion ==\n"
  local response tiny_jpg attacker_token
  local delete_email="s7-delete-${RUN_ID}@test.local"
  response=$(signup_email_password "$delete_email" "DeleteMe!42")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "delete test: sign-up"
  DELETE_USER_ID=$(json_field "$RESPONSE_BODY" '.id // .user.id // empty')
  assert_not_empty "$DELETE_USER_ID" "delete test: user id obtained"
  response=$(signin_email_password "$delete_email" "DeleteMe!42")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "delete test: sign-in"
  DELETE_TOKEN=$(json_field "$RESPONSE_BODY" '.access_token')

  response=$(rest_insert_service "activities" \
    "{\"user_id\":\"${DELETE_USER_ID}\",\"sport_type\":\"run\",\"started_at\":\"2026-03-14T16:00:00Z\",\"distance_meters\":1000,\"duration_seconds\":300,\"visibility\":\"public\",\"title\":\"Delete Test ${RUN_ID}\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "delete test: activity seeded"
  local delete_activity_id
  delete_activity_id=$(json_field "$RESPONSE_BODY" '.[0].id')

  response=$(rest_insert_service "track_points" \
    "{\"activity_id\":\"${delete_activity_id}\",\"timestamp\":\"2026-03-14T16:00:01Z\",\"latitude\":37.7749,\"longitude\":-122.4194}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "delete test: track point seeded"

  tiny_jpg=$(create_temp_jpeg)
  DELETE_AVATAR_PATH="${DELETE_USER_ID}/delete-avatar-${RUN_ID}.jpg"
  response=$(storage_upload "avatars" "$DELETE_AVATAR_PATH" "$tiny_jpg" "image/jpeg" "$DELETE_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "delete test: avatar seeded"
  DELETE_PHOTO_PATH="${DELETE_USER_ID}/${delete_activity_id}/delete-photo-${RUN_ID}.jpg"
  response=$(storage_upload "activity-photos" "$DELETE_PHOTO_PATH" "$tiny_jpg" "image/jpeg" "$DELETE_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "delete test: activity photo seeded"
  rm -f "$tiny_jpg"
  response=$(edge_function_call "delete-my-account" "$DELETE_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "delete-my-account call status"

  local auth_user_exists
  auth_user_exists=$(db_query \
    "SELECT count(*) FROM auth.users WHERE id = '${DELETE_USER_ID}';")
  assert_eq "$auth_user_exists" "0" "auth user deleted"

  local profile_exists
  profile_exists=$(db_query \
    "SELECT count(*) FROM public.profiles WHERE id = '${DELETE_USER_ID}';")
  assert_eq "$profile_exists" "0" "profile cascaded on delete"

  local activities_exist
  activities_exist=$(db_query \
    "SELECT count(*) FROM public.activities WHERE user_id = '${DELETE_USER_ID}';")
  assert_eq "$activities_exist" "0" "activities cascaded on delete"

  local tp_exist
  tp_exist=$(db_query \
    "SELECT count(*) FROM public.track_points WHERE activity_id = '${delete_activity_id}';")
  assert_eq "$tp_exist" "0" "track_points cascaded on delete"

  local avatar_objects photo_objects
  avatar_objects=$(db_query "SELECT count(*) FROM storage.objects WHERE bucket_id = 'avatars' AND name LIKE '${DELETE_USER_ID}/%';")
  assert_eq "$avatar_objects" "0" "avatars cleaned up on delete"
  photo_objects=$(db_query "SELECT count(*) FROM storage.objects WHERE bucket_id = 'activity-photos' AND name LIKE '${DELETE_USER_ID}/%';")
  assert_eq "$photo_objects" "0" "activity photos cleaned up on delete"

  response=$(signup_email_password "s7-victim-${RUN_ID}@test.local" "VictimUser!42")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "cross-user delete: victim sign-up"
  VICTIM_USER_ID=$(json_field "$RESPONSE_BODY" '.id // .user.id // empty')
  response=$(signup_email_password "s7-attacker-${RUN_ID}@test.local" "Attacker!42")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "cross-user delete: attacker sign-up"
  ATTACKER_USER_ID=$(json_field "$RESPONSE_BODY" '.id // .user.id // empty')
  response=$(signin_email_password "s7-attacker-${RUN_ID}@test.local" "Attacker!42")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "cross-user delete: attacker sign-in"
  attacker_token=$(json_field "$RESPONSE_BODY" '.access_token')
  response=$(edge_function_call "delete-my-account" "$attacker_token" "{\"target_user_id\":\"${VICTIM_USER_ID}\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "cross-user delete attempt status"
  assert_eq "$(db_query "SELECT count(*) FROM auth.users WHERE id = '${VICTIM_USER_ID}';")" "1" "cross-user delete leaves target user intact"
  assert_eq "$(db_query "SELECT count(*) FROM auth.users WHERE id = '${ATTACKER_USER_ID}';")" "0" "cross-user delete deletes caller instead"
}

test_deletion_partial_data() {
  printf "\n== Deletion with partial data ==\n"
  local response
  local partial_email="s7-partial-${RUN_ID}@test.local"
  response=$(signup_email_password "$partial_email" "PartialTest!42")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "partial delete: sign-up"
  PARTIAL_USER_ID=$(json_field "$RESPONSE_BODY" '.id // .user.id // empty')
  assert_not_empty "$PARTIAL_USER_ID" "partial delete: user id obtained"

  response=$(signin_email_password "$partial_email" "PartialTest!42")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "partial delete: sign-in"
  local partial_token
  partial_token=$(json_field "$RESPONSE_BODY" '.access_token')

  response=$(edge_function_call "delete-my-account" "$partial_token")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "partial delete succeeds"

  local partial_gone
  partial_gone=$(db_query \
    "SELECT count(*) FROM auth.users WHERE id = '${PARTIAL_USER_ID}';")
  assert_eq "$partial_gone" "0" "partial user auth row deleted"
}

cleanup_test_data() {
  printf "\n== Cleanup ==\n"
  if [ -n "${PRIVACY_ZONE_ID:-}" ]; then
    rest_delete_service "privacy_zones" "id=eq.${PRIVACY_ZONE_ID}" >/dev/null 2>&1 || true
  fi
  if [ -n "${OWNER_ID:-}" ]; then
    rest_delete_service "profile_consent" "user_id=eq.${OWNER_ID}" >/dev/null 2>&1 || true
  fi
  for fid in "${ACCEPTED_FOLLOW_ID:-}" "${PENDING_FOLLOW_ID:-}"; do
    if [ -n "$fid" ]; then
      rest_delete_service "follows" "id=eq.${fid}" >/dev/null 2>&1 || true
    fi
  done
  for aid in "${PUBLIC_ACTIVITY_ID:-}" "${PRIVATE_ACTIVITY_ID:-}" "${FOLLOWERS_ACTIVITY_ID:-}"; do
    if [ -n "$aid" ]; then
      rest_delete_service "activities" "id=eq.${aid}" >/dev/null 2>&1 || true
    fi
  done
  for target in \
    "avatars:${OWNER_AVATAR_PATH:-}" "activity-photos:${OWNER_PHOTO_PATH:-}" \
    "avatars:${DELETE_AVATAR_PATH:-}" "activity-photos:${DELETE_PHOTO_PATH:-}"; do
    [ -z "${target#*:}" ] || storage_delete_service "${target%%:*}" "{\"prefixes\":[\"${target#*:}\"]}" >/dev/null 2>&1 || true
  done
  if [ -n "${DELETE_USER_ID:-}" ]; then
    delete_auth_user "$DELETE_USER_ID"
  fi
  if [ -n "${PARTIAL_USER_ID:-}" ]; then
    delete_auth_user "$PARTIAL_USER_ID"
  fi
  if [ -n "${PENDING_ID:-}" ]; then
    delete_auth_user "$PENDING_ID"
  fi
  if [ -n "${UNRELATED_ID:-}" ]; then
    delete_auth_user "$UNRELATED_ID"
  fi
  if [ -n "${VICTIM_USER_ID:-}" ]; then
    delete_auth_user "$VICTIM_USER_ID"
  fi
  if [ -n "${ATTACKER_USER_ID:-}" ]; then
    delete_auth_user "$ATTACKER_USER_ID"
  fi
  printf "  cleanup complete\n"
}

print_summary() {
  printf "\n========================================\n"
  printf "Stage 7 Privacy Verification: %d/%d passed\n" "$PASS_COUNT" "$TOTAL_COUNT"
  if [ "$FAIL_COUNT" -gt 0 ]; then
    printf "%d FAILED\n" "$FAIL_COUNT"
    printf "========================================\n"
    return 1
  fi
  printf "ALL PASSED\n"
  printf "========================================\n"
}

main() {
  printf "Stage 7 Privacy Verification\n"
  printf "API: %s\n" "$API_URL"

  trap 'printf "\n== Emergency cleanup ==\n"; cleanup_test_data' EXIT

  load_and_sign_in
  preflight
  seed_test_data
  test_privacy_zone_crud
  test_track_points_direct_access
  test_masked_rpc
  test_consent_field_visibility
  test_export
  test_account_deletion
  test_deletion_partial_data
  cleanup_test_data

  trap - EXIT
  print_summary
}

main "$@"
