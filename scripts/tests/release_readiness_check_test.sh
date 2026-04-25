#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

failures=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [[ "${expected}" != "${actual}" ]]; then
    echo "FAIL: ${description} (expected '${expected}', got '${actual}')"
    failures=$((failures + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "FAIL: ${description} (missing '${needle}')"
    failures=$((failures + 1))
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    echo "FAIL: ${description} (unexpected '${needle}')"
    failures=$((failures + 1))
  fi
}

# Build a minimal fixture that passes all checks by default.
# Individual tests override specific parts to trigger failures.
setup_fixture() {
  local fixture_root
  fixture_root="$(mktemp -d)"

  # Directory structure
  mkdir -p "${fixture_root}/scripts/dev"
  mkdir -p "${fixture_root}/scripts/lib"
  mkdir -p "${fixture_root}/ios/Runner"
  mkdir -p "${fixture_root}/android/app"
  mkdir -p "${fixture_root}/tmp/devicecloud"
  mkdir -p "${fixture_root}/lib"

  # Copy the scripts under test
  cp "${REPO_ROOT}/scripts/lib/deployment_common.sh" "${fixture_root}/scripts/lib/"
  cp "${REPO_ROOT}/scripts/dev/release_readiness_check.sh" "${fixture_root}/scripts/dev/"
  chmod +x "${fixture_root}/scripts/dev/release_readiness_check.sh"

  # Valid .build_number
  echo "10" > "${fixture_root}/.build_number"

  # Valid .env.prod with required keys and valid Mapbox token
  cat > "${fixture_root}/.env.prod" <<'ENV'
SUPABASE_URL=https://example.supabase.co
SUPABASE_ANON_KEY=test-anon-key
MAPBOX_ACCESS_TOKEN=pk.test-valid-public-token
ENV

  # Firebase configs
  echo "<plist />" > "${fixture_root}/ios/Runner/GoogleService-Info.plist"
  echo "{}" > "${fixture_root}/android/app/google-services.json"

  # Init git repo and set HEAD
  (
    cd "${fixture_root}"
    git init -q
    git config user.email "fixture@example.com"
    git config user.name "Fixture User"
    git add .
    git commit -q -m "fixture"
  )

  # Write smoke stamp matching HEAD
  local head_sha
  head_sha="$(git -C "${fixture_root}" rev-parse HEAD)"
  echo "${head_sha}" > "${fixture_root}/tmp/devicecloud/last_passed_sha"

  printf '%s\n' "${fixture_root}"
}

last_exit_code=0
last_output=""

run_readiness() {
  local fixture_root="$1"
  shift
  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    "./scripts/dev/release_readiness_check.sh" "$@" 2>&1
  )" || exit_code=$?
  last_exit_code="${exit_code}"
  last_output="${output}"
}

# --- Build number tests ---

test_missing_build_number_file_fails() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  rm "${fixture_root}/.build_number"

  run_readiness "${fixture_root}"

  assert_eq "1" "${last_exit_code}" "missing .build_number exits 1"
  assert_contains "${last_output}" "[FAIL]" "missing .build_number reports FAIL"
  assert_contains "${last_output}" ".build_number" "missing .build_number names the file"

  rm -rf "${fixture_root}"
}

test_zero_build_number_fails() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  echo "0" > "${fixture_root}/.build_number"

  run_readiness "${fixture_root}"

  assert_eq "1" "${last_exit_code}" "zero .build_number exits 1"
  assert_contains "${last_output}" "[FAIL]" "zero .build_number reports FAIL"

  rm -rf "${fixture_root}"
}

test_non_numeric_build_number_fails() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  echo "abc" > "${fixture_root}/.build_number"

  run_readiness "${fixture_root}"

  assert_eq "1" "${last_exit_code}" "non-numeric .build_number exits 1"
  assert_contains "${last_output}" "[FAIL]" "non-numeric .build_number reports FAIL"

  rm -rf "${fixture_root}"
}

test_valid_build_number_passes() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_readiness "${fixture_root}"

  assert_eq "0" "${last_exit_code}" "valid .build_number exits 0"
  assert_contains "${last_output}" "[PASS]" "valid .build_number reports PASS"
  assert_contains "${last_output}" ".build_number" "valid .build_number names the file"

  rm -rf "${fixture_root}"
}

# --- .env.prod required keys tests ---

test_missing_env_prod_fails() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  rm "${fixture_root}/.env.prod"

  run_readiness "${fixture_root}"

  assert_eq "1" "${last_exit_code}" "missing .env.prod exits 1"
  assert_contains "${last_output}" "[FAIL]" "missing .env.prod reports FAIL"
  assert_contains "${last_output}" ".env.prod" "missing .env.prod names the file"

  rm -rf "${fixture_root}"
}

test_missing_supabase_url_fails() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  cat > "${fixture_root}/.env.prod" <<'ENV'
SUPABASE_ANON_KEY=test-anon-key
MAPBOX_ACCESS_TOKEN=pk.test-valid-public-token
ENV

  run_readiness "${fixture_root}"

  assert_eq "1" "${last_exit_code}" "missing SUPABASE_URL exits 1"
  assert_contains "${last_output}" "SUPABASE_URL" "missing SUPABASE_URL names the key"

  rm -rf "${fixture_root}"
}

test_missing_supabase_anon_key_fails() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  cat > "${fixture_root}/.env.prod" <<'ENV'
SUPABASE_URL=https://example.supabase.co
MAPBOX_ACCESS_TOKEN=pk.test-valid-public-token
ENV

  run_readiness "${fixture_root}"

  assert_eq "1" "${last_exit_code}" "missing SUPABASE_ANON_KEY exits 1"
  assert_contains "${last_output}" "SUPABASE_ANON_KEY" "missing SUPABASE_ANON_KEY names the key"

  rm -rf "${fixture_root}"
}

# --- Mapbox token tests ---

test_missing_mapbox_token_fails() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  cat > "${fixture_root}/.env.prod" <<'ENV'
SUPABASE_URL=https://example.supabase.co
SUPABASE_ANON_KEY=test-anon-key
ENV

  run_readiness "${fixture_root}"

  assert_eq "1" "${last_exit_code}" "missing Mapbox token exits 1"
  assert_contains "${last_output}" "MAPBOX" "missing Mapbox token names the key"

  rm -rf "${fixture_root}"
}

test_placeholder_mapbox_token_fails() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  cat > "${fixture_root}/.env.prod" <<'ENV'
SUPABASE_URL=https://example.supabase.co
SUPABASE_ANON_KEY=test-anon-key
MAPBOX_ACCESS_TOKEN=<your-mapbox-token>
ENV

  run_readiness "${fixture_root}"

  assert_eq "1" "${last_exit_code}" "placeholder Mapbox token exits 1"
  assert_contains "${last_output}" "[FAIL]" "placeholder Mapbox token reports FAIL"
  assert_contains "${last_output}" "placeholder" "placeholder Mapbox token mentions placeholder"

  rm -rf "${fixture_root}"
}

test_secret_scoped_mapbox_token_fails() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  cat > "${fixture_root}/.env.prod" <<'ENV'
SUPABASE_URL=https://example.supabase.co
SUPABASE_ANON_KEY=test-anon-key
MAPBOX_ACCESS_TOKEN=sk.secret-scoped-token
ENV

  run_readiness "${fixture_root}"

  assert_eq "1" "${last_exit_code}" "secret-scoped Mapbox token exits 1"
  assert_contains "${last_output}" "[FAIL]" "secret-scoped Mapbox token reports FAIL"
  assert_contains "${last_output}" "secret" "secret-scoped Mapbox token mentions secret"

  rm -rf "${fixture_root}"
}

test_valid_mapbox_token_passes() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_readiness "${fixture_root}"

  assert_eq "0" "${last_exit_code}" "valid pk.* Mapbox token exits 0"
  assert_contains "${last_output}" "[PASS]" "valid Mapbox token reports PASS"

  rm -rf "${fixture_root}"
}

# --- Mapbox token from .secret/.env.secret fallback ---

test_mapbox_token_resolved_from_secret_file() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  # Remove from .env.prod, put in .secret/.env.secret
  cat > "${fixture_root}/.env.prod" <<'ENV'
SUPABASE_URL=https://example.supabase.co
SUPABASE_ANON_KEY=test-anon-key
ENV
  mkdir -p "${fixture_root}/.secret"
  cat > "${fixture_root}/.secret/.env.secret" <<'ENV'
MAPBOX_ACCESS_TOKEN=pk.from-secret-file
ENV

  run_readiness "${fixture_root}"

  assert_eq "0" "${last_exit_code}" "Mapbox token from .secret/.env.secret exits 0"
  assert_contains "${last_output}" "[PASS]" "Mapbox token from .secret file reports PASS"

  rm -rf "${fixture_root}"
}

# --- DeviceCloud smoke stamp tests ---

test_missing_smoke_stamp_warns() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  rm "${fixture_root}/tmp/devicecloud/last_passed_sha"

  run_readiness "${fixture_root}"

  assert_eq "0" "${last_exit_code}" "missing smoke stamp is warn-only, exits 0"
  assert_contains "${last_output}" "[WARN]" "missing smoke stamp reports WARN"

  rm -rf "${fixture_root}"
}

test_stale_smoke_stamp_warns() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  echo "stale123" > "${fixture_root}/tmp/devicecloud/last_passed_sha"

  run_readiness "${fixture_root}"

  assert_eq "0" "${last_exit_code}" "stale smoke stamp is warn-only, exits 0"
  assert_contains "${last_output}" "[WARN]" "stale smoke stamp reports WARN"
  assert_contains "${last_output}" "stale123" "stale smoke stamp mentions stamp SHA"

  rm -rf "${fixture_root}"
}

test_current_smoke_stamp_passes() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_readiness "${fixture_root}"

  assert_eq "0" "${last_exit_code}" "current smoke stamp exits 0"
  assert_contains "${last_output}" "DeviceCloud smoke stamp matches HEAD" "current smoke stamp reports smoke-specific PASS"

  rm -rf "${fixture_root}"
}

# --- Firebase config tests ---

test_missing_ios_firebase_config_fails() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  rm "${fixture_root}/ios/Runner/GoogleService-Info.plist"

  run_readiness "${fixture_root}"

  assert_eq "1" "${last_exit_code}" "missing iOS Firebase config exits 1"
  assert_contains "${last_output}" "[FAIL]" "missing iOS Firebase config reports FAIL"
  assert_contains "${last_output}" "GoogleService-Info.plist" "missing iOS Firebase config names file"

  rm -rf "${fixture_root}"
}

test_missing_android_firebase_config_fails() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  rm "${fixture_root}/android/app/google-services.json"

  run_readiness "${fixture_root}"

  assert_eq "1" "${last_exit_code}" "missing Android Firebase config exits 1"
  assert_contains "${last_output}" "[FAIL]" "missing Android Firebase config reports FAIL"
  assert_contains "${last_output}" "google-services.json" "missing Android Firebase config names file"

  rm -rf "${fixture_root}"
}

# --- Checkout weight detection ---

test_heavy_checkout_with_data_dir_warns() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  mkdir -p "${fixture_root}/data"

  run_readiness "${fixture_root}"

  assert_eq "0" "${last_exit_code}" "heavy checkout is warn-only, exits 0"
  assert_contains "${last_output}" "[WARN]" "heavy checkout reports WARN"
  assert_contains "${last_output}" "data/" "heavy checkout mentions data/"

  rm -rf "${fixture_root}"
}

test_heavy_checkout_with_build_dir_warns() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  mkdir -p "${fixture_root}/build"

  run_readiness "${fixture_root}"

  assert_eq "0" "${last_exit_code}" "build/ dir is warn-only, exits 0"
  assert_contains "${last_output}" "[WARN]" "build/ dir reports WARN"
  assert_contains "${last_output}" "build/" "heavy checkout mentions build/"

  rm -rf "${fixture_root}"
}

test_lean_checkout_passes() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_readiness "${fixture_root}"

  # Verify no weight warnings in a clean fixture
  assert_not_contains "${last_output}" "heavyweight" "lean checkout has no weight warnings"
  assert_eq "0" "${last_exit_code}" "lean checkout exits 0"

  rm -rf "${fixture_root}"
}

# --- All-green vs exit code semantics ---

test_all_green_exits_zero() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_readiness "${fixture_root}"

  assert_eq "0" "${last_exit_code}" "all-green exits 0"
  assert_contains "${last_output}" "Summary:" "all-green prints summary"
  assert_contains "${last_output}" "0 failed" "all-green reports 0 failures"

  rm -rf "${fixture_root}"
}

test_any_fail_exits_one() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  rm "${fixture_root}/.build_number"

  run_readiness "${fixture_root}"

  assert_eq "1" "${last_exit_code}" "any fail-level check exits 1"
  assert_not_contains "${last_output}" "0 failed" "failing check reports non-zero failures"

  rm -rf "${fixture_root}"
}

test_warn_only_does_not_block_exit_zero() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  # Trigger warn-only: stale smoke stamp + heavy checkout
  echo "stale123" > "${fixture_root}/tmp/devicecloud/last_passed_sha"
  mkdir -p "${fixture_root}/data"

  run_readiness "${fixture_root}"

  assert_eq "0" "${last_exit_code}" "warn-only findings do not block exit 0"
  assert_contains "${last_output}" "[WARN]" "warn-only findings are reported"

  rm -rf "${fixture_root}"
}

main() {
  # Build number tests
  test_missing_build_number_file_fails
  test_zero_build_number_fails
  test_non_numeric_build_number_fails
  test_valid_build_number_passes

  # .env.prod required keys tests
  test_missing_env_prod_fails
  test_missing_supabase_url_fails
  test_missing_supabase_anon_key_fails

  # Mapbox token tests
  test_missing_mapbox_token_fails
  test_placeholder_mapbox_token_fails
  test_secret_scoped_mapbox_token_fails
  test_valid_mapbox_token_passes
  test_mapbox_token_resolved_from_secret_file

  # DeviceCloud smoke stamp tests
  test_missing_smoke_stamp_warns
  test_stale_smoke_stamp_warns
  test_current_smoke_stamp_passes

  # Firebase config tests
  test_missing_ios_firebase_config_fails
  test_missing_android_firebase_config_fails

  # Checkout weight detection
  test_heavy_checkout_with_data_dir_warns
  test_heavy_checkout_with_build_dir_warns
  test_lean_checkout_passes

  # Exit code semantics
  test_all_green_exits_zero
  test_any_fail_exits_one
  test_warn_only_does_not_block_exit_zero

  if [[ "${failures}" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "release_readiness_check_test: PASS"
}

main "$@"
