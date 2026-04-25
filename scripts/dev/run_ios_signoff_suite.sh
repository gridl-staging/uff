#!/usr/bin/env bash
set -euo pipefail

build_patrol_log_file() {
  local output_dir="$1"
  local test_path="$2"
  local safe_name

  safe_name="$(printf '%s' "${test_path}" | sed 's#[^A-Za-z0-9._-]#_#g')"
  printf '%s/%s.log\n' "${output_dir}" "${safe_name}"
}

now_ms() {
  python3 - <<'PY'
import time

print(int(time.time() * 1000))
PY
}

# TODO: Document print_profile_summary.
print_profile_summary() {
  local test_results_json="$1"
  python3 - "$test_results_json" <<'PY'
import json
import sys


def safe_duration(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


try:
    parsed = json.loads(sys.argv[1])
except (IndexError, json.JSONDecodeError):
    parsed = []

if not isinstance(parsed, list):
    parsed = []

rows = []
total_duration_ms = 0
for item in parsed:
    if not isinstance(item, dict):
        continue
    test_name = str(item.get("test", ""))
    status = str(item.get("status", ""))
    duration_ms = safe_duration(item.get("duration_ms", 0))
    rows.append((test_name, status, duration_ms))
    total_duration_ms += duration_ms

average_duration_ms = total_duration_ms // len(rows) if rows else 0

test_header = "TEST FILE"
status_header = "STATUS"
duration_header = "DURATION_MS"

test_width = max(
    len(test_header),
    len("TOTAL"),
    len("AVERAGE"),
    *(len(test) for test, _status, _duration in rows),
)
status_width = max(
    len(status_header),
    len("-"),
    *(len(status) for _test, status, _duration in rows),
)
duration_width = max(
    len(duration_header),
    len(str(total_duration_ms)),
    len(str(average_duration_ms)),
    *(len(str(duration)) for _test, _status, duration in rows),
)


def print_row(name, status, duration):
    print(
        "[profile] "
        + f"{name:<{test_width}}  {status:<{status_width}}  {duration:>{duration_width}}"
    )


print("Profile summary (from signoff JSON payload):")
print_row(test_header, status_header, duration_header)
print_row("-" * test_width, "-" * status_width, "-" * duration_width)
for test_name, status, duration_ms in rows:
    print_row(test_name, status, str(duration_ms))
print_row("TOTAL", "-", str(total_duration_ms))
print_row("AVERAGE", "-", str(average_duration_ms))
PY
}

# TODO: Document usage.
usage() {
  cat <<'EOF'
usage: run_ios_signoff_suite.sh [options]

Runs the repo-owned high-value iOS Patrol signoff suite in a stable order.
Tests are auto-discovered from e2e_test/ (no manifest file to maintain).

Options:
  --env dev|staging|prod   Target environment (default: dev)
  --device <name-or-udid>  iOS simulator to use
  --list-tests             Print the discovered test list and exit
  --from-test <path>       Start from this test (skip earlier tests)
  --only-test <path>       Run only this single test
  --profile                Print per-test duration table from JSON payload
  -h, --help               Show this help

Environment behavior:
  --env dev      uses .env.dev (default)
  --env staging  uses .env.staging
  --env prod     uses .env.prod

Optional hosted-account overrides:
  Set E2E_TEST_EMAIL and E2E_TEST_PASSWORD in the shell to force Patrol to use
  an existing account instead of creating throwaway credentials during setup.

Hosted auto-provisioning:
  If --env is staging or prod and E2E_TEST_EMAIL / E2E_TEST_PASSWORD are not
  already set, the script will try to create a confirmed hosted test user via
  scripts/dev/prepare_hosted_test_user.sh when SUPABASE_SERVICE_ROLE_KEY is
  available in the shell or target env file.
EOF
}

app_env="dev"
device=""
list_tests=false
from_test=""
only_test=""
profile=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      app_env="${2:-}"
      shift 2
      ;;
    --device)
      device="${2:-}"
      shift 2
      ;;
    --list-tests)
      list_tests=true
      shift
      ;;
    --from-test)
      from_test="${2:-}"
      shift 2
      ;;
    --only-test)
      only_test="${2:-}"
      shift 2
      ;;
    --profile)
      profile=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "${app_env}" in
  dev|staging|prod)
    ;;
  *)
    printf 'Unsupported --env value: %s\n' "${app_env}" >&2
    exit 1
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
# shellcheck source=/dev/null
source "${repo_root}/scripts/lib/simulator_control.sh"

temp_files=()
tests=()
helper_owned_simulator_udid=""
helper_owned_simulator_booted_by_this_run="false"

cleanup_temp_files() {
  local temp_file
  if ! declare -p temp_files >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${#temp_files[@]}" -eq 0 ]]; then
    return 0
  fi
  for temp_file in "${temp_files[@]}"; do
    [[ -n "${temp_file}" ]] && rm -f "${temp_file}"
  done
  return 0
}

cleanup_signoff_run() {
  cleanup_temp_files
  shutdown_simulator_if_owned "${helper_owned_simulator_udid}" "${helper_owned_simulator_booted_by_this_run}"
}

trap cleanup_signoff_run EXIT

is_wrapper_owned_test() {
  local test_path="$1"

  case "${test_path}" in
    # This flow coordinates with capture_app_store_screenshots.sh via
    # .ready_* / .captured_* sentinel files. Running it inside the generic
    # hosted signoff runner can never pass because no capture loop is present
    # to acknowledge the requested screenshots.
    e2e_test/smoke/screenshot_capture_test.dart)
      return 0
      ;;
  esac

  return 1
}

append_discovered_tests() {
  local search_dir="$1"
  local skip_test="${2:-}"
  local discovered_test

  while IFS= read -r discovered_test; do
    [[ -z "${discovered_test}" ]] && continue
    [[ -n "${skip_test}" && "${discovered_test}" == "${skip_test}" ]] && continue
    if is_wrapper_owned_test "${discovered_test}"; then
      continue
    fi
    tests+=("${discovered_test}")
  done < <(find "${search_dir}" -name '*_test.dart' -type f 2>/dev/null | sort)
}

has_discovered_test() {
  local expected_test="$1"
  local discovered_test

  for discovered_test in "${tests[@]}"; do
    if [[ "${discovered_test}" == "${expected_test}" ]]; then
      return 0
    fi
  done

  return 1
}

# TODO: Document filter_tests_from.
filter_tests_from() {
  local start_test="$1"
  local filtered_tests=()
  local include_test=false
  local discovered_test

  for discovered_test in "${tests[@]}"; do
    if [[ "${discovered_test}" == "${start_test}" ]]; then
      include_test=true
    fi
    if [[ "${include_test}" == true ]]; then
      filtered_tests+=("${discovered_test}")
    fi
  done

  tests=("${filtered_tests[@]}")
}

# shellcheck source=/dev/null
source "${repo_root}/scripts/lib/deployment_common.sh"

env_file="${repo_root}/$(resolve_env_file_path "${app_env}")"
secret_source_file="${repo_root}/.secret/.env.secret"

# resolve_service_role_key is now in scripts/lib/deployment_common.sh
# Called as: resolve_service_role_key "$env_file" "$secret_source_file"

# Auto-discover hosted-safe e2e tests from the filesystem. No manifest file to
# maintain. Wrapper-owned flows stay on their dedicated entrypoints so signoff
# only includes tests that can pass in this environment.
# Order: auth_flow_test first (critical gate), then other smoke/ tests
# alphabetically, then full/ tests alphabetically.
e2e_dir="${repo_root}/e2e_test"
if [[ ! -d "${e2e_dir}" ]]; then
  printf 'e2e_test/ directory not found at %s\n' "${e2e_dir}" >&2
  exit 1
fi

# auth_flow_test is always first — if auth is broken, nothing else matters.
auth_test="e2e_test/smoke/auth_flow_test.dart"
if [[ -f "${repo_root}/${auth_test}" ]]; then
  tests+=("${auth_test}")
fi

# Remaining smoke/ tests alphabetically (skip auth_flow_test, already added).
append_discovered_tests "e2e_test/smoke" "${auth_test}"

# full/ tests alphabetically.
append_discovered_tests "e2e_test/full"

if [[ "${#tests[@]}" -eq 0 ]]; then
  printf 'No e2e test files found in %s\n' "${e2e_dir}" >&2
  exit 1
fi

# Validate and apply --from-test / --only-test filters before --list-tests
# so --list-tests shows the effective test list after filtering
if [[ -n "${from_test}" ]]; then
  if ! has_discovered_test "${from_test}"; then
    printf 'Error: --from-test path not found in e2e_test/: %s\n' "${from_test}" >&2
    exit 1
  fi
  filter_tests_from "${from_test}"
fi

if [[ -n "${only_test}" ]]; then
  if ! has_discovered_test "${only_test}"; then
    printf 'Error: --only-test path not found in e2e_test/: %s\n' "${only_test}" >&2
    exit 1
  fi
  tests=("${only_test}")
fi

# Validate credentials early: both or neither must be set
if [[ -n "${E2E_TEST_EMAIL:-}" || -n "${E2E_TEST_PASSWORD:-}" ]]; then
  if [[ -z "${E2E_TEST_EMAIL:-}" || -z "${E2E_TEST_PASSWORD:-}" ]]; then
    printf 'Set both E2E_TEST_EMAIL and E2E_TEST_PASSWORD together.\n' >&2
    exit 1
  fi
fi

if [[ "${list_tests}" == true ]]; then
  printf '%s\n' "${tests[@]}"
  exit 0
fi

if [[ "${app_env}" != "dev" && ! -f "${env_file}" ]]; then
  printf 'Missing env file: %s\n' "${env_file}" >&2
  exit 1
fi

# Hosted signoff commonly runs from a lean mobile worktree that does not keep
# gitignored Firebase configs checked in. Reuse the same primary-checkout
# materialization path as release builds so signoff and TestFlight agree on how
# those native prerequisites reach the worktree.
materialize_shared_firebase_configs_from_primary_checkout "${repo_root}"

if [[ -z "${device}" ]]; then
  simulator_metadata="$(resolve_worktree_simulator_metadata "${script_dir}/ensure_worktree_ios_simulator.sh")"
  device="$(simulator_metadata_field "${simulator_metadata}" "udid")"
  helper_owned_simulator_udid="${device}"
  helper_owned_simulator_booted_by_this_run="$(simulator_metadata_field "${simulator_metadata}" "booted_by_this_run")"
fi

dart_define_pairs=(
  "APP_ENV" "${app_env}"
)

if [[ "${app_env}" != "dev" && (-z "${E2E_TEST_EMAIL:-}" || -z "${E2E_TEST_PASSWORD:-}") ]]; then
  # Safe bootstrap: capture only stdout to a temp file, then parse only the
  # expected export statements. Do not execute helper output as shell code.
  bootstrap_tmp="$(mktemp)"
  temp_files+=("${bootstrap_tmp}")
  if ! "${script_dir}/prepare_hosted_test_user.sh" --env "${app_env}" > "${bootstrap_tmp}"; then
    printf '%s\n' \
      "Hosted signoff needs either E2E_TEST_EMAIL / E2E_TEST_PASSWORD or a working SUPABASE_SERVICE_ROLE_KEY so it can auto-create a confirmed hosted test user." >&2
    exit 1
  fi

  if ! E2E_TEST_EMAIL="$(read_bootstrap_export_value "${bootstrap_tmp}" "E2E_TEST_EMAIL")" || \
    ! E2E_TEST_PASSWORD="$(read_bootstrap_export_value "${bootstrap_tmp}" "E2E_TEST_PASSWORD")"; then
    printf '%s\n' \
      "Hosted signoff could not load bootstrap exports from prepare_hosted_test_user.sh." >&2
    exit 1
  fi
  bootstrap_service_role=""
  if bootstrap_service_role="$(read_bootstrap_export_value "${bootstrap_tmp}" "SUPABASE_SERVICE_ROLE_KEY" 2>/dev/null)"; then
    export SUPABASE_SERVICE_ROLE_KEY="${bootstrap_service_role}"
  fi
fi

if [[ "${app_env}" != "dev" ]]; then
  if ! SUPABASE_SERVICE_ROLE_KEY="$(resolve_service_role_key "${env_file}" "${secret_source_file}")"; then
    printf '%s\n' \
      "Hosted social signoff needs SUPABASE_SERVICE_ROLE_KEY so seeded users can bypass normal email signup limits." >&2
    exit 1
  fi
  export SUPABASE_SERVICE_ROLE_KEY
  dart_define_pairs+=("SUPABASE_SERVICE_ROLE_KEY" "${SUPABASE_SERVICE_ROLE_KEY}")
fi

# Credential validation already done above; just add dart defines if set
if [[ -n "${E2E_TEST_EMAIL:-}" && -n "${E2E_TEST_PASSWORD:-}" ]]; then
  dart_define_pairs+=(
    "E2E_TEST_EMAIL" "${E2E_TEST_EMAIL}"
    "E2E_TEST_PASSWORD" "${E2E_TEST_PASSWORD}"
  )
fi

dart_define_file="$(mktemp)"
temp_files+=("${dart_define_file}")
write_dart_define_file "${dart_define_file}" "${dart_define_pairs[@]}"
dart_define_args=(
  "--dart-define-from-file=${dart_define_file}"
  "--dart-define=PROJECT_ROOT=${repo_root}"
)

cd "${repo_root}"

printf 'Using iOS simulator: %s\n' "${device}"
printf 'Using app env: %s\n' "${app_env}"

signoff_timestamp="$(date +%s)"
signoff_sha="$(git rev-parse --short HEAD)"
signoff_dir="${repo_root}/tmp/signoff"
patrol_output_dir="${signoff_dir}/patrol_${signoff_timestamp}_${signoff_sha}"
mkdir -p "${patrol_output_dir}"
json_report_path="${signoff_dir}/signoff_${signoff_timestamp}_${signoff_sha}.json"

# Track per-test results for JSON summary
tests_passed=0
tests_failed=0
test_results_json="["
signoff_finalized=false
current_test_path=""
current_test_log_file=""
current_test_started_ms=""
current_test_result_recorded=true
current_patrol_pid=""
json_report_line_printed=false

# TODO: Document append_test_result.
append_test_result() {
  local test_path="$1"
  local test_status="$2"
  local test_duration_ms="$3"
  local test_failure_reason="${4:-}"
  local escaped_test_path
  escaped_test_path="$(json_quote "${test_path}")"

  if [[ "${test_status}" == "pass" ]]; then
    tests_passed=$((tests_passed + 1))
    test_results_json="${test_results_json}{\"test\":${escaped_test_path},\"status\":\"pass\",\"duration_ms\":${test_duration_ms}},"
    return 0
  fi

  tests_failed=$((tests_failed + 1))
  local failure_reason_json
  failure_reason_json="$(json_quote "${test_failure_reason}")"
  test_results_json="${test_results_json}{\"test\":${escaped_test_path},\"status\":\"fail\",\"reason\":${failure_reason_json},\"duration_ms\":${test_duration_ms}},"
}

print_json_report_path() {
  if [[ "${json_report_line_printed}" == true ]]; then
    return 0
  fi
  json_report_line_printed=true
  printf 'JSON report: %s\n' "${json_report_path}"
}

# TODO: Document write_inflight_signoff_summary.
write_inflight_signoff_summary() {
  local inflight_finished_ms
  local inflight_duration_ms=0
  local inflight_reason_json
  local escaped_test_path
  local inflight_results_json
  local inflight_tests_failed=0
  local inflight_tests_attempted=0

  if [[ -z "${current_test_path}" || "${current_test_result_recorded}" == true ]]; then
    return 0
  fi

  if [[ -n "${current_test_started_ms}" ]]; then
    inflight_finished_ms="$(now_ms)"
    inflight_duration_ms="$((inflight_finished_ms - current_test_started_ms))"
  fi

  escaped_test_path="$(json_quote "${current_test_path}")"
  inflight_reason_json="$(json_quote "runner interrupted by an external signal; see ${current_test_log_file}")"
  inflight_results_json="${test_results_json}{\"test\":${escaped_test_path},\"status\":\"fail\",\"reason\":${inflight_reason_json},\"duration_ms\":${inflight_duration_ms}},"
  inflight_results_json="${inflight_results_json%,}]"
  inflight_tests_failed=$((tests_failed + 1))
  inflight_tests_attempted=$((tests_passed + inflight_tests_failed))

  write_signoff_summary "${signoff_dir}" "${signoff_timestamp}" "${signoff_sha}" \
    "${app_env}" "${device}" "${inflight_tests_attempted}" "${tests_passed}" "${inflight_tests_failed}" \
    "${inflight_results_json}" "${patrol_output_dir}"
}

# TODO: Document finalize_signoff_summary.
finalize_signoff_summary() {
  local interrupted_run="${1:-false}"
  local interrupt_signal="${2:-}"
  local final_test_results_json
  local tests_attempted=0

  if [[ "${signoff_finalized}" == true ]]; then
    return 0
  fi
  signoff_finalized=true

  if [[ "${interrupted_run}" == true && -n "${current_test_path}" && "${current_test_result_recorded}" != true ]]; then
    local interrupted_finished_ms
    local interrupted_duration_ms=0
    local interrupted_reason="runner interrupted by SIG${interrupt_signal}"
    if [[ -n "${current_test_log_file}" ]]; then
      interrupted_reason="${interrupted_reason}; see ${current_test_log_file}"
    fi
    if [[ -n "${current_test_started_ms}" ]]; then
      interrupted_finished_ms="$(now_ms)"
      interrupted_duration_ms="$((interrupted_finished_ms - current_test_started_ms))"
    fi
    append_test_result "${current_test_path}" "fail" "${interrupted_duration_ms}" "${interrupted_reason}"
    current_test_result_recorded=true
  fi

  if [[ "${test_results_json}" == "[" ]]; then
    final_test_results_json="[]"
  else
    final_test_results_json="${test_results_json%,}]"
  fi
  tests_attempted=$((tests_passed + tests_failed))

  write_signoff_summary "${signoff_dir}" "${signoff_timestamp}" "${signoff_sha}" \
    "${app_env}" "${device}" "${tests_attempted}" "${tests_passed}" "${tests_failed}" \
    "${final_test_results_json}" "${patrol_output_dir}"

  if [[ "${profile}" == true ]]; then
    print_profile_summary "${final_test_results_json}"
  fi

  printf '\nSignoff summary: %s/%s passed\n' "${tests_passed}" "${tests_attempted}"
  print_json_report_path
}

# TODO: Document handle_signoff_interrupt.
handle_signoff_interrupt() {
  local interrupt_signal="$1"
  local finalize_status=0
  # Traps run while set -e is active. Disable it here so interrupt finalization
  # always attempts to persist partial results before exiting.
  set +e
  if [[ -n "${current_patrol_pid}" ]]; then
    kill -TERM "${current_patrol_pid}" 2>/dev/null || true
  fi
  finalize_signoff_summary true "${interrupt_signal}"
  finalize_status=$?
  set -e
  if [[ "${finalize_status}" -ne 0 ]]; then
    exit "${finalize_status}"
  fi
  exit 1
}

trap 'handle_signoff_interrupt TERM' TERM
trap 'handle_signoff_interrupt INT' INT
trap 'handle_signoff_interrupt HUP' HUP

print_json_report_path

for test_path in "${tests[@]}"; do
  printf '\n==> %s\n' "${test_path}"
  current_test_path="${test_path}"
  test_log_file="$(build_patrol_log_file "${patrol_output_dir}" "${test_path}")"
  current_test_log_file="${test_log_file}"
  test_started_ms="$(now_ms)"
  current_test_started_ms="${test_started_ms}"
  current_test_result_recorded=false
  write_inflight_signoff_summary
  patrol_status=0
  set +e
  (
    "${script_dir}/patrol_fast.sh" test \
      --no-uninstall \
      -t "${test_path}" \
      -d "${device}" \
      "${dart_define_args[@]}" 2>&1 | tee "${test_log_file}"
  ) &
  current_patrol_pid="$!"
  wait "${current_patrol_pid}"
  patrol_status="$?"
  current_patrol_pid=""
  set -e
  test_finished_ms="$(now_ms)"
  test_duration_ms="$((test_finished_ms - test_started_ms))"
  printf '[timing] %s took %sms\n' "${test_path}" "${test_duration_ms}"
  if [[ "${patrol_status}" -eq 0 ]]; then
    append_test_result "${test_path}" "pass" "${test_duration_ms}"
  else
    append_test_result "${test_path}" "fail" "${test_duration_ms}" \
      "patrol exited with status ${patrol_status}; see ${test_log_file}"
  fi
  current_test_result_recorded=true
done

finalize_signoff_summary false ""

if [[ "${tests_failed}" -gt 0 ]]; then
  exit 1
fi
