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

assert_select_count() {
  local table="$1" token="$2" query="$3" expected="$4" label="$5"
  local response
  response=$(rest_select "$table" "$token" "$query")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "${label} status"
  assert_row_count "$RESPONSE_BODY" "$expected" "$label"
}

assert_select_count_service() {
  local table="$1" query="$2" expected="$3" label="$4"
  local response
  response=$(rest_select_service "$table" "$query")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "${label} status"
  assert_row_count "$RESPONSE_BODY" "$expected" "$label"
}

assert_select_count_anon() {
  local table="$1" expected="$2" label="$3"
  local response
  response=$(rest_select_anon "$table")
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

assert_rejected_mutation() {
  local response="$1" label="$2"
  split_http_response "$response"
  assert_http_error "$RESPONSE_STATUS" "$label"
}

insert_comment_and_capture_id() {
  local token="$1" activity_id="$2" user_id="$3" body="$4" status_label="$5" row_label="$6" id_label="$7" id_var="$8" response comment_id
  response=$(rest_insert "comments" "{\"activity_id\":\"${activity_id}\",\"user_id\":\"${user_id}\",\"body\":\"${body}\"}" "$token")
  assert_single_row_mutation "$response" "$status_label" "$row_label"
  comment_id=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$comment_id" "$id_label"; printf -v "$id_var" '%s' "$comment_id"
}

delete_comment_and_assert_removed() {
  local comment_id="$1" token="$2" status_label="$3" row_label="$4" persistence_label="$5" response
  response=$(rest_delete "comments" "id=eq.${comment_id}" "$token")
  assert_single_row_mutation "$response" "$status_label" "$row_label"; assert_select_count_service "comments" "id=eq.${comment_id}" "0" "$persistence_label"
}

OWNER_ID="" OWNER_TOKEN="" OTHER_ID="" OTHER_TOKEN="" TRIGGER_USER_ID=""
PENDING_ID="" PENDING_TOKEN="" UNRELATED_ID="" UNRELATED_TOKEN=""
PUBLIC_ACTIVITY_ID="" PRIVATE_ACTIVITY_ID="" FOLLOWERS_ACTIVITY_ID="" TEMP_ACTIVITY_ID=""
PUBLIC_TRACK_POINT_ID="" PRIVATE_TRACK_POINT_ID="" PUBLIC_SPLIT_ID="" PRIVATE_SPLIT_ID=""
FOLLOWERS_SPLIT_ID="" PUBLIC_ACTIVITY_PHOTO_ID="" PRIVATE_ACTIVITY_PHOTO_ID="" FOLLOWERS_ACTIVITY_PHOTO_ID="" TEMP_ACTIVITY_PHOTO_ID=""
GEAR_ID="" OTHER_GEAR_ID="" TEMP_GEAR_ID=""
FOLLOWERS_STORAGE_PATH="" ACCEPTED_FOLLOW_ID="" PENDING_FOLLOW_ID=""
MUTATION_ACCEPT_FOLLOW_ID="" MUTATION_REJECT_FOLLOW_ID="" MUTATION_UNFOLLOW_FOLLOW_ID=""
OTHER_KUDOS_ID=""
PUBLIC_OWNER_COMMENT_ID="" PRIVATE_OWNER_COMMENT_ID="" FOLLOWERS_OWNER_COMMENT_ID="" PUBLIC_OTHER_COMMENT_ID=""
MUTATION_PUBLIC_COMMENT_ID="" MUTATION_PRIVATE_COMMENT_ID="" MUTATION_FOLLOWERS_COMMENT_ID=""

# TODO: Document load_and_sign_in.
load_and_sign_in() {
  printf "\n== Load principals and sign in ==\n"
  local response pending_email unrelated_email
  sign_in_test_principal_pair "$PRINCIPALS_FILE" " Run stage3_provision_test_principals.sh first."
  OWNER_ID="$SIGNED_IN_OWNER_ID"
  OWNER_TOKEN="$SIGNED_IN_OWNER_TOKEN"
  OTHER_ID="$SIGNED_IN_OTHER_ID"
  OTHER_TOKEN="$SIGNED_IN_OTHER_TOKEN"

  pending_email="s4-pending-${RUN_ID}@test.local"
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

  unrelated_email="s4-unrelated-${RUN_ID}@test.local"
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

# TODO: Document preflight.
preflight() {
  printf "\n== Preflight: RLS and policies ==\n"

  require_auth_test_commands

  local db_check
  db_check=$(db_query "SELECT 1;" 2>/dev/null || echo "")
  assert_eq "$db_check" "1" "database reachable"

  local rls_count
  rls_count=$(db_query "
    SELECT count(*) FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename IN ('profiles','gear','activities','track_points','splits','activity_photos','follows','kudos','comments')
      AND rowsecurity = true;
  ")
  assert_eq "$rls_count" "9" "RLS enabled on all 9 tables"

  # profiles(2) + gear(4) + activities(4) + track_points(3) + splits(3) + activity_photos(3) + follows(4) + kudos(3) + comments(3) = 29
  local policy_count
  policy_count=$(db_query "
    SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('profiles','gear','activities','track_points','splits','activity_photos','follows','kudos','comments');
  ")
  assert_eq "$policy_count" "29" "29 RLS policies exist"

  assert_policy_exists "profiles" "profiles_select_authenticated"
  assert_policy_exists "profiles" "profiles_update_own"
  assert_policy_exists "gear" "gear_select_own"
  assert_policy_exists "gear" "gear_insert_own"
  assert_policy_exists "gear" "gear_update_own"
  assert_policy_exists "gear" "gear_delete_own"
  assert_policy_exists "activities" "activities_select_own_or_public"
  assert_policy_exists "activities" "activities_insert_own"
  assert_policy_exists "activities" "activities_update_own"
  assert_policy_exists "activities" "activities_delete_own"
  # Stage 7 replaced track_points_select_via_activity with track_points_select_own
  assert_policy_exists "track_points" "track_points_select_own"
  assert_policy_exists "track_points" "track_points_insert_via_activity"
  assert_policy_exists "track_points" "track_points_delete_via_activity"
  assert_policy_exists "splits" "splits_select_via_activity"
  assert_policy_exists "splits" "splits_insert_via_activity"
  assert_policy_exists "splits" "splits_delete_via_activity"
  assert_policy_exists "activity_photos" "activity_photos_select_own_or_public"
  assert_policy_exists "activity_photos" "activity_photos_insert_own"
  assert_policy_exists "activity_photos" "activity_photos_delete_own"
  assert_policy_exists "follows" "follows_select_participants"
  assert_policy_exists "follows" "follows_insert_requester"
  assert_policy_exists "follows" "follows_update_following_accept"
  assert_policy_exists "follows" "follows_delete_participants"
  assert_policy_exists "kudos" "kudos_select_visible_activity"
  assert_policy_exists "kudos" "kudos_insert_visible_activity"
  assert_policy_exists "kudos" "kudos_delete_own"
  assert_policy_exists "comments" "comments_select_visible_activity"
  assert_policy_exists "comments" "comments_insert_visible_activity"
  assert_policy_exists "comments" "comments_delete_own"
}

# TODO: Document seed_test_data.
seed_test_data() {
  printf "\n== Seed test data ==\n"

  local response tiny_jpg

  response=$(rest_insert_service "gear" \
    "{\"user_id\":\"${OWNER_ID}\",\"name\":\"RLS Test Shoes\",\"gear_type\":\"shoe\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: gear inserted"
  GEAR_ID=$(json_field "$RESPONSE_BODY" '.[0].id')

  response=$(rest_insert_service "gear" \
    "{\"user_id\":\"${OTHER_ID}\",\"name\":\"RLS Other Gear\",\"gear_type\":\"bike\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: other-user gear inserted"
  OTHER_GEAR_ID=$(json_field "$RESPONSE_BODY" '.[0].id')

  response=$(rest_insert_service "activities" \
    "{\"user_id\":\"${OWNER_ID}\",\"sport_type\":\"run\",\"started_at\":\"2026-03-14T08:00:00Z\",\"distance_meters\":5000,\"duration_seconds\":1500,\"visibility\":\"public\",\"title\":\"RLS Public Run\",\"gear_id\":\"${GEAR_ID}\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: public activity inserted"
  PUBLIC_ACTIVITY_ID=$(json_field "$RESPONSE_BODY" '.[0].id')

  response=$(rest_insert_service "activities" \
    "{\"user_id\":\"${OWNER_ID}\",\"sport_type\":\"ride\",\"started_at\":\"2026-03-14T09:00:00Z\",\"distance_meters\":20000,\"duration_seconds\":3600,\"visibility\":\"private\",\"title\":\"RLS Private Ride\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: private activity inserted"
  PRIVATE_ACTIVITY_ID=$(json_field "$RESPONSE_BODY" '.[0].id')

  response=$(rest_insert_service "activities" \
    "{\"user_id\":\"${OWNER_ID}\",\"sport_type\":\"run\",\"started_at\":\"2026-03-14T10:00:00Z\",\"distance_meters\":3000,\"duration_seconds\":900,\"visibility\":\"followers\",\"title\":\"RLS Followers Run\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: followers activity inserted"
  FOLLOWERS_ACTIVITY_ID=$(json_field "$RESPONSE_BODY" '.[0].id')

  response=$(rest_insert_service "track_points" \
    "{\"activity_id\":\"${PUBLIC_ACTIVITY_ID}\",\"timestamp\":\"2026-03-14T08:00:01Z\",\"latitude\":37.7749,\"longitude\":-122.4194}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: track_point for public activity"
  PUBLIC_TRACK_POINT_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$PUBLIC_TRACK_POINT_ID" "seed: public track_point id obtained"

  response=$(rest_insert_service "track_points" \
    "{\"activity_id\":\"${PRIVATE_ACTIVITY_ID}\",\"timestamp\":\"2026-03-14T09:00:01Z\",\"latitude\":37.7750,\"longitude\":-122.4195}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: track_point for private activity"
  PRIVATE_TRACK_POINT_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$PRIVATE_TRACK_POINT_ID" "seed: private track_point id obtained"

  response=$(rest_insert_service "splits" \
    "{\"activity_id\":\"${PUBLIC_ACTIVITY_ID}\",\"split_number\":1,\"distance_meters\":1000,\"duration_seconds\":300}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: split for public activity"
  PUBLIC_SPLIT_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$PUBLIC_SPLIT_ID" "seed: public split id obtained"

  response=$(rest_insert_service "splits" \
    "{\"activity_id\":\"${PRIVATE_ACTIVITY_ID}\",\"split_number\":1,\"distance_meters\":1000,\"duration_seconds\":180}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: split for private activity"
  PRIVATE_SPLIT_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$PRIVATE_SPLIT_ID" "seed: private split id obtained"

  response=$(rest_insert_service "splits" \
    "{\"activity_id\":\"${FOLLOWERS_ACTIVITY_ID}\",\"split_number\":1,\"distance_meters\":1000,\"duration_seconds\":320}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: split for followers activity"
  FOLLOWERS_SPLIT_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$FOLLOWERS_SPLIT_ID" "seed: followers split id obtained"

  response=$(rest_insert_service "activity_photos" \
    "{\"activity_id\":\"${PUBLIC_ACTIVITY_ID}\",\"user_id\":\"${OWNER_ID}\",\"storage_path\":\"${OWNER_ID}/${PUBLIC_ACTIVITY_ID}/seed-public-${RUN_ID}.jpg\",\"thumbnail_path\":\"${OWNER_ID}/${PUBLIC_ACTIVITY_ID}/seed-public-${RUN_ID}-thumb.jpg\",\"sort_order\":0}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: activity_photo for public activity"
  PUBLIC_ACTIVITY_PHOTO_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$PUBLIC_ACTIVITY_PHOTO_ID" "seed: public activity_photo id obtained"

  response=$(rest_insert_service "activity_photos" \
    "{\"activity_id\":\"${PRIVATE_ACTIVITY_ID}\",\"user_id\":\"${OWNER_ID}\",\"storage_path\":\"${OWNER_ID}/${PRIVATE_ACTIVITY_ID}/seed-private-${RUN_ID}.jpg\",\"thumbnail_path\":null,\"sort_order\":1}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: activity_photo for private activity"
  PRIVATE_ACTIVITY_PHOTO_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$PRIVATE_ACTIVITY_PHOTO_ID" "seed: private activity_photo id obtained"

  response=$(rest_insert_service "activity_photos" \
    "{\"activity_id\":\"${FOLLOWERS_ACTIVITY_ID}\",\"user_id\":\"${OWNER_ID}\",\"storage_path\":\"${OWNER_ID}/${FOLLOWERS_ACTIVITY_ID}/seed-followers-${RUN_ID}.jpg\",\"thumbnail_path\":null,\"sort_order\":2}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: activity_photo for followers activity"
  FOLLOWERS_ACTIVITY_PHOTO_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$FOLLOWERS_ACTIVITY_PHOTO_ID" "seed: followers activity_photo id obtained"

  tiny_jpg=$(mktemp)
  printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\xff\xd9' > "$tiny_jpg"
  FOLLOWERS_STORAGE_PATH="${OWNER_ID}/${FOLLOWERS_ACTIVITY_ID}/seed-followers-${RUN_ID}.jpg"
  response=$(storage_upload "activity-photos" "$FOLLOWERS_STORAGE_PATH" "$tiny_jpg" "image/jpeg" "$OWNER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: followers storage object uploaded"
  rm -f "$tiny_jpg"

  response=$(rest_insert_service "follows" \
    "{\"follower_id\":\"${OTHER_ID}\",\"following_id\":\"${OWNER_ID}\",\"status\":\"accepted\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: accepted follow relationship inserted"
  ACCEPTED_FOLLOW_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$ACCEPTED_FOLLOW_ID" "seed: accepted follow id obtained"

  response=$(rest_insert_service "follows" \
    "{\"follower_id\":\"${PENDING_ID}\",\"following_id\":\"${OWNER_ID}\",\"status\":\"pending\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: pending follow relationship inserted"
  PENDING_FOLLOW_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$PENDING_FOLLOW_ID" "seed: pending follow id obtained"

  response=$(rest_insert_service "comments" \
    "{\"activity_id\":\"${PUBLIC_ACTIVITY_ID}\",\"user_id\":\"${OWNER_ID}\",\"body\":\"Seed public owner comment ${RUN_ID}\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: owner comment for public activity inserted"
  PUBLIC_OWNER_COMMENT_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$PUBLIC_OWNER_COMMENT_ID" "seed: owner public comment id obtained"

  response=$(rest_insert_service "comments" \
    "{\"activity_id\":\"${PRIVATE_ACTIVITY_ID}\",\"user_id\":\"${OWNER_ID}\",\"body\":\"Seed private owner comment ${RUN_ID}\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: owner comment for private activity inserted"
  PRIVATE_OWNER_COMMENT_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$PRIVATE_OWNER_COMMENT_ID" "seed: owner private comment id obtained"

  response=$(rest_insert_service "comments" \
    "{\"activity_id\":\"${FOLLOWERS_ACTIVITY_ID}\",\"user_id\":\"${OWNER_ID}\",\"body\":\"Seed followers owner comment ${RUN_ID}\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: owner comment for followers activity inserted"
  FOLLOWERS_OWNER_COMMENT_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$FOLLOWERS_OWNER_COMMENT_ID" "seed: owner followers comment id obtained"

  response=$(rest_insert_service "comments" \
    "{\"activity_id\":\"${PUBLIC_ACTIVITY_ID}\",\"user_id\":\"${OTHER_ID}\",\"body\":\"Seed public accepted follower comment ${RUN_ID}\"}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "seed: accepted-follower comment for visible activity inserted"
  PUBLIC_OTHER_COMMENT_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$PUBLIC_OTHER_COMMENT_ID" "seed: accepted-follower public comment id obtained"
}

# TODO: Document test_owner_access.
test_owner_access() {
  printf "\n== Owner access tests ==\n"
  local response
  local owner_display_name="RLS-Test-Owner-${RUN_ID}"
  local temp_gear_name="temp-gear-${RUN_ID}"
  local temp_gear_updated_name="temp-gear-updated-${RUN_ID}"
  assert_select_count "profiles" "$OWNER_TOKEN" "id=eq.${OWNER_ID}" "1" "owner reads own profile"
  assert_select_count "gear" "$OWNER_TOKEN" "id=eq.${GEAR_ID}" "1" "owner reads own gear"
  assert_select_count "activities" "$OWNER_TOKEN" "id=in.(${PUBLIC_ACTIVITY_ID},${PRIVATE_ACTIVITY_ID})" "2" "owner reads both activities"
  assert_select_count "track_points" "$OWNER_TOKEN" "activity_id=in.(${PUBLIC_ACTIVITY_ID},${PRIVATE_ACTIVITY_ID})" "2" "owner reads track_points for both activities"
  assert_select_count "splits" "$OWNER_TOKEN" "activity_id=in.(${PUBLIC_ACTIVITY_ID},${PRIVATE_ACTIVITY_ID})" "2" "owner reads splits for both activities"
  assert_select_count "activity_photos" "$OWNER_TOKEN" "activity_id=in.(${PUBLIC_ACTIVITY_ID},${PRIVATE_ACTIVITY_ID})" "2" "owner reads activity_photos for both activities"

  response=$(rest_update "profiles" "id=eq.${OWNER_ID}" \
    "{\"display_name\":\"${owner_display_name}\"}" "$OWNER_TOKEN")
  assert_single_row_mutation "$response" "owner updates own profile" "owner profile update affects one row"
  assert_select_count_service "profiles" "id=eq.${OWNER_ID}&display_name=eq.${owner_display_name}" "1" "owner profile update persisted"
  response=$(rest_insert "gear" \
    "{\"user_id\":\"${OWNER_ID}\",\"name\":\"${temp_gear_name}\",\"gear_type\":\"bike\"}" "$OWNER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "owner inserts own gear"
  TEMP_GEAR_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$TEMP_GEAR_ID" "owner temp gear id obtained"

  response=$(rest_update "gear" "id=eq.${TEMP_GEAR_ID}" \
    "{\"name\":\"${temp_gear_updated_name}\"}" "$OWNER_TOKEN")
  assert_single_row_mutation "$response" "owner updates own gear" "owner gear update affects one row"
  assert_select_count_service "gear" "id=eq.${TEMP_GEAR_ID}&name=eq.${temp_gear_updated_name}" "1" "owner gear update persisted"

  response=$(rest_delete "gear" "id=eq.${TEMP_GEAR_ID}" "$OWNER_TOKEN")
  assert_single_row_mutation "$response" "owner deletes own gear" "owner gear delete affects one row"
  assert_select_count_service "gear" "id=eq.${TEMP_GEAR_ID}" "0" "owner gear deletion persisted"
  TEMP_GEAR_ID=""
  response=$(rest_insert "activities" \
    "{\"user_id\":\"${OWNER_ID}\",\"sport_type\":\"run\",\"started_at\":\"2026-03-14T11:00:00Z\",\"distance_meters\":4200,\"duration_seconds\":1260,\"visibility\":\"private\",\"title\":\"Owner Temp ${RUN_ID}\",\"gear_id\":\"${GEAR_ID}\"}" "$OWNER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "owner inserts own activity"
  TEMP_ACTIVITY_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$TEMP_ACTIVITY_ID" "owner temp activity id obtained"

  response=$(rest_insert "activities" \
    "{\"user_id\":\"${OWNER_ID}\",\"sport_type\":\"run\",\"started_at\":\"2026-03-14T11:05:00Z\",\"distance_meters\":2400,\"duration_seconds\":840,\"visibility\":\"private\",\"title\":\"Owner Foreign Gear ${RUN_ID}\",\"gear_id\":\"${OTHER_GEAR_ID}\"}" "$OWNER_TOKEN")
  assert_rejected_mutation "$response" "owner cannot insert activity with other user's gear"

  response=$(rest_update "activities" "id=eq.${TEMP_ACTIVITY_ID}" \
    "{\"title\":\"Owner Temp Updated ${RUN_ID}\"}" "$OWNER_TOKEN")
  assert_single_row_mutation "$response" "owner updates own activity" "owner activity update affects one row"

  response=$(rest_update "activities" "id=eq.${PUBLIC_ACTIVITY_ID}" \
    "{\"gear_id\":\"${OTHER_GEAR_ID}\"}" "$OWNER_TOKEN")
  assert_rejected_mutation "$response" "owner cannot attach other user's gear to own activity"
  assert_select_count_service "activities" "id=eq.${PUBLIC_ACTIVITY_ID}&gear_id=eq.${GEAR_ID}" "1" "owner activity gear unchanged after foreign-gear update"

  response=$(rest_delete "activities" "id=eq.${TEMP_ACTIVITY_ID}" "$OWNER_TOKEN")
  assert_single_row_mutation "$response" "owner deletes own activity" "owner activity delete affects one row"

  assert_select_count_service "activities" "id=eq.${TEMP_ACTIVITY_ID}" "0" "owner activity deletion persisted"
  TEMP_ACTIVITY_ID=""

  response=$(rest_insert "activity_photos" \
    "{\"activity_id\":\"${PUBLIC_ACTIVITY_ID}\",\"user_id\":\"${OWNER_ID}\",\"storage_path\":\"${OWNER_ID}/${PUBLIC_ACTIVITY_ID}/owner-temp-${RUN_ID}.jpg\",\"thumbnail_path\":null,\"sort_order\":2}" "$OWNER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "owner inserts own activity_photo"
  TEMP_ACTIVITY_PHOTO_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$TEMP_ACTIVITY_PHOTO_ID" "owner temp activity_photo id obtained"

  response=$(rest_delete "activity_photos" "id=eq.${TEMP_ACTIVITY_PHOTO_ID}" "$OWNER_TOKEN")
  assert_single_row_mutation "$response" "owner deletes own activity_photo" "owner activity_photo delete affects one row"
  assert_select_count_service "activity_photos" "id=eq.${TEMP_ACTIVITY_PHOTO_ID}" "0" "owner activity_photo deletion persisted"
  TEMP_ACTIVITY_PHOTO_ID=""
}

# TODO: Document test_other_user_read_access.
test_other_user_read_access() {
  local response
  assert_select_count "profiles" "$OTHER_TOKEN" "id=eq.${OWNER_ID}" "1" "other reads owner's profile"
  assert_select_count "activities" "$OTHER_TOKEN" "id=in.(${PUBLIC_ACTIVITY_ID},${PRIVATE_ACTIVITY_ID},${FOLLOWERS_ACTIVITY_ID})" "2" "accepted follower sees public and followers activities"

  response=$(rest_select "activities" "$OTHER_TOKEN" "id=eq.${PUBLIC_ACTIVITY_ID}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "other public activity lookup status"
  assert_row_count "$RESPONSE_BODY" "1" "other public activity lookup"
  local visible_id
  visible_id=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_eq "$visible_id" "$PUBLIC_ACTIVITY_ID" "visible activity is the public one"

  # Stage 7 changed track_points to owner-only; non-owner reads go through RPC
  assert_select_count "track_points" "$OTHER_TOKEN" "activity_id=eq.${PUBLIC_ACTIVITY_ID}" "0" "other cannot read raw track_points (Stage 7: owner-only)"
  assert_select_count "splits" "$OTHER_TOKEN" "activity_id=eq.${PUBLIC_ACTIVITY_ID}" "1" "other reads public activity splits"
  assert_select_count "activity_photos" "$OTHER_TOKEN" "id=in.(${PUBLIC_ACTIVITY_PHOTO_ID},${PRIVATE_ACTIVITY_PHOTO_ID},${FOLLOWERS_ACTIVITY_PHOTO_ID})" "2" "accepted follower reads public and followers activity photos"

  assert_select_count "activities" "$OTHER_TOKEN" "id=eq.${PRIVATE_ACTIVITY_ID}" "0" "other cannot read private activity"
  assert_select_count "track_points" "$OTHER_TOKEN" "activity_id=eq.${PRIVATE_ACTIVITY_ID}" "0" "other cannot read private track_points"
  assert_select_count "splits" "$OTHER_TOKEN" "activity_id=eq.${PRIVATE_ACTIVITY_ID}" "0" "other cannot read private splits"
  assert_select_count "activity_photos" "$OTHER_TOKEN" "id=eq.${PRIVATE_ACTIVITY_PHOTO_ID}" "0" "other cannot read private activity photos"
  assert_select_count "gear" "$OTHER_TOKEN" "id=eq.${GEAR_ID}" "0" "other cannot read owner's gear"
}

# TODO: Document test_other_user_write_denials.
test_other_user_write_denials() {
  local response
  local hacked_gear_name="Hack-Gear-${RUN_ID}"
  response=$(rest_update "gear" "id=eq.${GEAR_ID}" "{\"name\":\"Hacked\"}" "$OTHER_TOKEN")
  assert_noop_mutation "$response" "other cannot update owner's gear status" "other cannot update owner's gear"
  assert_select_count_service "gear" "id=eq.${GEAR_ID}" "1" "other gear update did not alter owner's gear"

  response=$(rest_update "activities" "id=eq.${PUBLIC_ACTIVITY_ID}" "{\"title\":\"Hacker-${RUN_ID}\"}" "$OTHER_TOKEN")
  assert_noop_mutation "$response" "other cannot update owner's public activity status" "other cannot update owner's public activity"
  assert_select_count_service "activities" "id=eq.${PUBLIC_ACTIVITY_ID}" "1" "other public activity update did not alter owner's activity"

  response=$(rest_insert "activities" \
    "{\"user_id\":\"${OWNER_ID}\",\"sport_type\":\"run\",\"started_at\":\"2026-03-14T12:00:00Z\",\"distance_meters\":3333,\"duration_seconds\":111,\"visibility\":\"private\",\"title\":\"Hacker-${RUN_ID}\"}" "$OTHER_TOKEN")
  assert_rejected_mutation "$response" "other cannot insert owner's activity"
  assert_select_count_service "activities" "title=eq.Hacker-${RUN_ID}" "0" "other activity insert as owner did not create row"

  response=$(rest_update "profiles" "id=eq.${OWNER_ID}" "{\"display_name\":\"Hacked\"}" "$OTHER_TOKEN")
  assert_noop_mutation "$response" "other owner-profile update attempt status" "other cannot update owner's profile"

  response=$(rest_insert "gear" \
    "{\"user_id\":\"${OWNER_ID}\",\"name\":\"${hacked_gear_name}\",\"gear_type\":\"shoe\"}" "$OTHER_TOKEN")
  assert_rejected_mutation "$response" "other cannot insert gear as owner (403)"
  assert_select_count_service "gear" "user_id=eq.${OWNER_ID}&name=eq.${hacked_gear_name}" "0" "other gear insert as owner did not create row"

  response=$(rest_delete "gear" "id=eq.${GEAR_ID}" "$OTHER_TOKEN")
  assert_noop_mutation "$response" "other cannot delete owner's gear status" "other cannot delete owner's gear"
  assert_select_count_service "gear" "id=eq.${GEAR_ID}" "1" "other gear delete did not remove owner's gear"

  response=$(rest_insert "track_points" \
    "{\"activity_id\":\"${PRIVATE_ACTIVITY_ID}\",\"timestamp\":\"2026-03-14T11:00:01Z\",\"latitude\":37.7760,\"longitude\":-122.4193}" "$OTHER_TOKEN")
  assert_rejected_mutation "$response" "other cannot insert track_point"
  assert_select_count_service "track_points" "activity_id=eq.${PRIVATE_ACTIVITY_ID}" "1" "other cannot insert private track_point"

  response=$(rest_delete "track_points" "id=eq.${PUBLIC_TRACK_POINT_ID}" "$OTHER_TOKEN")
  assert_noop_mutation "$response" "other cannot delete owner's track_point status" "other cannot delete owner's track_point"
  assert_select_count_service "track_points" "id=eq.${PUBLIC_TRACK_POINT_ID}" "1" "other track_point delete did not remove row"

  response=$(rest_insert "splits" \
    "{\"activity_id\":\"${PRIVATE_ACTIVITY_ID}\",\"split_number\":2,\"distance_meters\":1200,\"duration_seconds\":200}" "$OTHER_TOKEN")
  assert_rejected_mutation "$response" "other cannot insert split"
  assert_select_count_service "splits" "activity_id=eq.${PRIVATE_ACTIVITY_ID}" "1" "other cannot insert private split"

  response=$(rest_delete "splits" "id=eq.${PUBLIC_SPLIT_ID}" "$OTHER_TOKEN")
  assert_noop_mutation "$response" "other cannot delete owner's split status" "other cannot delete owner's split"
  assert_select_count_service "splits" "id=eq.${PUBLIC_SPLIT_ID}" "1" "other split delete did not remove row"

  response=$(rest_delete "activities" "id=eq.${PUBLIC_ACTIVITY_ID}" "$OTHER_TOKEN")
  assert_noop_mutation "$response" "other cannot delete owner's activity status" "other cannot delete owner's activity"
  assert_select_count_service "activities" "id=eq.${PUBLIC_ACTIVITY_ID}" "1" "other cannot delete owner's activity (still exists)"

  response=$(rest_insert "activity_photos" \
    "{\"activity_id\":\"${PUBLIC_ACTIVITY_ID}\",\"user_id\":\"${OTHER_ID}\",\"storage_path\":\"${OTHER_ID}/${PUBLIC_ACTIVITY_ID}/hacked-${RUN_ID}.jpg\",\"thumbnail_path\":null,\"sort_order\":9}" "$OTHER_TOKEN")
  assert_rejected_mutation "$response" "other cannot insert activity_photo for owner activity"
  assert_select_count_service "activity_photos" "activity_id=eq.${PUBLIC_ACTIVITY_ID}&user_id=eq.${OTHER_ID}&sort_order=eq.9" "0" "other insert activity_photo did not create row"

  response=$(rest_delete "activity_photos" "id=eq.${PUBLIC_ACTIVITY_PHOTO_ID}" "$OTHER_TOKEN")
  assert_noop_mutation "$response" "other cannot delete owner's activity_photo status" "other cannot delete owner's activity_photo"
  assert_select_count_service "activity_photos" "id=eq.${PUBLIC_ACTIVITY_PHOTO_ID}" "1" "other activity_photo delete did not remove row"
}

test_other_user_access() {
  printf "\n== Other-user access tests ==\n"
  test_other_user_read_access
  test_other_user_write_denials
}

# TODO: Document test_followers_visibility_reads.
test_followers_visibility_reads() {
  printf "\n== Followers visibility reads ==\n"
  local response
  assert_select_count "activities" "$OWNER_TOKEN" "id=eq.${FOLLOWERS_ACTIVITY_ID}" "1" "owner reads followers activity"
  assert_select_count "splits" "$OWNER_TOKEN" "id=eq.${FOLLOWERS_SPLIT_ID}" "1" "owner reads followers activity split"
  assert_select_count "activity_photos" "$OWNER_TOKEN" "id=eq.${FOLLOWERS_ACTIVITY_PHOTO_ID}" "1" "owner reads followers activity photo metadata"

  assert_select_count "activities" "$OTHER_TOKEN" "id=eq.${FOLLOWERS_ACTIVITY_ID}" "1" "accepted follower reads followers activity"
  assert_select_count "splits" "$OTHER_TOKEN" "id=eq.${FOLLOWERS_SPLIT_ID}" "1" "accepted follower reads followers split"
  assert_select_count "activity_photos" "$OTHER_TOKEN" "id=eq.${FOLLOWERS_ACTIVITY_PHOTO_ID}" "1" "accepted follower reads followers activity photo metadata"

  assert_select_count "activities" "$PENDING_TOKEN" "id=eq.${FOLLOWERS_ACTIVITY_ID}" "0" "pending requester cannot read followers activity"
  assert_select_count "splits" "$PENDING_TOKEN" "id=eq.${FOLLOWERS_SPLIT_ID}" "0" "pending requester cannot read followers split"
  assert_select_count "activity_photos" "$PENDING_TOKEN" "id=eq.${FOLLOWERS_ACTIVITY_PHOTO_ID}" "0" "pending requester cannot read followers activity photo metadata"

  assert_select_count "activities" "$UNRELATED_TOKEN" "id=eq.${FOLLOWERS_ACTIVITY_ID}" "0" "unrelated viewer cannot read followers activity"
  assert_select_count "splits" "$UNRELATED_TOKEN" "id=eq.${FOLLOWERS_SPLIT_ID}" "0" "unrelated viewer cannot read followers split"
  assert_select_count "activity_photos" "$UNRELATED_TOKEN" "id=eq.${FOLLOWERS_ACTIVITY_PHOTO_ID}" "0" "unrelated viewer cannot read followers activity photo metadata"

  response=$(storage_download "activity-photos" "$FOLLOWERS_STORAGE_PATH" "$OWNER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "owner reads followers storage object"

  response=$(storage_download "activity-photos" "$FOLLOWERS_STORAGE_PATH" "$OTHER_TOKEN")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "accepted follower reads followers storage object"

  response=$(storage_download "activity-photos" "$FOLLOWERS_STORAGE_PATH" "$PENDING_TOKEN")
  split_http_response "$response"
  assert_http_error "$RESPONSE_STATUS" "pending requester cannot read followers storage object"

  response=$(storage_download "activity-photos" "$FOLLOWERS_STORAGE_PATH" "$UNRELATED_TOKEN")
  split_http_response "$response"
  assert_http_error "$RESPONSE_STATUS" "unrelated viewer cannot read followers storage object"
}

# TODO: Document test_comment_visibility_reads.
test_comment_visibility_reads() {
  printf "\n== Comment visibility reads ==\n"
  assert_select_count "comments" "$OWNER_TOKEN" "id=in.(${PUBLIC_OWNER_COMMENT_ID},${PRIVATE_OWNER_COMMENT_ID},${FOLLOWERS_OWNER_COMMENT_ID},${PUBLIC_OTHER_COMMENT_ID})" "4" "owner reads comments across public/private/followers activities"

  assert_select_count "comments" "$OTHER_TOKEN" "id=in.(${PUBLIC_OWNER_COMMENT_ID},${PRIVATE_OWNER_COMMENT_ID},${FOLLOWERS_OWNER_COMMENT_ID},${PUBLIC_OTHER_COMMENT_ID})" "3" "accepted follower reads public and followers comments"
  assert_select_count "comments" "$OTHER_TOKEN" "id=eq.${PRIVATE_OWNER_COMMENT_ID}" "0" "accepted follower cannot read private activity comments"

  assert_select_count "comments" "$PENDING_TOKEN" "id=in.(${PUBLIC_OWNER_COMMENT_ID},${PRIVATE_OWNER_COMMENT_ID},${FOLLOWERS_OWNER_COMMENT_ID},${PUBLIC_OTHER_COMMENT_ID})" "2" "pending requester reads only public activity comments"
  assert_select_count "comments" "$PENDING_TOKEN" "id=eq.${FOLLOWERS_OWNER_COMMENT_ID}" "0" "pending requester cannot read followers activity comments"

  assert_select_count "comments" "$UNRELATED_TOKEN" "id=in.(${PUBLIC_OWNER_COMMENT_ID},${PRIVATE_OWNER_COMMENT_ID},${FOLLOWERS_OWNER_COMMENT_ID},${PUBLIC_OTHER_COMMENT_ID})" "2" "unrelated viewer reads only public activity comments"
  assert_select_count "comments" "$UNRELATED_TOKEN" "id=eq.${FOLLOWERS_OWNER_COMMENT_ID}" "0" "unrelated viewer cannot read followers activity comments"
}

# TODO: Document test_visibility_helper_call_constraints.
test_visibility_helper_call_constraints() {
  printf "\n== Visibility helper call constraints ==\n"
  local response can_view

  response=$(http_post_json "${REST_URL}/rpc/can_view_activity" \
    "{\"p_activity_owner_id\":\"${OWNER_ID}\",\"p_activity_visibility\":\"followers\",\"p_viewer_id\":\"${OTHER_ID}\"}" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${UNRELATED_TOKEN}")
  split_http_response "$response"
  assert_http_error "$RESPONSE_STATUS" "visibility helper rejects spoofed viewer parameter"

  response=$(http_post_json "${REST_URL}/rpc/can_view_activity" \
    "{\"p_activity_owner_id\":\"${OWNER_ID}\",\"p_activity_visibility\":\"followers\"}" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${OTHER_TOKEN}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "accepted follower can call visibility helper without viewer override"
  can_view=$(json_field "$RESPONSE_BODY" '.')
  assert_eq "$can_view" "true" "accepted follower visibility helper call returns true"

  response=$(http_post_json "${REST_URL}/rpc/can_view_activity" \
    "{\"p_activity_owner_id\":\"${OWNER_ID}\",\"p_activity_visibility\":\"followers\"}" \
    -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${UNRELATED_TOKEN}")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "unrelated viewer can call visibility helper without viewer override"
  can_view=$(json_field "$RESPONSE_BODY" '.')
  assert_eq "$can_view" "false" "unrelated visibility helper call returns false"
}

# TODO: Document test_follow_and_kudos_mutations.
test_follow_and_kudos_mutations() {
  printf "\n== Follow and kudos mutation rules ==\n"
  local response

  response=$(rest_insert "follows" \
    "{\"follower_id\":\"${UNRELATED_ID}\",\"following_id\":\"${OWNER_ID}\",\"status\":\"pending\"}" "$UNRELATED_TOKEN")
  assert_single_row_mutation "$response" "send follow request succeeds" "follow request insert affects one row"
  MUTATION_ACCEPT_FOLLOW_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$MUTATION_ACCEPT_FOLLOW_ID" "follow request id captured for accept flow"

  response=$(rest_update "follows" "id=eq.${MUTATION_ACCEPT_FOLLOW_ID}" \
    "{\"status\":\"accepted\"}" "$OWNER_TOKEN")
  assert_single_row_mutation "$response" "accept follow request succeeds" "follow accept update affects one row"

  response=$(rest_insert "follows" \
    "{\"follower_id\":\"${UNRELATED_ID}\",\"following_id\":\"${OWNER_ID}\",\"status\":\"pending\"}" "$UNRELATED_TOKEN")
  assert_rejected_mutation "$response" "duplicate follow request rejected by unique relationship constraint"

  response=$(rest_insert "follows" \
    "{\"follower_id\":\"${PENDING_ID}\",\"following_id\":\"${UNRELATED_ID}\",\"status\":\"pending\"}" "$PENDING_TOKEN")
  assert_single_row_mutation "$response" "secondary follow request succeeds for reject flow" "secondary follow request insert affects one row"
  MUTATION_REJECT_FOLLOW_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$MUTATION_REJECT_FOLLOW_ID" "follow request id captured for reject flow"

  response=$(rest_delete "follows" "id=eq.${MUTATION_REJECT_FOLLOW_ID}" "$UNRELATED_TOKEN")
  assert_single_row_mutation "$response" "reject follow request succeeds via delete" "follow reject delete affects one row"

  response=$(rest_insert "follows" \
    "{\"follower_id\":\"${UNRELATED_ID}\",\"following_id\":\"${OWNER_ID}\",\"status\":\"accepted\"}" "$UNRELATED_TOKEN")
  assert_rejected_mutation "$response" "requester cannot self-accept follow request"

  response=$(rest_insert "follows" \
    "{\"follower_id\":\"${OWNER_ID}\",\"following_id\":\"${UNRELATED_ID}\",\"status\":\"pending\"}" "$UNRELATED_TOKEN")
  assert_rejected_mutation "$response" "cross-user follow request tampering is rejected"

  response=$(rest_insert "follows" \
    "{\"follower_id\":\"${PENDING_ID}\",\"following_id\":\"${UNRELATED_ID}\",\"status\":\"pending\"}" "$PENDING_TOKEN")
  assert_single_row_mutation "$response" "unfollow flow seed relationship inserted" "unfollow flow seed insert affects one row"
  MUTATION_UNFOLLOW_FOLLOW_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$MUTATION_UNFOLLOW_FOLLOW_ID" "unfollow flow relationship id captured"

  response=$(rest_delete "follows" "id=eq.${MUTATION_UNFOLLOW_FOLLOW_ID}" "$PENDING_TOKEN")
  assert_single_row_mutation "$response" "unfollow succeeds via delete" "unfollow delete affects one row"

  response=$(rest_delete "follows" "id=eq.${ACCEPTED_FOLLOW_ID}" "$UNRELATED_TOKEN")
  assert_noop_mutation "$response" "cross-user follow delete attempt status" "cross-user follow delete denied"

  response=$(rest_insert "kudos" \
    "{\"activity_id\":\"${FOLLOWERS_ACTIVITY_ID}\",\"user_id\":\"${OTHER_ID}\"}" "$OTHER_TOKEN")
  assert_single_row_mutation "$response" "give kudos succeeds for accepted follower" "kudos insert affects one row"
  OTHER_KUDOS_ID=$(json_field "$RESPONSE_BODY" '.[0].id')
  assert_not_empty "$OTHER_KUDOS_ID" "kudos id captured"

  response=$(rest_insert "kudos" \
    "{\"activity_id\":\"${FOLLOWERS_ACTIVITY_ID}\",\"user_id\":\"${OTHER_ID}\"}" "$OTHER_TOKEN")
  assert_rejected_mutation "$response" "duplicate kudos rejected by unique constraint"

  response=$(rest_insert "kudos" \
    "{\"activity_id\":\"${FOLLOWERS_ACTIVITY_ID}\",\"user_id\":\"${PENDING_ID}\"}" "$PENDING_TOKEN")
  assert_rejected_mutation "$response" "pending requester cannot give kudos on followers activity"

  response=$(rest_insert "kudos" \
    "{\"activity_id\":\"${PUBLIC_ACTIVITY_ID}\",\"user_id\":\"${OWNER_ID}\"}" "$UNRELATED_TOKEN")
  assert_rejected_mutation "$response" "cross-user kudos insert tampering is rejected"

  response=$(rest_delete "kudos" "id=eq.${OTHER_KUDOS_ID}" "$UNRELATED_TOKEN")
  assert_noop_mutation "$response" "cross-user kudos delete attempt status" "cross-user kudos delete denied"

  response=$(rest_delete "kudos" "id=eq.${OTHER_KUDOS_ID}" "$OTHER_TOKEN")
  assert_single_row_mutation "$response" "remove kudos succeeds for creator" "kudos delete affects one row"
}

# TODO: Document test_comment_mutations.
test_comment_mutations() {
  printf "\n== Comment mutation rules ==\n"
  local response
  local pending_fail_body="pending-should-fail-${RUN_ID}" unrelated_fail_body="unrelated-should-fail-${RUN_ID}" tamper_fail_body="tamper-user-id-${RUN_ID}"
  insert_comment_and_capture_id "$OTHER_TOKEN" "$PUBLIC_ACTIVITY_ID" "$OTHER_ID" "Mutation public comment ${RUN_ID}" "insert own comment succeeds on visible public activity" "public comment insert affects one row" "public mutation comment id captured" MUTATION_PUBLIC_COMMENT_ID
  insert_comment_and_capture_id "$OWNER_TOKEN" "$PRIVATE_ACTIVITY_ID" "$OWNER_ID" "Mutation private owner comment ${RUN_ID}" "owner inserts own comment on visible private activity" "private owner comment insert affects one row" "private mutation comment id captured" MUTATION_PRIVATE_COMMENT_ID
  insert_comment_and_capture_id "$OTHER_TOKEN" "$FOLLOWERS_ACTIVITY_ID" "$OTHER_ID" "Mutation followers comment ${RUN_ID}" "insert own comment succeeds on visible followers activity" "followers comment insert affects one row" "followers mutation comment id captured" MUTATION_FOLLOWERS_COMMENT_ID
  response=$(rest_insert "comments" "{\"activity_id\":\"${FOLLOWERS_ACTIVITY_ID}\",\"user_id\":\"${PENDING_ID}\",\"body\":\"${pending_fail_body}\"}" "$PENDING_TOKEN")
  assert_rejected_mutation "$response" "pending requester cannot comment on non-visible followers activity"
  assert_select_count_service "comments" "activity_id=eq.${FOLLOWERS_ACTIVITY_ID}&user_id=eq.${PENDING_ID}&body=eq.${pending_fail_body}" "0" "pending failed comment insert created no rows"
  response=$(rest_insert "comments" "{\"activity_id\":\"${PRIVATE_ACTIVITY_ID}\",\"user_id\":\"${UNRELATED_ID}\",\"body\":\"${unrelated_fail_body}\"}" "$UNRELATED_TOKEN")
  assert_rejected_mutation "$response" "unrelated viewer cannot comment on non-visible private activity"
  assert_select_count_service "comments" "activity_id=eq.${PRIVATE_ACTIVITY_ID}&user_id=eq.${UNRELATED_ID}&body=eq.${unrelated_fail_body}" "0" "unrelated failed private comment insert created no rows"
  response=$(rest_insert "comments" "{\"activity_id\":\"${PUBLIC_ACTIVITY_ID}\",\"user_id\":\"${OWNER_ID}\",\"body\":\"${tamper_fail_body}\"}" "$OTHER_TOKEN")
  assert_rejected_mutation "$response" "cross-user comment insert tampering is rejected"
  assert_select_count_service "comments" "activity_id=eq.${PUBLIC_ACTIVITY_ID}&user_id=eq.${OWNER_ID}&body=eq.${tamper_fail_body}" "0" "tampered comment insert created no rows"
  delete_comment_and_assert_removed "$MUTATION_PUBLIC_COMMENT_ID" "$OTHER_TOKEN" "delete own public comment succeeds" "public comment delete affects one row" "public comment deletion persisted"
  MUTATION_PUBLIC_COMMENT_ID=""
  delete_comment_and_assert_removed "$MUTATION_PRIVATE_COMMENT_ID" "$OWNER_TOKEN" "owner deletes own private comment succeeds" "private owner comment delete affects one row" "private owner comment deletion persisted"
  MUTATION_PRIVATE_COMMENT_ID=""
  response=$(rest_delete "comments" "id=eq.${PUBLIC_OWNER_COMMENT_ID}" "$OTHER_TOKEN")
  assert_noop_mutation "$response" "delete another user's comment is denied status" "delete another user's comment is denied"
  assert_select_count_service "comments" "id=eq.${PUBLIC_OWNER_COMMENT_ID}" "1" "owner public seeded comment remains after cross-user delete attempt"
  delete_comment_and_assert_removed "$MUTATION_FOLLOWERS_COMMENT_ID" "$OTHER_TOKEN" "delete own followers comment succeeds" "followers comment delete affects one row" "followers comment deletion persisted"
  MUTATION_FOLLOWERS_COMMENT_ID=""
}

test_anon_access() {
  printf "\n== Anon key access ==\n"
  assert_select_count_anon "profiles" "0" "anon gets 0 profiles"
  assert_select_count_anon "activities" "0" "anon gets 0 activities"
  assert_select_count_anon "gear" "0" "anon gets 0 gear"
  assert_select_count_anon "track_points" "0" "anon gets 0 track_points"
  assert_select_count_anon "splits" "0" "anon gets 0 splits"
  assert_select_count_anon "activity_photos" "0" "anon gets 0 activity_photos"
  assert_select_count_anon "comments" "0" "anon gets 0 comments"
}

test_trigger_with_rls() {
  printf "\n== Trigger fires with RLS enabled ==\n"
  local trigger_email="rls-trigger-${RUN_ID}@test.local"
  local response
  response=$(signup_email_password "$trigger_email" "TriggerTestPass!42")
  split_http_response "$response"
  assert_http_ok "$RESPONSE_STATUS" "trigger test: sign-up succeeds"

  TRIGGER_USER_ID=$(json_field "$RESPONSE_BODY" '.id // .user.id // empty')
  assert_not_empty "$TRIGGER_USER_ID" "trigger test: user id obtained"

  local profile_exists
  profile_exists=$(db_query "SELECT count(*) FROM public.profiles WHERE id = '${TRIGGER_USER_ID}';")
  assert_eq "$profile_exists" "1" "trigger test: profile created with RLS enabled"
}

# TODO: Document cleanup_test_data.
cleanup_test_data() {
  printf "\n== Cleanup ==\n"

  # Delete follows and kudos before activity cleanup.
  for fid in "${ACCEPTED_FOLLOW_ID:-}" "${PENDING_FOLLOW_ID:-}" "${MUTATION_ACCEPT_FOLLOW_ID:-}" "${MUTATION_REJECT_FOLLOW_ID:-}" "${MUTATION_UNFOLLOW_FOLLOW_ID:-}"; do
    if [ -n "$fid" ]; then
      rest_delete_service "follows" "id=eq.${fid}" >/dev/null 2>&1 || true
    fi
  done

  if [ -n "${OWNER_ID:-}" ]; then
    rest_delete_service "follows" "following_id=eq.${OWNER_ID}" >/dev/null 2>&1 || true
    rest_delete_service "kudos" "activity_id=in.(${PUBLIC_ACTIVITY_ID:-00000000-0000-0000-0000-000000000000},${FOLLOWERS_ACTIVITY_ID:-00000000-0000-0000-0000-000000000000})" >/dev/null 2>&1 || true
  fi

  # Delete activities (cascades to track_points, splits, and kudos)
  for aid in "${PUBLIC_ACTIVITY_ID:-}" "${PRIVATE_ACTIVITY_ID:-}" "${FOLLOWERS_ACTIVITY_ID:-}" "${TEMP_ACTIVITY_ID:-}"; do
    if [ -n "$aid" ]; then
      rest_delete_service "activities" "id=eq.${aid}" >/dev/null 2>&1 || true
    fi
  done

  # Delete activity_photos not already cascaded through activity deletes.
  for pid in "${PUBLIC_ACTIVITY_PHOTO_ID:-}" "${PRIVATE_ACTIVITY_PHOTO_ID:-}" "${FOLLOWERS_ACTIVITY_PHOTO_ID:-}" "${TEMP_ACTIVITY_PHOTO_ID:-}"; do
    if [ -n "$pid" ]; then
      rest_delete_service "activity_photos" "id=eq.${pid}" >/dev/null 2>&1 || true
    fi
  done

  if [ -n "${FOLLOWERS_STORAGE_PATH:-}" ]; then
    storage_delete_service "activity-photos" "{\"prefixes\":[\"${FOLLOWERS_STORAGE_PATH}\"]}" >/dev/null 2>&1 || true
  fi

  # Delete gear
  for gid in "${GEAR_ID:-}" "${OTHER_GEAR_ID:-}" "${TEMP_GEAR_ID:-}"; do
    if [ -n "$gid" ]; then
      rest_delete_service "gear" "id=eq.${gid}" >/dev/null 2>&1 || true
    fi
  done

  # Delete trigger test user (cascades to profile)
  delete_auth_user "${TRIGGER_USER_ID:-}"
  delete_auth_user "${PENDING_ID:-}"
  delete_auth_user "${UNRELATED_ID:-}"

  printf "  cleanup complete\n"
}

print_summary() {
  printf "\n========================================\n"
  printf "Stage 4 RLS Verification: %d/%d passed\n" "$PASS_COUNT" "$TOTAL_COUNT"
  if [ "$FAIL_COUNT" -gt 0 ]; then
    printf "%d FAILED\n" "$FAIL_COUNT"
    printf "========================================\n"
    return 1
  fi
  printf "ALL PASSED\n"
  printf "========================================\n"
}

# TODO: Document main.
main() {
  printf "Stage 4 RLS Verification\n"
  printf "API: %s\n" "$API_URL"

  trap 'printf "\n== Emergency cleanup ==\n"; cleanup_test_data' EXIT

  load_and_sign_in
  preflight
  seed_test_data
  test_owner_access
  test_other_user_access
  test_followers_visibility_reads
  test_comment_visibility_reads
  test_visibility_helper_call_constraints
  test_follow_and_kudos_mutations
  test_comment_mutations
  test_anon_access
  test_trigger_with_rls
  cleanup_test_data

  trap - EXIT
  print_summary
}

main "$@"
