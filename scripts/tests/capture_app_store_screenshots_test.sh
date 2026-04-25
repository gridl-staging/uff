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

assert_file_contains() {
  local file_path="$1"
  local needle="$2"
  local description="$3"
  if [[ ! -f "${file_path}" ]]; then
    echo "FAIL: ${description} (missing file '${file_path}')"
    failures=$((failures + 1))
    return 0
  fi

  local contents=""
  contents="$(cat "${file_path}")"
  assert_contains "${contents}" "${needle}" "${description}"
}

setup_fixture() {
  local patrol_mode="${1:-ready_screens}"
  local fixture_root
  fixture_root="$(mktemp -d)"

  mkdir -p "${fixture_root}/scripts/dev" "${fixture_root}/scripts/lib" "${fixture_root}/bin"
  cp "${REPO_ROOT}/scripts/dev/capture_app_store_screenshots.sh" "${fixture_root}/scripts/dev/"
  cp "${REPO_ROOT}/scripts/dev/check_local_docker_engine.sh" "${fixture_root}/scripts/dev/"
  cp "${REPO_ROOT}/scripts/lib/deployment_common.sh" "${fixture_root}/scripts/lib/"
  chmod +x "${fixture_root}/scripts/dev/capture_app_store_screenshots.sh"
  chmod +x "${fixture_root}/scripts/dev/check_local_docker_engine.sh"
  printf 'SUPABASE_URL=http://127.0.0.1:54321\nSUPABASE_ANON_KEY=test-key\n' > "${fixture_root}/.env.dev"
  printf 'SUPABASE_URL=http://127.0.0.1:54321\nSUPABASE_ANON_KEY=test-key\n' > "${fixture_root}/.env.staging"
  printf 'SUPABASE_URL=http://127.0.0.1:54321\nSUPABASE_ANON_KEY=test-key\n' > "${fixture_root}/.env.prod"

  case "${patrol_mode}" in
    ready_screens)
cat > "${fixture_root}/scripts/dev/patrol_fast.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
screenshot_dir="${repo_root}/tmp/screenshots"
screens=("activity-recording" "activity-detail" "analytics-dashboard" "social-feed" "activity-photo")
mkdir -p "${screenshot_dir}"
printf '%s\n' "$*" > "${screenshot_dir}/mock_patrol_args.txt"
for screen in "${screens[@]}"; do
  printf 'ready\n' > "${screenshot_dir}/.ready_${screen}"
done
exit 0
SCRIPT
      ;;
    exit_before_first_sentinel)
cat > "${fixture_root}/scripts/dev/patrol_fast.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
screenshot_dir="${repo_root}/tmp/screenshots"
mkdir -p "${screenshot_dir}"
printf '%s\n' 'Error: xcodebuild exited with code 65' >&2
exit 65
SCRIPT
      ;;
    *)
      echo "FAIL: unknown setup_fixture patrol mode '${patrol_mode}'"
      failures=$((failures + 1))
      return 1
      ;;
  esac
  chmod +x "${fixture_root}/scripts/dev/patrol_fast.sh"

  cat > "${fixture_root}/bin/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "simctl" ]]; then
  exit 1
fi
shift

subcommand="${1:-}"
shift || true

  case "${subcommand}" in
    list)
      if [[ "${1:-}" == "runtimes" && "${2:-}" == "--json" ]]; then
        cat <<'JSON'
{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-2","name":"iOS 18.2","isAvailable":true}]}
JSON
      exit 0
    fi
    if [[ "${1:-}" == "devices" && "${2:-}" == "--json" ]]; then
      cat <<'JSON'
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-2":[{"name":"Screenshot-iphone-16-pro-max","udid":"11111111-1111-1111-1111-111111111111","state":"Booted","isAvailable":true}]}}
JSON
      exit 0
    fi
    ;;
    io)
      if [[ "${2:-}" == "screenshot" && ( "${1:-}" == "11111111-1111-1111-1111-111111111111" || "${1:-}" == "22222222-2222-2222-2222-222222222222" ) ]]; then
        target_path="${3:-}"
        mkdir -p "$(dirname "${target_path}")"
        printf 'fixture-png-bytes' > "${target_path}"

      if [[ "${MOCK_XCRUN_ADD_ROGUE_DEVICE_DIR:-1}" == "1" ]]; then
        rogue_dir="$(dirname "${target_path}")/../rogue-device"
        mkdir -p "${rogue_dir}"
        printf 'rogue-png-bytes' > "${rogue_dir}/rogue.png"
      fi
      exit 0
    fi
    ;;
  create)
    if [[ "${MOCK_SIMCTL_CREATE_MODE:-success}" == "error" ]]; then
      printf '%s\n' 'An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=403):' >&2
      printf '%s\n' 'Incompatible device' >&2
      exit 1
    fi
    printf '22222222-2222-2222-2222-222222222222\n'
    exit 0
    ;;
    boot)
      exit 0
      ;;
    shutdown)
      mkdir -p "$(pwd)/tmp/screenshots"
      printf '%s\n' "${1:-}" >> "$(pwd)/tmp/screenshots/mock_shutdown_calls.txt"
      exit 0
      ;;
  esac

printf 'Unexpected mock xcrun invocation: simctl %s %s\n' "${subcommand}" "$*" >&2
exit 1
SCRIPT
  chmod +x "${fixture_root}/bin/xcrun"

  cat > "${fixture_root}/bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
cat >/dev/null
printf '200'
SCRIPT
  chmod +x "${fixture_root}/bin/curl"

  cat > "${fixture_root}/bin/docker" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  context)
    if [[ "${2:-}" == "show" ]]; then
      printf '%s\n' "${MOCK_DOCKER_CONTEXT:-desktop-linux}"
      exit 0
    fi
    ;;
  info)
    if [[ "${MOCK_DOCKER_INFO_MODE:-success}" == "fail" ]]; then
      printf '%s\n' 'Cannot connect to the Docker daemon at unix:///Users/stuart/.docker/run/docker.sock.' >&2
      exit 1
    fi
    printf 'Client:\n'
    printf ' Server Version: mock\n'
    exit 0
    ;;
  desktop)
    if [[ "${2:-}" == "start" ]]; then
      exit 0
    fi
    ;;
esac

printf 'Unexpected mock docker invocation: %s\n' "$*" >&2
exit 1
SCRIPT
  chmod +x "${fixture_root}/bin/docker"

  printf '%s\n' "${fixture_root}"
}

test_rejects_unexpected_aggregate_device_directory() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --device iphone-16-pro-max 2>&1
  )" || exit_code=$?

  assert_eq "1" "${exit_code}" "script exits non-zero when aggregate output includes an unexpected device directory"
  assert_contains "${output}" "Unexpected screenshot device directory" "script reports unexpected device directory"

  rm -rf "${fixture_root}"
}

test_fails_when_simulator_create_is_incompatible() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    MOCK_SIMCTL_CREATE_MODE=error \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --device iphone-11-pro-max 2>&1
  )" || exit_code=$?

  assert_eq "1" "${exit_code}" "script exits non-zero when simulator creation fails"
  assert_contains "${output}" "ERROR: Failed to create simulator Screenshot-iphone-11-pro-max" "script reports create failure for selected slug"
  assert_contains "${output}" "Incompatible device" "script surfaces simulator create incompatibility details"

  rm -rf "${fixture_root}"
}

test_forwards_app_env_dart_define_to_patrol() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --env prod --device iphone-16-pro-max 2>&1
  )" || exit_code=$?

  assert_eq "1" "${exit_code}" "fixture run exits non-zero due injected rogue aggregate directory"
  assert_contains "${output}" "Unexpected screenshot device directory" "fixture still exercises aggregate verifier path"

  local patrol_args_file="${fixture_root}/tmp/screenshots/mock_patrol_args.txt"
  if [[ ! -f "${patrol_args_file}" ]]; then
    echo "FAIL: fixture captures patrol invocation args"
    failures=$((failures + 1))
  else
    local patrol_args
    patrol_args="$(cat "${patrol_args_file}")"
    assert_contains "${patrol_args}" "--dart-define=APP_ENV=prod" "wrapper forwards APP_ENV dart define to patrol"
    assert_contains "${patrol_args}" "--dart-define=SKIP_FIREBASE=true" "wrapper skips Firebase during simulator screenshot capture runs"
    assert_contains "${patrol_args}" "--dart-define=PROJECT_ROOT=${fixture_root}" "wrapper forwards PROJECT_ROOT dart define to patrol for sentinel path resolution"
  fi

  rm -rf "${fixture_root}"
}

test_shuts_down_simulator_booted_by_wrapper() {
  local fixture_root
  fixture_root="$(setup_fixture exit_before_first_sentinel)"

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    SCREENSHOT_SENTINEL_TIMEOUT=60 \
    SCREENSHOT_SENTINEL_POLL_INTERVAL=1 \
    MOCK_XCRUN_ADD_ROGUE_DEVICE_DIR=0 \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --device iphone-11-pro-max 2>&1
  )" || exit_code=$?

  assert_eq "1" "${exit_code}" "script still exits non-zero when Patrol fails before the first sentinel"
  assert_contains "${output}" "Patrol test exited 65" \
    "cleanup assertion runs on a real pre-sentinel Patrol failure path"
  local shutdown_log="${fixture_root}/tmp/screenshots/mock_shutdown_calls.txt"
  assert_file_contains "${shutdown_log}" "22222222-2222-2222-2222-222222222222" \
    "wrapper shuts down the simulator instance it booted for the selected device after failure"

  rm -rf "${fixture_root}"
}

test_timeout_cleanup_terminates_patrol_child_processes() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  cat > "${fixture_root}/scripts/dev/patrol_fast.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
screenshot_dir="${repo_root}/tmp/screenshots"
mkdir -p "${screenshot_dir}"
sleep 300 &
child_pid=$!
printf '%s\n' "${child_pid}" > "${screenshot_dir}/mock_patrol_child.pid"
wait "${child_pid}"
SCRIPT
  chmod +x "${fixture_root}/scripts/dev/patrol_fast.sh"

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    SCREENSHOT_SENTINEL_TIMEOUT=1 \
    SCREENSHOT_SENTINEL_POLL_INTERVAL=1 \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --device iphone-16-pro-max 2>&1
  )" || exit_code=$?

  assert_eq "1" "${exit_code}" "script exits non-zero when timed out waiting for first sentinel"
  assert_contains "${output}" "Stopping Patrol process tree" "script reports process-tree cleanup after timeout"

  local child_pid_file="${fixture_root}/tmp/screenshots/mock_patrol_child.pid"
  if [[ ! -f "${child_pid_file}" ]]; then
    echo "FAIL: timeout fixture writes child pid file"
    failures=$((failures + 1))
  else
    local child_pid
    child_pid="$(tr -d '[:space:]' < "${child_pid_file}")"
    if [[ -z "${child_pid}" ]]; then
      echo "FAIL: timeout fixture writes non-empty child pid"
      failures=$((failures + 1))
    elif kill -0 "${child_pid}" 2>/dev/null; then
      echo "FAIL: timeout cleanup terminates patrol child process tree"
      failures=$((failures + 1))
      kill "${child_pid}" 2>/dev/null || true
    fi
  fi

  rm -rf "${fixture_root}"
}

test_fails_fast_when_patrol_exits_before_first_sentinel() {
  local fixture_root
  fixture_root="$(setup_fixture exit_before_first_sentinel)"

  local output=""
  local exit_code=0
  local start_epoch=0
  local end_epoch=0
  start_epoch="$(date +%s)"
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    SCREENSHOT_SENTINEL_TIMEOUT=60 \
    SCREENSHOT_SENTINEL_POLL_INTERVAL=1 \
    MOCK_XCRUN_ADD_ROGUE_DEVICE_DIR=0 \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --device iphone-16-pro-max 2>&1
  )" || exit_code=$?
  end_epoch="$(date +%s)"
  local elapsed_seconds=$((end_epoch - start_epoch))

  assert_eq "1" "${exit_code}" "script exits non-zero when Patrol exits before first ready sentinel"
  assert_contains "${output}" "ERROR: Patrol test exited before signaling activity-recording ready." \
    "wrapper reports early Patrol failure before first screenshot"
  assert_contains "${output}" "FAIL: Screenshot capture failed for iPhone 16 Pro Max. See ${fixture_root}/tmp/screenshots/iphone-16-pro-max_patrol.log" \
    "wrapper includes per-device Patrol log path in early failure output"
  assert_not_contains "${output}" "Timed out waiting for activity-recording ready sentinel" \
    "wrapper reports Patrol pre-sentinel exit directly instead of mislabeling it as a sentinel timeout"
  local patrol_log_file="${fixture_root}/tmp/screenshots/iphone-16-pro-max_patrol.log"
  assert_file_contains "${patrol_log_file}" "xcodebuild exited with code 65" \
    "per-device Patrol log captures early xcodebuild exit details"
  if [[ ${elapsed_seconds} -ge 10 ]]; then
    echo "FAIL: early Patrol exit does not burn full sentinel timeout"
    failures=$((failures + 1))
  fi
  assert_contains "${output}" "Patrol test exited 65" \
    "wrapper surfaces Patrol exit status for pre-sentinel failures"

  rm -rf "${fixture_root}"
}

test_fails_fast_when_backend_unreachable() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  # Override default mock curl to simulate unreachable backend.
  cat > "${fixture_root}/bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
cat >/dev/null
exit 7  # curl exit code 7 = connection refused
SCRIPT
  chmod +x "${fixture_root}/bin/curl"

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --device iphone-16-pro-max 2>&1
  )" || exit_code=$?

  assert_eq "1" "${exit_code}" "script exits non-zero when backend is unreachable"
  assert_contains "${output}" "ERROR: Supabase backend is not reachable" \
    "script reports unreachable backend with clear error"

  rm -rf "${fixture_root}"
}

test_fails_fast_when_docker_desktop_is_not_ready() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    MOCK_DOCKER_INFO_MODE=fail \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --device iphone-16-pro-max 2>&1
  )" || exit_code=$?

  assert_eq "1" "${exit_code}" "script exits non-zero when Docker Desktop is not ready"
  assert_contains "${output}" "ERROR: Docker Desktop is not ready." \
    "script reports Docker Desktop readiness failure before local screenshot work"
  assert_contains "${output}" "docker desktop start" \
    "script prints the Docker Desktop recovery command"

  local patrol_args_file="${fixture_root}/tmp/screenshots/mock_patrol_args.txt"
  if [[ -f "${patrol_args_file}" ]]; then
    echo "FAIL: Docker Desktop preflight blocks Patrol launch"
    failures=$((failures + 1))
  fi

  rm -rf "${fixture_root}"
}

test_fails_fast_when_docker_context_is_colima() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    MOCK_DOCKER_CONTEXT=colima \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --device iphone-16-pro-max 2>&1
  )" || exit_code=$?

  assert_eq "1" "${exit_code}" "script exits non-zero when Docker context is Colima"
  assert_contains "${output}" "ERROR: Unsupported Docker context: colima" \
    "script rejects Colima for repo-owned local screenshot automation"
  assert_contains "${output}" "docker context use desktop-linux" \
    "script tells operators how to switch back to Docker Desktop"

  rm -rf "${fixture_root}"
}

test_fails_fast_when_backend_http_code_is_malformed() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  # Simulate a curl output concatenation bug that can produce malformed "000000".
  cat > "${fixture_root}/bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
cat >/dev/null
printf '000000'
exit 0
SCRIPT
  chmod +x "${fixture_root}/bin/curl"

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --device iphone-16-pro-max 2>&1
  )" || exit_code=$?

  assert_eq "1" "${exit_code}" "script exits non-zero when backend health check gets malformed HTTP code"
  assert_contains "${output}" "ERROR: Supabase backend is not reachable" \
    "script treats malformed backend HTTP code as unreachable"

  rm -rf "${fixture_root}"
}

test_fails_fast_when_backend_env_file_is_missing() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  rm -f "${fixture_root}/.env.dev"

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    MOCK_XCRUN_ADD_ROGUE_DEVICE_DIR=0 \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --device iphone-16-pro-max 2>&1
  )" || exit_code=$?

  assert_eq "1" "${exit_code}" "script exits non-zero when backend env file is missing"
  assert_contains "${output}" "ERROR: Missing backend env file" \
    "script reports missing backend env file instead of skipping the health check"

  local patrol_args_file="${fixture_root}/tmp/screenshots/mock_patrol_args.txt"
  if [[ -f "${patrol_args_file}" ]]; then
    echo "FAIL: missing backend env file blocks Patrol launch"
    failures=$((failures + 1))
  fi

  rm -rf "${fixture_root}"
}

test_accepts_auth_required_rest_root_as_reachable() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  # Override default mock curl to verify header-based auth and return 401.
  cat > "${fixture_root}/bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
tmp_dir="$(pwd)/tmp/screenshots"
mkdir -p "${tmp_dir}"
printf '%s\n' "${args}" > "${tmp_dir}/mock_curl_args.txt"
cat > "${tmp_dir}/mock_curl_config.txt"
config_contents="$(cat "${tmp_dir}/mock_curl_config.txt")"
if [[ "${config_contents}" == *"apikey: test-key"* && "${config_contents}" == *"Authorization: Bearer test-key"* ]]; then
  printf '401'
  exit 0
fi
exit 22
SCRIPT
  chmod +x "${fixture_root}/bin/curl"

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --device iphone-16-pro-max 2>&1
  )" || exit_code=$?

  assert_eq "1" "${exit_code}" "fixture run exits non-zero due injected rogue aggregate directory after backend check passes"
  assert_contains "${output}" "Backend reachable (HTTP 401)." "wrapper treats auth-required REST root as reachable"
  assert_contains "${output}" "Unexpected screenshot device directory" "fixture continues into aggregate verification after backend check"

  local mock_curl_args_file="${fixture_root}/tmp/screenshots/mock_curl_args.txt"
  assert_file_contains "${mock_curl_args_file}" "--config -" "backend check invokes curl with stdin config"
  local mock_curl_args
  mock_curl_args="$(cat "${mock_curl_args_file}")"
  assert_not_contains "${mock_curl_args}" "test-key" "backend check keeps Supabase anon key out of curl argv"
  local mock_curl_config_file="${fixture_root}/tmp/screenshots/mock_curl_config.txt"
  assert_file_contains "${mock_curl_config_file}" "apikey: test-key" "backend check forwards Supabase anon key header via curl stdin config"
  assert_file_contains "${mock_curl_config_file}" "Authorization: Bearer test-key" "backend check forwards bearer auth header via curl stdin config"

  local patrol_args_file="${fixture_root}/tmp/screenshots/mock_patrol_args.txt"
  if [[ ! -f "${patrol_args_file}" ]]; then
    echo "FAIL: backend check success allows patrol launch"
    failures=$((failures + 1))
  fi

  rm -rf "${fixture_root}"
}

test_fails_when_patrol_exits_non_zero_after_capture() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  # Override default mock patrol to exit non-zero after signaling screens.
  cat > "${fixture_root}/scripts/dev/patrol_fast.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
screenshot_dir="${repo_root}/tmp/screenshots"
screens=("activity-recording" "activity-detail" "analytics-dashboard" "social-feed" "activity-photo")
mkdir -p "${screenshot_dir}"
printf '%s\n' "$*" > "${screenshot_dir}/mock_patrol_args.txt"
for screen in "${screens[@]}"; do
  printf 'ready\n' > "${screenshot_dir}/.ready_${screen}"
done
exit 17
SCRIPT
  chmod +x "${fixture_root}/scripts/dev/patrol_fast.sh"

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    MOCK_XCRUN_ADD_ROGUE_DEVICE_DIR=0 \
    bash "./scripts/dev/capture_app_store_screenshots.sh" --device iphone-16-pro-max 2>&1
  )" || exit_code=$?

  assert_eq "1" "${exit_code}" "script exits non-zero when Patrol exits non-zero after screenshots are captured"
  assert_contains "${output}" "FAIL: Patrol test exited 17" \
    "wrapper treats Patrol test failure as a failed screenshot run"

  rm -rf "${fixture_root}"
}

test_repo_wrapper_entrypoint_is_executable() {
  local wrapper_path="${REPO_ROOT}/scripts/dev/capture_app_store_screenshots.sh"
  if [[ ! -x "${wrapper_path}" ]]; then
    echo "FAIL: wrapper entrypoint is executable (${wrapper_path})"
    failures=$((failures + 1))
  fi
}

main() {
  test_repo_wrapper_entrypoint_is_executable
  test_rejects_unexpected_aggregate_device_directory
  test_fails_when_simulator_create_is_incompatible
  test_forwards_app_env_dart_define_to_patrol
  test_shuts_down_simulator_booted_by_wrapper
  test_timeout_cleanup_terminates_patrol_child_processes
  test_fails_fast_when_patrol_exits_before_first_sentinel
  test_fails_fast_when_docker_desktop_is_not_ready
  test_fails_fast_when_docker_context_is_colima
  test_fails_fast_when_backend_unreachable
  test_fails_fast_when_backend_http_code_is_malformed
  test_fails_fast_when_backend_env_file_is_missing
  test_accepts_auth_required_rest_root_as_reachable
  test_fails_when_patrol_exits_non_zero_after_capture

  if [[ ${failures} -gt 0 ]]; then
    echo
    echo "capture_app_store_screenshots_test: ${failures} failure(s)"
    exit 1
  fi

  echo "capture_app_store_screenshots_test: all tests passed"
}

main "$@"
