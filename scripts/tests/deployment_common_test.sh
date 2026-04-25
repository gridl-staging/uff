#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# This source should fail before the helper extraction is implemented.
source "${REPO_ROOT}/scripts/lib/deployment_common.sh"

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

assert_success() {
  local description="$1"
  shift
  if "$@"; then
    return 0
  fi
  echo "FAIL: ${description} (command failed)"
  failures=$((failures + 1))
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

assert_failure() {
  local description="$1"
  shift
  if "$@"; then
    echo "FAIL: ${description} (command succeeded unexpectedly)"
    failures=$((failures + 1))
    return
  fi
}

assert_emit_result_format() {
  local output
  output="$(emit_result "PASS" "formatted output")"
  assert_eq "[PASS] formatted output" "$output" "emit_result formats status lines"
}

assert_read_env_value_behavior() {
  local env_file
  env_file="$(mktemp)"
  cat > "$env_file" <<ENV
# ignored comment
export SUPABASE_URL=https://example.supabase.co
SUPABASE_ANON_KEY=anon-key # inline comment ignored
SPACED_VALUE = value with spaces
ENV

  local url_value
  url_value="$(read_env_value "$env_file" "SUPABASE_URL")"
  assert_eq "https://example.supabase.co" "$url_value" "read_env_value parses exported key"

  local anon_value
  anon_value="$(read_env_value "$env_file" "SUPABASE_ANON_KEY")"
  assert_eq "anon-key" "$anon_value" "read_env_value trims inline comments"

  local missing_value
  missing_value="$(read_env_value "$env_file" "NOT_REAL")"
  assert_eq "" "$missing_value" "read_env_value returns empty when key missing"

  rm -f "$env_file"
}

assert_count_env_key_occurrences_behavior() {
  local env_file
  env_file="$(mktemp)"
  cat > "$env_file" <<ENV
# ignored comment
SUPABASE_URL=https://one.supabase.co
export SUPABASE_URL=https://two.supabase.co
SUPABASE_ANON_KEY=anon-key
ENV

  local url_count
  url_count="$(count_env_key_occurrences "$env_file" "SUPABASE_URL")"
  assert_eq "2" "$url_count" "count_env_key_occurrences counts duplicate keys"

  local anon_count
  anon_count="$(count_env_key_occurrences "$env_file" "SUPABASE_ANON_KEY")"
  assert_eq "1" "$anon_count" "count_env_key_occurrences counts single keys"

  local missing_count
  missing_count="$(count_env_key_occurrences "$env_file" "NOT_REAL")"
  assert_eq "0" "$missing_count" "count_env_key_occurrences returns 0 when key missing"

  rm -f "$env_file"
}

assert_environment_contract() {
  assert_success "is_supported_environment accepts dev" is_supported_environment "dev"
  assert_success "is_supported_environment accepts staging" is_supported_environment "staging"
  assert_success "is_supported_environment accepts prod" is_supported_environment "prod"
  assert_failure "is_supported_environment rejects unknown values" is_supported_environment "qa"
}

assert_hosted_environment_contract() {
  assert_failure "is_hosted_environment rejects dev" is_hosted_environment "dev"
  assert_success "is_hosted_environment accepts staging" is_hosted_environment "staging"
  assert_success "is_hosted_environment accepts prod" is_hosted_environment "prod"
  assert_failure "is_hosted_environment rejects unknown values" is_hosted_environment "qa"
}

assert_env_file_resolution() {
  assert_eq ".env.dev" "$(resolve_env_file_path "dev")" "resolve_env_file_path for dev"
  assert_eq ".env.staging" "$(resolve_env_file_path "staging")" "resolve_env_file_path for staging"
  assert_eq ".env.prod" "$(resolve_env_file_path "prod")" "resolve_env_file_path for prod"
}

assert_credential_selection() {
  assert_eq "SUPABASE_LOCAL_URL SUPABASE_LOCAL_ANON_KEY SUPABASE_LOCAL_SERVICE_ROLE_KEY" "$(resolve_supabase_credential_keys "dev")" "dev uses local credential keys"
  assert_eq "SUPABASE_URL SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY" "$(resolve_supabase_credential_keys "staging")" "staging uses hosted credential keys"
  assert_eq "SUPABASE_URL SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY" "$(resolve_supabase_credential_keys "prod")" "prod uses hosted credential keys"
}

assert_hosted_project_ref_extraction() {
  local hosted_ref
  hosted_ref="$(extract_project_ref_from_url "https://staging-ref.supabase.co")"
  assert_eq "staging-ref" "$hosted_ref" "extract_project_ref_from_url parses hosted project refs"

  if extract_project_ref_from_url "https://example.com" >/dev/null 2>&1; then
    echo "FAIL: extract_project_ref_from_url rejects non-*.supabase.co hosts (command succeeded unexpectedly)"
    failures=$((failures + 1))
  fi
}

assert_upsert_env_key_behavior() {
  local env_file
  env_file="$(mktemp)"
  cat > "$env_file" <<ENV
# ignored comment
SUPABASE_URL=https://example.supabase.co
export FCM_PROJECT_ID=old-project
FCM_PROJECT_ID=older-project
ENV

  upsert_env_key "$env_file" "FCM_PROJECT_ID" "new-project"

  local count
  count="$(count_env_key_occurrences "$env_file" "FCM_PROJECT_ID")"
  assert_eq "1" "$count" "upsert_env_key replaces duplicate definitions with one key"

  local project_id
  project_id="$(read_env_value "$env_file" "FCM_PROJECT_ID")"
  assert_eq "new-project" "$project_id" "upsert_env_key writes the new value"

  local contents
  contents="$(cat "$env_file")"
  assert_contains "$contents" "SUPABASE_URL=https://example.supabase.co" "upsert_env_key preserves unrelated keys"

  rm -f "$env_file"
}

assert_materialize_shared_firebase_configs_copies_missing_files() {
  local repo_root
  local primary_root
  repo_root="$(mktemp -d)"
  primary_root="$(mktemp -d)"

  mkdir -p "${repo_root}/ios/Runner" "${repo_root}/android/app"
  mkdir -p "${primary_root}/ios/Runner" "${primary_root}/android/app"

  printf '%s\n' '<plist>primary-ios</plist>' > "${primary_root}/ios/Runner/GoogleService-Info.plist"
  printf '%s\n' '{"project_info":"primary-android"}' > "${primary_root}/android/app/google-services.json"

  materialize_shared_firebase_configs_from_primary_checkout "${repo_root}" "${primary_root}"

  local ios_contents
  ios_contents="$(cat "${repo_root}/ios/Runner/GoogleService-Info.plist")"
  assert_eq "<plist>primary-ios</plist>" "$ios_contents" \
    "materialize_shared_firebase_configs copies missing iOS Firebase config from primary checkout"

  local android_contents
  android_contents="$(cat "${repo_root}/android/app/google-services.json")"
  assert_eq '{"project_info":"primary-android"}' "$android_contents" \
    "materialize_shared_firebase_configs copies missing Android Firebase config from primary checkout"

  rm -rf "${repo_root}" "${primary_root}"
}

assert_materialize_shared_firebase_configs_preserves_existing_files() {
  local repo_root
  local primary_root
  repo_root="$(mktemp -d)"
  primary_root="$(mktemp -d)"

  mkdir -p "${repo_root}/ios/Runner" "${repo_root}/android/app"
  mkdir -p "${primary_root}/ios/Runner" "${primary_root}/android/app"

  printf '%s\n' '<plist>worktree-ios</plist>' > "${repo_root}/ios/Runner/GoogleService-Info.plist"
  printf '%s\n' '{"project_info":"worktree-android"}' > "${repo_root}/android/app/google-services.json"
  printf '%s\n' '<plist>primary-ios</plist>' > "${primary_root}/ios/Runner/GoogleService-Info.plist"
  printf '%s\n' '{"project_info":"primary-android"}' > "${primary_root}/android/app/google-services.json"

  materialize_shared_firebase_configs_from_primary_checkout "${repo_root}" "${primary_root}"

  local ios_contents
  ios_contents="$(cat "${repo_root}/ios/Runner/GoogleService-Info.plist")"
  assert_eq "<plist>worktree-ios</plist>" "$ios_contents" \
    "materialize_shared_firebase_configs does not overwrite existing iOS Firebase config"

  local android_contents
  android_contents="$(cat "${repo_root}/android/app/google-services.json")"
  assert_eq '{"project_info":"worktree-android"}' "$android_contents" \
    "materialize_shared_firebase_configs does not overwrite existing Android Firebase config"

  rm -rf "${repo_root}" "${primary_root}"
}

assert_check_hosted_client_contract_is_defined() {
  if declare -f check_hosted_client_contract >/dev/null 2>&1; then
    return 0
  fi
  echo "FAIL: check_hosted_client_contract is not defined after sourcing deployment_common.sh"
  failures=$((failures + 1))
}

main() {
  assert_emit_result_format
  assert_read_env_value_behavior
  assert_count_env_key_occurrences_behavior
  assert_environment_contract
  assert_hosted_environment_contract
  assert_env_file_resolution
  assert_credential_selection
  assert_hosted_project_ref_extraction
  assert_upsert_env_key_behavior
  assert_materialize_shared_firebase_configs_copies_missing_files
  assert_materialize_shared_firebase_configs_preserves_existing_files
  assert_check_hosted_client_contract_is_defined

  if [[ "$failures" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "deployment_common_test: PASS"
}

main "$@"
