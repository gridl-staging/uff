#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
    echo "FAIL: ${description} (should not contain '${needle}')"
    failures=$((failures + 1))
  fi
}

assert_failure() {
  local description="$1"
  shift
  if "$@" 2>/dev/null; then
    echo "FAIL: ${description} (command succeeded unexpectedly)"
    failures=$((failures + 1))
    return
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

setup_runner_fixture() {
  local fixture_root="$1"
  mkdir -p "${fixture_root}/scripts/dev" "${fixture_root}/scripts/lib"
  cp "${REPO_ROOT}/scripts/dev/run_ios_signoff_suite.sh" "${fixture_root}/scripts/dev/"
  cp "${REPO_ROOT}/scripts/lib/deployment_common.sh" "${fixture_root}/scripts/lib/"
  cp "${REPO_ROOT}/scripts/lib/simulator_control.sh" "${fixture_root}/scripts/lib/"
}

install_fake_git_short_sha() {
  local fixture_root="$1"
  local short_sha="${2:-deadbee}"
  local git_common_dir="${3:-${fixture_root}/.git}"

  mkdir -p "${fixture_root}/bin"
  mkdir -p "${git_common_dir}"
  cat > "${fixture_root}/bin/git" <<SCRIPT
#!/usr/bin/env bash
if [[ "\${1:-}" == "-C" ]]; then
  shift 2
fi
if [[ "\${1:-}" == "rev-parse" && "\${2:-}" == "--short" && "\${3:-}" == "HEAD" ]]; then
  printf '%s\n' "${short_sha}"
  exit 0
fi
if [[ "\${1:-}" == "rev-parse" && "\${2:-}" == "--git-common-dir" ]]; then
  printf '%s\n' "${git_common_dir}"
  exit 0
fi
exit 1
SCRIPT
  chmod +x "${fixture_root}/bin/git"
}

# Create e2e_test/ directory structure with empty test files for auto-discovery.
setup_e2e_fixture() {
  local fixture_root="$1"
  shift
  # Remaining args are test file paths (relative to fixture_root).
  for test_path in "$@"; do
    mkdir -p "${fixture_root}/$(dirname "${test_path}")"
    touch "${fixture_root}/${test_path}"
  done
}

# --- resolve_service_role_key tests ---

test_resolve_service_role_key_env_var_wins() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  cat > "${tmpdir}/env_file" <<'ENV'
SUPABASE_SERVICE_ROLE_KEY=from-env-file
ENV

  cat > "${tmpdir}/secret_file" <<'ENV'
SUPABASE_uff_service_role_key=from-secret-file
ENV

  local result
  result="$(SUPABASE_SERVICE_ROLE_KEY="from-env-var" resolve_service_role_key "${tmpdir}/env_file" "${tmpdir}/secret_file")"
  assert_eq "from-env-var" "$result" "resolve_service_role_key: env var beats env file and secret file"

  rm -rf "$tmpdir"
}

test_resolve_service_role_key_env_file_beats_secret() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  cat > "${tmpdir}/env_file" <<'ENV'
SUPABASE_SERVICE_ROLE_KEY=from-env-file
ENV

  cat > "${tmpdir}/secret_file" <<'ENV'
SUPABASE_uff_service_role_key=from-secret-file
ENV

  local result
  result="$(SUPABASE_SERVICE_ROLE_KEY="" resolve_service_role_key "${tmpdir}/env_file" "${tmpdir}/secret_file")"
  assert_eq "from-env-file" "$result" "resolve_service_role_key: env file beats secret file"

  rm -rf "$tmpdir"
}

test_resolve_service_role_key_secret_file_fallback() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  cat > "${tmpdir}/env_file" <<'ENV'
SUPABASE_URL=https://example.supabase.co
ENV

  cat > "${tmpdir}/secret_file" <<'ENV'
SUPABASE_uff_service_role_key=from-secret-file
ENV

  local result
  result="$(SUPABASE_SERVICE_ROLE_KEY="" resolve_service_role_key "${tmpdir}/env_file" "${tmpdir}/secret_file")"
  assert_eq "from-secret-file" "$result" "resolve_service_role_key: falls back to secret file"

  rm -rf "$tmpdir"
}

test_resolve_service_role_key_secret_file_prod_key_fallback() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  cat > "${tmpdir}/env_file" <<'ENV'
SUPABASE_URL=https://example.supabase.co
ENV

  cat > "${tmpdir}/secret_file" <<'ENV'
SUPABASE_uff_prod_project__SECRET_KEY=from-prod-secret
ENV

  local result
  result="$(SUPABASE_SERVICE_ROLE_KEY="" resolve_service_role_key "${tmpdir}/env_file" "${tmpdir}/secret_file")"
  assert_eq "from-prod-secret" "$result" "resolve_service_role_key: falls back to prod secret key"

  rm -rf "$tmpdir"
}

test_resolve_service_role_key_missing_all_returns_nonzero() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  cat > "${tmpdir}/env_file" <<'ENV'
SUPABASE_URL=https://example.supabase.co
ENV

  assert_failure "resolve_service_role_key: missing all sources returns non-zero" \
    env SUPABASE_SERVICE_ROLE_KEY="" resolve_service_role_key "${tmpdir}/env_file" "${tmpdir}/nonexistent_secret"

  rm -rf "$tmpdir"
}

# --- CLI contract tests (run against the actual runner script) ---

RUNNER="${REPO_ROOT}/scripts/dev/run_ios_signoff_suite.sh"

test_list_tests_discovers_e2e_files() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_runner_fixture "${tmpdir}"
  setup_e2e_fixture "${tmpdir}" \
    "e2e_test/smoke/auth_flow_test.dart" \
    "e2e_test/smoke/bravo_test.dart" \
    "e2e_test/smoke/alpha_test.dart" \
    "e2e_test/full/zulu_test.dart"

  local output
  output="$(cd "${tmpdir}" && bash "./scripts/dev/run_ios_signoff_suite.sh" --list-tests)"
  local expected
  # auth first, then smoke alphabetically, then full alphabetically
  expected="e2e_test/smoke/auth_flow_test.dart
e2e_test/smoke/alpha_test.dart
e2e_test/smoke/bravo_test.dart
e2e_test/full/zulu_test.dart"
  assert_eq "${expected}" "${output}" "--list-tests discovers e2e files in correct order"

  rm -rf "${tmpdir}"
}

test_list_tests_excludes_wrapper_owned_screenshot_capture_test() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_runner_fixture "${tmpdir}"
  setup_e2e_fixture "${tmpdir}" \
    "e2e_test/smoke/auth_flow_test.dart" \
    "e2e_test/smoke/screenshot_capture_test.dart" \
    "e2e_test/smoke/screenshot_capture_proof_test.dart" \
    "e2e_test/full/zulu_test.dart"

  local output
  output="$(cd "${tmpdir}" && bash "./scripts/dev/run_ios_signoff_suite.sh" --list-tests)"

  # screenshot_capture_test.dart is wrapper-owned. It waits for
  # capture_app_store_screenshots.sh to write .captured_* acknowledgements, so
  # the generic hosted signoff runner must not auto-discover it.
  assert_not_contains "${output}" "e2e_test/smoke/screenshot_capture_test.dart" \
    "--list-tests excludes the wrapper-owned screenshot capture test"
  assert_contains "${output}" "e2e_test/smoke/screenshot_capture_proof_test.dart" \
    "--list-tests keeps the hosted-safe screenshot proof coverage"

  rm -rf "${tmpdir}"
}

test_help_contains_all_flags() {
  local help_output
  help_output="$(bash "${RUNNER}" --help 2>&1)"
  assert_contains "$help_output" "--env" "--help output contains --env"
  assert_contains "$help_output" "--from-test" "--help output contains --from-test"
  assert_contains "$help_output" "--only-test" "--help output contains --only-test"
  assert_contains "$help_output" "--list-tests" "--help output contains --list-tests"
  assert_contains "$help_output" "--profile" "--help output contains --profile"
}

test_direct_entrypoint_help_succeeds() {
  local help_output=""
  local exit_code=0
  help_output="$("${RUNNER}" --help 2>&1)" || exit_code=$?

  assert_eq "0" "${exit_code}" "runner direct entrypoint exits zero for --help"
  assert_contains "${help_output}" "usage: run_ios_signoff_suite.sh [options]" \
    "runner direct entrypoint prints usage text"
}

test_invalid_env_exits_nonzero() {
  assert_failure "--env bogus exits non-zero" \
    bash "${RUNNER}" --env bogus
}

test_partial_credentials_exits_nonzero() {
  assert_failure "only E2E_TEST_EMAIL set exits non-zero" \
    env E2E_TEST_EMAIL="test@example.com" E2E_TEST_PASSWORD="" \
    bash "${RUNNER}" --env dev --list-tests
  assert_failure "only E2E_TEST_PASSWORD set exits non-zero" \
    env E2E_TEST_EMAIL="" E2E_TEST_PASSWORD="secret123" \
    bash "${RUNNER}" --env dev --list-tests
}

test_from_test_skips_earlier_tests() {
  local full_output
  full_output="$(bash "${RUNNER}" --list-tests)"
  local third_test
  third_test="$(echo "$full_output" | sed -n '3p')"
  local first_test
  first_test="$(echo "$full_output" | sed -n '1p')"

  local filtered
  filtered="$(bash "${RUNNER}" --from-test "${third_test}" --list-tests)"
  assert_not_contains "$filtered" "$first_test" "--from-test skips earlier tests"
  assert_contains "$filtered" "$third_test" "--from-test includes the named test"
}

test_discovered_tail_matches_expected_order() {
  local output
  output="$(bash "${RUNNER}" --list-tests)"

  local actual_tail
  actual_tail="$(printf '%s\n' "${output}" | tail -n 5)"
  # Smoke tests alphabetically, then full tests alphabetically.
  local expected_tail
  expected_tail="e2e_test/smoke/social_feed_test.dart
e2e_test/full/import_zip_flow_test.dart
e2e_test/full/privacy_zone_test.dart
e2e_test/full/social_relationships_and_kudos_test.dart
e2e_test/full/visibility_matrix_cross_user_test.dart"

  assert_eq "${expected_tail}" "${actual_tail}" \
    "discovered test list ends with expected full/ tests"
}

test_from_test_social_feed_targets_exact_tail() {
  local output
  output="$(bash "${RUNNER}" --from-test e2e_test/smoke/social_feed_test.dart --list-tests)"

  local expected_tail
  expected_tail="e2e_test/smoke/social_feed_test.dart
e2e_test/full/import_zip_flow_test.dart
e2e_test/full/privacy_zone_test.dart
e2e_test/full/social_relationships_and_kudos_test.dart
e2e_test/full/visibility_matrix_cross_user_test.dart"

  assert_eq "${expected_tail}" "${output}" \
    "--from-test social_feed_test.dart resolves to the exact tail"
}

test_only_test_runs_single_test() {
  local full_output
  full_output="$(bash "${RUNNER}" --list-tests)"
  local second_test
  second_test="$(echo "$full_output" | sed -n '2p')"

  local filtered
  filtered="$(bash "${RUNNER}" --only-test "${second_test}" --list-tests)"
  assert_eq "$second_test" "$filtered" "--only-test returns exactly one test"
}

test_from_test_invalid_path_exits_nonzero() {
  local missing_path="nonexistent/test.dart"
  local output=""
  local exit_code=0
  output="$(bash "${RUNNER}" --from-test "${missing_path}" --list-tests 2>&1)" || exit_code=$?

  assert_eq "1" "${exit_code}" "--from-test with invalid path exits non-zero"
  assert_contains "${output}" "Error: --from-test path not found in e2e_test/: ${missing_path}" \
    "--from-test with invalid path prints clear error text"
}

test_only_test_invalid_path_exits_nonzero() {
  local missing_path="nonexistent/test.dart"
  local output=""
  local exit_code=0
  output="$(bash "${RUNNER}" --only-test "${missing_path}" --list-tests 2>&1)" || exit_code=$?

  assert_eq "1" "${exit_code}" "--only-test with invalid path exits non-zero"
  assert_contains "${output}" "Error: --only-test path not found in e2e_test/: ${missing_path}" \
    "--only-test with invalid path prints clear error text"
}

test_missing_e2e_dir_exits_cleanly() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_runner_fixture "${tmpdir}"
  # Do NOT create e2e_test/ directory.

  local output=""
  local exit_code=0
  output="$(cd "${tmpdir}" && bash "./scripts/dev/run_ios_signoff_suite.sh" --list-tests 2>&1)" || exit_code=$?

  assert_eq "1" "${exit_code}" "--list-tests exits non-zero when e2e_test/ is missing"
  assert_contains "${output}" "e2e_test/ directory not found" "--list-tests reports missing e2e_test/"
  assert_not_contains "${output}" "unbound variable" "--list-tests does not leak bash unbound-variable errors"

  rm -rf "${tmpdir}"
}

test_empty_e2e_dir_exits_cleanly() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_runner_fixture "${tmpdir}"
  mkdir -p "${tmpdir}/e2e_test/smoke" "${tmpdir}/e2e_test/full"
  # Directories exist but contain no *_test.dart files.

  local output=""
  local exit_code=0
  output="$(cd "${tmpdir}" && bash "./scripts/dev/run_ios_signoff_suite.sh" --list-tests 2>&1)" || exit_code=$?

  assert_eq "1" "${exit_code}" "--list-tests exits non-zero when e2e_test/ is empty"
  assert_contains "${output}" "No e2e test files found" "--list-tests reports empty e2e_test/"
  assert_not_contains "${output}" "unbound variable" "runner does not leak bash unbound-variable errors for empty e2e_test/"

  rm -rf "${tmpdir}"
}

test_from_test_executes_tail_in_order_and_json_counts() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_runner_fixture "${tmpdir}"
  install_fake_git_short_sha "${tmpdir}"

  # Create e2e_test/ directory structure for auto-discovery.
  setup_e2e_fixture "${tmpdir}" \
    "e2e_test/smoke/analytics_metrics_test.dart" \
    "e2e_test/smoke/auto_pause_flow_test.dart" \
    "e2e_test/smoke/import_flow_test.dart" \
    "e2e_test/smoke/recording_flow_test.dart" \
    "e2e_test/smoke/recording_pause_resume_test.dart" \
    "e2e_test/smoke/social_feed_test.dart" \
    "e2e_test/full/privacy_zone_test.dart" \
    "e2e_test/full/social_relationships_and_kudos_test.dart"

  local args_log="${tmpdir}/invoked_args.log"
  cat > "${tmpdir}/scripts/dev/patrol_fast.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${RUNNER_ARGS_LOG}"
target=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t)
      target="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s\n' "${target}" >> "${RUNNER_AUDIT_LOG}"
exit 0
SCRIPT
  chmod +x "${tmpdir}/scripts/dev/patrol_fast.sh"

  local audit_log="${tmpdir}/invoked_tests.log"
  local output=""
  local exit_code=0
  output="$(
    cd "${tmpdir}" &&
    PATH="${tmpdir}/bin:${PATH}" RUNNER_AUDIT_LOG="${audit_log}" \
    RUNNER_ARGS_LOG="${args_log}" \
    bash "./scripts/dev/run_ios_signoff_suite.sh" --env dev --device "Fixture iPhone" \
      --from-test e2e_test/smoke/social_feed_test.dart 2>&1
  )" || exit_code=$?

  assert_eq "0" "${exit_code}" "runner succeeds for mocked --from-test tail rerun"
  assert_contains "${output}" "Signoff summary: 3/3 passed" \
    "runner reports expected pass count for tail rerun"

  local actual_invocations
  actual_invocations="$(cat "${audit_log}")"
  # Alphabetical: social_feed (last smoke), then full/ alphabetically
  local expected_tail
  expected_tail="e2e_test/smoke/social_feed_test.dart
e2e_test/full/privacy_zone_test.dart
e2e_test/full/social_relationships_and_kudos_test.dart"
  assert_eq "${expected_tail}" "${actual_invocations}" \
    "runner executes tail tests in discovered order after --from-test"

  local json_file
  json_file="$(ls "${tmpdir}"/tmp/signoff/signoff_*_deadbee.json 2>/dev/null | head -n 1)"
  if [[ -z "${json_file}" ]]; then
    echo "FAIL: runner writes signoff JSON artifact for --from-test rerun"
    failures=$((failures + 1))
    rm -rf "${tmpdir}"
    return
  fi

  local parsed_output
  parsed_output="$(python3 - <<'PY' "${json_file}"
import json
import sys

data = json.load(open(sys.argv[1]))
print(data["tests_attempted"])
print(data["tests_passed"])
print(data["tests_failed"])
print(len(data["results"]))
print(data["results"][0]["test"])
PY
)"

  local expected_parsed
  expected_parsed='3
3
0
3
e2e_test/smoke/social_feed_test.dart'
  assert_eq "${expected_parsed}" "${parsed_output}" \
    "runner JSON artifact reports accurate tail counts and first test"

  # Verify --no-uninstall is passed on every patrol invocation.
  local missing_no_uninstall=0
  while IFS= read -r invocation; do
    if [[ "${invocation}" != *"--no-uninstall"* ]]; then
      missing_no_uninstall=$((missing_no_uninstall + 1))
    fi
  done < "${args_log}"
  assert_eq "0" "${missing_no_uninstall}" \
    "runner passes --no-uninstall on every patrol invocation"
  local dart_define_arg_count=0
  while IFS= read -r invocation; do
    if [[ "${invocation}" == *"--dart-define-from-file="* ]]; then
      dart_define_arg_count=$((dart_define_arg_count + 1))
    fi
  done < "${args_log}"
  assert_eq "3" "${dart_define_arg_count}" \
    "runner passes dart defines via file on every patrol invocation"

  rm -rf "${tmpdir}"
}

test_profile_mode_prints_per_file_table_with_totals() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_runner_fixture "${tmpdir}"
  install_fake_git_short_sha "${tmpdir}"

  setup_e2e_fixture "${tmpdir}" \
    "e2e_test/smoke/auth_flow_test.dart" \
    "e2e_test/full/privacy_zone_test.dart"

  cat > "${tmpdir}/scripts/dev/patrol_fast.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "${tmpdir}/scripts/dev/patrol_fast.sh"

  local output=""
  local exit_code=0
  output="$(
    cd "${tmpdir}" &&
    PATH="${tmpdir}/bin:${PATH}" \
    bash "./scripts/dev/run_ios_signoff_suite.sh" --env dev --device "Fixture iPhone" --profile 2>&1
  )" || exit_code=$?

  assert_eq "0" "${exit_code}" "runner succeeds when --profile is enabled"
  assert_contains "${output}" "Profile summary (from signoff JSON payload):" \
    "runner prints profile summary heading"
  assert_contains "${output}" "[profile] TEST FILE" \
    "runner profile output includes table header row"
  assert_contains "${output}" "[profile] e2e_test/smoke/auth_flow_test.dart" \
    "runner profile output includes smoke test row"
  assert_contains "${output}" "[profile] e2e_test/full/privacy_zone_test.dart" \
    "runner profile output includes full test row"
  assert_contains "${output}" "[profile] TOTAL" \
    "runner profile output includes total duration row"
  assert_contains "${output}" "[profile] AVERAGE" \
    "runner profile output includes average duration row"

  local profile_test_rows
  profile_test_rows="$(printf '%s\n' "${output}" | grep -c '^\[profile\] e2e_test/' || true)"
  assert_eq "2" "${profile_test_rows}" \
    "runner profile output prints one per-file row per executed test"

  rm -rf "${tmpdir}"
}

test_signoff_copies_missing_firebase_config_from_primary_checkout() {
  local tmpdir
  local primary_root
  tmpdir="$(mktemp -d)"
  primary_root="$(mktemp -d)"
  setup_runner_fixture "${tmpdir}"
  install_fake_git_short_sha "${tmpdir}" "deadbee" "${primary_root}/.git"

  setup_e2e_fixture "${tmpdir}" "e2e_test/smoke/only_test.dart"

  mkdir -p "${tmpdir}/ios/Runner" "${tmpdir}/android/app"
  mkdir -p "${primary_root}/ios/Runner" "${primary_root}/android/app"

  printf '%s\n' '<plist>primary-ios</plist>' > "${primary_root}/ios/Runner/GoogleService-Info.plist"
  printf '%s\n' '{"project_info":"primary-android"}' > "${primary_root}/android/app/google-services.json"

  cat > "${tmpdir}/scripts/dev/patrol_fast.sh" <<'SCRIPT'
#!/usr/bin/env bash
if [[ ! -f "${PWD}/ios/Runner/GoogleService-Info.plist" ]]; then
  echo "missing iOS Firebase config" >&2
  exit 41
fi
printf '%s\n' "patrol-ran" > "${PATROL_MARKER}"
exit 0
SCRIPT
  chmod +x "${tmpdir}/scripts/dev/patrol_fast.sh"

  local patrol_marker="${tmpdir}/patrol_called.txt"
  local output=""
  local exit_code=0
  output="$(
    cd "${tmpdir}" &&
    PATH="${tmpdir}/bin:${PATH}" PATROL_MARKER="${patrol_marker}" \
    bash "./scripts/dev/run_ios_signoff_suite.sh" --env dev --device "Fixture iPhone" 2>&1
  )" || exit_code=$?

  assert_eq "0" "${exit_code}" \
    "runner succeeds when Firebase configs are available only in primary checkout"
  assert_success "runner copies iOS Firebase config from primary checkout before patrol" \
    test -f "${tmpdir}/ios/Runner/GoogleService-Info.plist"
  assert_eq "<plist>primary-ios</plist>" "$(cat "${tmpdir}/ios/Runner/GoogleService-Info.plist")" \
    "runner materializes the primary-checkout iOS Firebase config into the lean worktree"
  assert_success "runner reaches patrol after materializing Firebase config" \
    test -f "${patrol_marker}"
  assert_not_contains "${output}" "missing iOS Firebase config" \
    "runner avoids patrol failure once the Firebase plist is materialized"

  rm -rf "${tmpdir}" "${primary_root}"
}

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/tests/run_ios_signoff_suite_hosted_cases.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/tests/run_ios_signoff_suite_interruption_cases.sh"

main() {
  test_resolve_service_role_key_env_var_wins
  test_resolve_service_role_key_env_file_beats_secret
  test_resolve_service_role_key_secret_file_fallback
  test_resolve_service_role_key_secret_file_prod_key_fallback
  test_resolve_service_role_key_missing_all_returns_nonzero
  test_list_tests_discovers_e2e_files
  test_list_tests_excludes_wrapper_owned_screenshot_capture_test
  test_help_contains_all_flags
  test_direct_entrypoint_help_succeeds
  test_invalid_env_exits_nonzero
  test_partial_credentials_exits_nonzero
  test_from_test_skips_earlier_tests
  test_discovered_tail_matches_expected_order
  test_from_test_social_feed_targets_exact_tail
  test_only_test_runs_single_test
  test_from_test_invalid_path_exits_nonzero
  test_only_test_invalid_path_exits_nonzero
  test_missing_e2e_dir_exits_cleanly
  test_empty_e2e_dir_exits_cleanly
  test_from_test_executes_tail_in_order_and_json_counts
  test_profile_mode_prints_per_file_table_with_totals
  test_signoff_copies_missing_firebase_config_from_primary_checkout
  test_hosted_explicit_credentials_skip_bootstrap_when_service_key_present
  test_hosted_explicit_credentials_without_service_key_fail_fast
  test_hosted_missing_env_file_fails_before_expensive_work
  test_missing_device_uses_worktree_simulator_script
  test_missing_device_shuts_down_simulator_booted_by_helper
  test_missing_device_leaves_prebooted_simulator_running
  test_bootstrap_parser_reads_expected_exports
  test_bootstrap_parser_rejects_non_export_shell
  test_bootstrap_stderr_not_in_sourced_file
  test_runner_bootstrap_stderr_is_not_silenced
  test_runner_bootstrap_temp_file_is_removed_on_parse_failure
  test_json_summary_contains_required_keys
  test_json_summary_contains_no_secrets
  test_json_summary_escapes_string_values
  test_runner_writes_json_summary_artifact_after_mocked_run
  test_runner_passes_secret_defines_via_file_not_argv
  test_runner_passes_project_root_dart_define
  test_runner_json_artifact_records_failure_reason
  test_runner_interrupted_run_expected_to_write_json_summary

  if [[ "$failures" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "run_ios_signoff_suite_test: PASS"
}

main "$@"
