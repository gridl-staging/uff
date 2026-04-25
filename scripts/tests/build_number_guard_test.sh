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

read_file_or_empty() {
  local file_path="$1"
  if [[ -f "${file_path}" ]]; then
    cat "${file_path}"
    return 0
  fi
  printf ''
}

read_counter_value() {
  local file_path="$1"
  tr -d '[:space:]' < "${file_path}"
}

setup_fixture() {
  local fixture_root
  fixture_root="$(mktemp -d)"

  mkdir -p "${fixture_root}/scripts/dev" "${fixture_root}/scripts/lib" "${fixture_root}/ios" "${fixture_root}/bin"
  cp "${REPO_ROOT}/scripts/dev/build_testflight_release.sh" "${fixture_root}/scripts/dev/"
  cp "${REPO_ROOT}/scripts/lib/deployment_common.sh" "${fixture_root}/scripts/lib/"
  chmod +x "${fixture_root}/scripts/dev/build_testflight_release.sh"

  cat > "${fixture_root}/scripts/dev/with_fast_build_dir.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${BUILD_CALL_LOG}"
if [[ "${MOCK_BUILD_SHOULD_FAIL:-0}" == "1" ]]; then
  exit 31
fi
exit 0
SCRIPT
  chmod +x "${fixture_root}/scripts/dev/with_fast_build_dir.sh"

  cat > "${fixture_root}/bin/fastlane" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${UPLOAD_CALL_LOG}"
if [[ "${MOCK_UPLOAD_SHOULD_FAIL:-0}" == "1" ]]; then
  exit 41
fi
exit 0
SCRIPT
  chmod +x "${fixture_root}/bin/fastlane"

  cat > "${fixture_root}/.env.prod" <<'ENV'
MAPBOX_ACCESS_TOKEN=pk.fixture-public-token
ENV

  cat > "${fixture_root}/fixture.secret" <<'ENV'
ASC_KEY_PATH=/tmp/key.p8
ASC_KEY_ID=test-key-id
ASC_ISSUER_ID=test-issuer-id
MAPBOX_DEFAULT_PUBLIC_TOKEN=pk.fixture-public-token
ENV

  echo "10" > "${fixture_root}/.build_number"

  (
    cd "${fixture_root}"
    git init -q
    git config user.email "fixture@example.com"
    git config user.name "Fixture User"
    git add .
    git commit -q -m "fixture"
  )

  printf '%s\n' "${fixture_root}"
}

last_exit_code=0
last_output=""

run_release() {
  local fixture_root="$1"
  shift

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    BUILD_CALL_LOG="${fixture_root}/build_calls.log" \
    UPLOAD_CALL_LOG="${fixture_root}/upload_calls.log" \
    PATH="${fixture_root}/bin:${PATH}" \
    "./scripts/dev/build_testflight_release.sh" "$@" 2>&1
  )" || exit_code=$?

  last_exit_code="${exit_code}"
  last_output="${output}"
}

test_rejects_stale_explicit_build_number_before_secret_or_build_work() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --build-number 10

  assert_eq "1" "${last_exit_code}" "stale explicit build number exits non-zero"
  assert_contains "${last_output}" "must be greater" "stale explicit build number prints stale guard message"
  assert_not_contains "${last_output}" "Unable to locate .env.secret." "stale explicit build number exits before secret discovery"
  assert_not_contains "${last_output}" "Refusing to build a production/TestFlight release with a broken map configuration." "stale explicit build number exits before runtime token resolution"
  assert_eq "1" "$(test -f "${fixture_root}/build_calls.log"; echo $?)" "stale explicit build number does not invoke mocked build"

  rm -rf "${fixture_root}"
}

test_accepts_higher_explicit_build_number() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --build-number 11 --secret-file "${fixture_root}/fixture.secret" --skip-contract-check --skip-smoke-check

  assert_eq "0" "${last_exit_code}" "higher explicit build number exits zero"
  assert_contains "$(read_file_or_empty "${fixture_root}/build_calls.log")" "--build-number=11" "higher explicit build number reaches mocked flutter build with provided number"

  rm -rf "${fixture_root}"
}

test_build_only_succeeds_without_secret_file_when_env_prod_has_runtime_token() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --skip-contract-check --skip-smoke-check

  assert_eq "0" "${last_exit_code}" "build-only invocation does not require .env.secret when .env.prod already has a public runtime token"
  assert_contains "$(read_file_or_empty "${fixture_root}/build_calls.log")" "--build-number=11" "build-only invocation without .env.secret still reaches mocked flutter build"
  assert_eq "11" "$(read_counter_value "${fixture_root}/.build_number")" "build-only invocation without .env.secret persists incremented canonical counter"

  rm -rf "${fixture_root}"
}

test_omitted_build_number_auto_increments_from_stored_value() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --secret-file "${fixture_root}/fixture.secret" --skip-contract-check --skip-smoke-check

  assert_eq "0" "${last_exit_code}" "omitted build number exits zero"
  assert_contains "$(read_file_or_empty "${fixture_root}/build_calls.log")" "--build-number=11" "omitted build number auto-increments from .build_number value"

  rm -rf "${fixture_root}"
}

test_build_only_persists_after_successful_build() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --secret-file "${fixture_root}/fixture.secret" --skip-contract-check --skip-smoke-check

  assert_eq "0" "${last_exit_code}" "build-only invocation exits zero"
  assert_eq "11" "$(read_counter_value "${fixture_root}/.build_number")" "build-only invocation persists incremented canonical counter after successful build"

  rm -rf "${fixture_root}"
}

test_build_failure_does_not_persist_incremented_counter() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  MOCK_BUILD_SHOULD_FAIL=1 run_release "${fixture_root}" --secret-file "${fixture_root}/fixture.secret" --skip-contract-check --skip-smoke-check

  assert_eq "31" "${last_exit_code}" "build-only invocation surfaces mocked build failure"
  assert_eq "10" "$(read_counter_value "${fixture_root}/.build_number")" "failed build does not persist canonical counter"

  rm -rf "${fixture_root}"
}

test_upload_missing_app_store_connect_credentials_fails_before_build() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  cat > "${fixture_root}/fixture.secret" <<'ENV'
MAPBOX_DEFAULT_PUBLIC_TOKEN=pk.fixture-public-token
ENV

  run_release "${fixture_root}" --upload --secret-file "${fixture_root}/fixture.secret" --skip-contract-check --skip-smoke-check

  assert_eq "1" "${last_exit_code}" "upload invocation without App Store Connect credentials exits non-zero"
  assert_contains "${last_output}" "Upload requested, but App Store Connect credentials were not resolved" "upload invocation prints a credential preflight error"
  assert_eq "1" "$(test -f "${fixture_root}/build_calls.log"; echo $?)" "upload invocation without App Store Connect credentials exits before mocked flutter build"
  assert_eq "10" "$(read_counter_value "${fixture_root}/.build_number")" "upload invocation without App Store Connect credentials does not persist canonical counter"

  rm -rf "${fixture_root}"
}

test_upload_without_secret_file_fails_before_build() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --upload --skip-contract-check --skip-smoke-check

  assert_eq "1" "${last_exit_code}" "upload invocation without .env.secret exits non-zero"
  assert_contains "${last_output}" "Upload requested, but App Store Connect credentials were not resolved" "upload invocation without .env.secret prints a credential preflight error"
  assert_not_contains "${last_output}" "awk: cannot open" "upload invocation without .env.secret does not leak awk file-open errors"
  assert_eq "1" "$(test -f "${fixture_root}/build_calls.log"; echo $?)" "upload invocation without .env.secret exits before mocked flutter build"
  assert_eq "10" "$(read_counter_value "${fixture_root}/.build_number")" "upload invocation without .env.secret does not persist canonical counter"

  rm -rf "${fixture_root}"
}

test_upload_failure_does_not_persist_incremented_counter() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  MOCK_UPLOAD_SHOULD_FAIL=1 run_release "${fixture_root}" --upload --secret-file "${fixture_root}/fixture.secret" --skip-contract-check --skip-smoke-check

  assert_eq "41" "${last_exit_code}" "upload invocation surfaces mocked upload failure"
  assert_eq "10" "$(read_counter_value "${fixture_root}/.build_number")" "failed upload does not persist canonical counter"

  rm -rf "${fixture_root}"
}

test_upload_success_persists_incremented_counter() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --upload --secret-file "${fixture_root}/fixture.secret" --skip-contract-check --skip-smoke-check

  assert_eq "0" "${last_exit_code}" "upload invocation exits zero when mocked upload succeeds"
  assert_eq "11" "$(read_counter_value "${fixture_root}/.build_number")" "successful upload persists canonical counter after upload step"

  rm -rf "${fixture_root}"
}

# --- Skip-flag warning tests ---

test_skip_contract_check_produces_prominent_warning() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --skip-contract-check --skip-smoke-check

  assert_eq "0" "${last_exit_code}" "skip-contract-check build exits zero"
  assert_contains "${last_output}" "========" "skip-contract-check warning includes separator"
  assert_contains "${last_output}" "WARNING" "skip-contract-check warning includes WARNING label"
  assert_contains "${last_output}" "--skip-contract-check" "skip-contract-check warning names the flag"

  rm -rf "${fixture_root}"
}

test_skip_smoke_check_produces_prominent_warning() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --skip-contract-check --skip-smoke-check

  assert_eq "0" "${last_exit_code}" "skip-smoke-check build exits zero"
  assert_contains "${last_output}" "--skip-smoke-check" "skip-smoke-check warning names the flag"

  rm -rf "${fixture_root}"
}

# --- Build metadata tests ---

test_successful_build_writes_metadata_json() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --skip-contract-check --skip-smoke-check

  assert_eq "0" "${last_exit_code}" "build exits zero for metadata test"

  local metadata_file="${fixture_root}/tmp/build/build_11_metadata.json"
  if [[ ! -f "${metadata_file}" ]]; then
    echo "FAIL: metadata file not written at ${metadata_file}"
    failures=$((failures + 1))
    rm -rf "${fixture_root}"
    return
  fi

  local metadata
  metadata="$(cat "${metadata_file}")"
  assert_contains "${metadata}" '"build_number"' "metadata contains build_number field"
  assert_contains "${metadata}" '"git_sha"' "metadata contains git_sha field"
  assert_contains "${metadata}" '"timestamp"' "metadata contains timestamp field"
  assert_contains "${metadata}" '"contract_check"' "metadata contains contract_check field"
  assert_contains "${metadata}" '"smoke_check"' "metadata contains smoke_check field"

  rm -rf "${fixture_root}"
}

test_metadata_records_skip_flags() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --skip-contract-check --skip-smoke-check

  assert_eq "0" "${last_exit_code}" "build exits zero for skip-flag metadata test"

  local metadata_file="${fixture_root}/tmp/build/build_11_metadata.json"
  if [[ ! -f "${metadata_file}" ]]; then
    echo "FAIL: metadata file not written at ${metadata_file}"
    failures=$((failures + 1))
    rm -rf "${fixture_root}"
    return
  fi

  local metadata
  metadata="$(cat "${metadata_file}")"
  assert_contains "${metadata}" '"contract_check": "skipped"' "metadata records contract_check as skipped"
  assert_contains "${metadata}" '"smoke_check": "skipped"' "metadata records smoke_check as skipped"

  rm -rf "${fixture_root}"
}

test_metadata_records_smoke_stamp_sha() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  # Set up a valid smoke stamp matching HEAD
  local head_sha
  head_sha="$(git -C "${fixture_root}" rev-parse HEAD)"
  mkdir -p "${fixture_root}/tmp/devicecloud"
  echo "${head_sha}" > "${fixture_root}/tmp/devicecloud/last_passed_sha"

  run_release "${fixture_root}" --skip-contract-check

  assert_eq "0" "${last_exit_code}" "build exits zero with valid smoke stamp"

  local metadata_file="${fixture_root}/tmp/build/build_11_metadata.json"
  if [[ ! -f "${metadata_file}" ]]; then
    echo "FAIL: metadata file not written at ${metadata_file}"
    failures=$((failures + 1))
    rm -rf "${fixture_root}"
    return
  fi

  local metadata
  metadata="$(cat "${metadata_file}")"
  assert_contains "${metadata}" '"smoke_check": "passed"' "metadata records smoke_check as passed"
  assert_contains "${metadata}" "\"git_sha\": \"${head_sha}\"" "metadata records full HEAD SHA"
  assert_contains "${metadata}" "\"smoke_stamp_sha\": \"${head_sha}\"" "metadata records smoke stamp SHA"

  rm -rf "${fixture_root}"
}

test_failed_build_does_not_write_metadata() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  MOCK_BUILD_SHOULD_FAIL=1 run_release "${fixture_root}" --skip-contract-check --skip-smoke-check

  assert_eq "31" "${last_exit_code}" "failed build exits with mocked failure code"

  local metadata_file="${fixture_root}/tmp/build/build_11_metadata.json"
  if [[ -f "${metadata_file}" ]]; then
    echo "FAIL: metadata file should not exist after failed build"
    failures=$((failures + 1))
  fi

  rm -rf "${fixture_root}"
}

# --- Smoke stamp gate tests ---

test_stale_smoke_stamp_sha_fails_build() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  mkdir -p "${fixture_root}/tmp/devicecloud"
  echo "stale123" > "${fixture_root}/tmp/devicecloud/last_passed_sha"

  run_release "${fixture_root}" --skip-contract-check

  assert_eq "1" "${last_exit_code}" "stale smoke stamp exits non-zero"
  assert_contains "${last_output}" "stale123" "stale smoke stamp output mentions stamp SHA"
  assert_contains "${last_output}" "HEAD" "stale smoke stamp output mentions HEAD"

  rm -rf "${fixture_root}"
}

test_missing_smoke_stamp_fails_build() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --skip-contract-check

  assert_eq "1" "${last_exit_code}" "missing smoke stamp exits non-zero"
  assert_contains "${last_output}" "run_devicecloud_smoke.sh" "missing smoke stamp mentions the smoke script"

  rm -rf "${fixture_root}"
}

# --- Build number edge case tests ---

test_zero_build_number_file_rejected() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  echo "0" > "${fixture_root}/.build_number"
  (cd "${fixture_root}" && git add . && git commit -q -m "zero")

  run_release "${fixture_root}" --skip-contract-check --skip-smoke-check

  assert_eq "1" "${last_exit_code}" "zero in .build_number exits non-zero"
  assert_contains "${last_output}" "Invalid build counter" "zero in .build_number prints invalid counter message"

  rm -rf "${fixture_root}"
}

test_non_numeric_build_number_file_rejected() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  echo "abc" > "${fixture_root}/.build_number"
  (cd "${fixture_root}" && git add . && git commit -q -m "abc")

  run_release "${fixture_root}" --skip-contract-check --skip-smoke-check

  assert_eq "1" "${last_exit_code}" "non-numeric .build_number exits non-zero"
  assert_contains "${last_output}" "Invalid build counter" "non-numeric .build_number prints invalid counter message"

  rm -rf "${fixture_root}"
}

test_missing_build_number_file_rejected() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  rm "${fixture_root}/.build_number"
  (cd "${fixture_root}" && git add . && git commit -q --allow-empty -m "no-build-number")

  run_release "${fixture_root}" --skip-contract-check --skip-smoke-check

  assert_eq "1" "${last_exit_code}" "missing .build_number file exits non-zero"
  assert_contains "${last_output}" "Missing required tracked build counter" "missing .build_number prints missing file message"

  rm -rf "${fixture_root}"
}

test_explicit_build_number_zero_rejected() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --build-number 0 --skip-contract-check --skip-smoke-check

  assert_eq "1" "${last_exit_code}" "explicit --build-number 0 exits non-zero"
  assert_contains "${last_output}" "Invalid --build-number" "explicit --build-number 0 prints invalid message"

  rm -rf "${fixture_root}"
}

test_explicit_build_number_negative_rejected() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --build-number -1 --skip-contract-check --skip-smoke-check

  assert_eq "1" "${last_exit_code}" "explicit --build-number -1 exits non-zero"

  rm -rf "${fixture_root}"
}

test_explicit_build_number_non_numeric_rejected() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_release "${fixture_root}" --build-number abc --skip-contract-check --skip-smoke-check

  assert_eq "1" "${last_exit_code}" "explicit --build-number abc exits non-zero"
  assert_contains "${last_output}" "Invalid --build-number" "explicit --build-number abc prints invalid message"

  rm -rf "${fixture_root}"
}

main() {
  test_rejects_stale_explicit_build_number_before_secret_or_build_work
  test_accepts_higher_explicit_build_number
  test_build_only_succeeds_without_secret_file_when_env_prod_has_runtime_token
  test_omitted_build_number_auto_increments_from_stored_value
  test_build_only_persists_after_successful_build
  test_build_failure_does_not_persist_incremented_counter
  test_upload_missing_app_store_connect_credentials_fails_before_build
  test_upload_without_secret_file_fails_before_build
  test_upload_failure_does_not_persist_incremented_counter
  test_upload_success_persists_incremented_counter
  test_skip_contract_check_produces_prominent_warning
  test_skip_smoke_check_produces_prominent_warning
  test_successful_build_writes_metadata_json
  test_metadata_records_skip_flags
  test_metadata_records_smoke_stamp_sha
  test_failed_build_does_not_write_metadata
  test_stale_smoke_stamp_sha_fails_build
  test_missing_smoke_stamp_fails_build
  test_zero_build_number_file_rejected
  test_non_numeric_build_number_file_rejected
  test_missing_build_number_file_rejected
  test_explicit_build_number_zero_rejected
  test_explicit_build_number_negative_rejected
  test_explicit_build_number_non_numeric_rejected

  if [[ "${failures}" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "build_number_guard_test: PASS"
}

main "$@"
