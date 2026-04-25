#!/usr/bin/env bash
set -euo pipefail

# Captures App Store screenshots across 3 iOS simulator device types.
#
# Coordinates with e2e_test/smoke/screenshot_capture_test.dart via file-based
# signaling: the Patrol test navigates to each screen and writes a .ready_<screen>
# sentinel; this script polls for it, captures via simctl, then writes a
# .captured_<screen> acknowledgement so the test advances.
#
# Output: tmp/screenshots/<device-slug>/<screen>.png (15 files total)

usage() {
  cat <<'EOF'
usage: capture_app_store_screenshots.sh [options]

Options:
  --env dev|staging|prod   Target environment (default: dev)
  --device <slug>          Run on single device (iphone-16-pro-max, iphone-11-pro-max, ipad-pro-13-inch)
  -h, --help               Show this help
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
docker_preflight_script="${repo_root}/scripts/dev/check_local_docker_engine.sh"

# shellcheck source=/dev/null
source "${repo_root}/scripts/lib/deployment_common.sh"

# --- Device target definitions ---
# Each entry: slug|device-type-identifier|display-name
DEVICE_TARGETS=(
  "iphone-16-pro-max|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max|iPhone 16 Pro Max"
  # iPhone 11 Pro Max provides the 6.5-inch screenshot class (Xs Max unavailable on iOS 26.x).
  "iphone-11-pro-max|com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max|iPhone 11 Pro Max (6.5-inch class)"
  "ipad-pro-13-inch|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB|iPad Pro 13-inch (M5)"
)

SCREENS=("activity-recording" "activity-detail" "analytics-dashboard" "social-feed" "activity-photo")

SCREENSHOT_DIR="${repo_root}/tmp/screenshots"
TEST_PATH="e2e_test/smoke/screenshot_capture_test.dart"
SENTINEL_POLL_INTERVAL="${SCREENSHOT_SENTINEL_POLL_INTERVAL:-1}"  # seconds between polls for .ready_ files
SENTINEL_TIMEOUT="${SCREENSHOT_SENTINEL_TIMEOUT:-300}"            # seconds before giving up on a screen
FIREBASE_PLIST_PATH="${repo_root}/ios/Runner/GoogleService-Info.plist"
# Firebase iOS SDK validates API key format on startup before Dart executes.
# Use a syntactically valid placeholder for simulator screenshot runs when the
# repo plist uses "placeholder", then restore the original file on exit.
SIMULATOR_FIREBASE_API_KEY="AIzaSySimulatorScreenshotBypass000000000000"
firebase_plist_backup=""
SIMULATORS_BOOTED_THIS_RUN=()
ENSURED_SIMULATOR_UDID=""

# --- Argument parsing ---
app_env="dev"
device_filter=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      app_env="${2:-}"
      shift 2
      ;;
    --device)
      device_filter="${2:-}"
      shift 2
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
  dev|staging|prod) ;;
  *)
    printf 'Unsupported --env value: %s\n' "${app_env}" >&2
    exit 1
    ;;
esac

# --- Runtime discovery ---
ios_runtime_id=""
# TODO: Document discover_ios_runtime.
discover_ios_runtime() {
  ios_runtime_id="$(xcrun simctl list runtimes --json 2>/dev/null \
    | python3 -c '
import json, sys
d = json.load(sys.stdin)
for r in d["runtimes"]:
    if r.get("isAvailable", False) and "iOS" in r.get("name", ""):
        print(r["identifier"])
        break
' 2>/dev/null || true)"

  if [[ -z "${ios_runtime_id}" ]]; then
    printf 'ERROR: No available iOS simulator runtime found.\n' >&2
    exit 1
  fi
  printf 'Using iOS runtime: %s\n' "${ios_runtime_id}"
}

restore_simulator_firebase_config() {
  if [[ -z "${firebase_plist_backup}" ]]; then
    return 0
  fi

  if [[ -f "${firebase_plist_backup}" ]]; then
    cp "${firebase_plist_backup}" "${FIREBASE_PLIST_PATH}"
    rm -f "${firebase_plist_backup}"
  fi
  firebase_plist_backup=""
}

shutdown_booted_screenshot_simulators() {
  if [[ ${#SIMULATORS_BOOTED_THIS_RUN[@]} -eq 0 ]]; then
    return 0
  fi

  local idx udid
  for (( idx=${#SIMULATORS_BOOTED_THIS_RUN[@]} - 1; idx>=0; idx-- )); do
    udid="${SIMULATORS_BOOTED_THIS_RUN[idx]}"
    printf 'Shutting down simulator: %s\n' "${udid}" >&2
    xcrun simctl shutdown "${udid}" >/dev/null 2>&1 || true
  done
}

cleanup_screenshot_run() {
  shutdown_booted_screenshot_simulators
  restore_simulator_firebase_config
}

booted_screenshot_simulator_recorded() {
  local candidate_udid="$1"
  local recorded_udid
  for recorded_udid in "${SIMULATORS_BOOTED_THIS_RUN[@]-}"; do
    if [[ -n "${recorded_udid}" && "${recorded_udid}" == "${candidate_udid}" ]]; then
      return 0
    fi
  done
  return 1
}

# TODO: Document prepare_simulator_firebase_config.
prepare_simulator_firebase_config() {
  if [[ ! -f "${FIREBASE_PLIST_PATH}" ]]; then
    return 0
  fi

  local api_key
  api_key="$(/usr/libexec/PlistBuddy -c 'Print :API_KEY' "${FIREBASE_PLIST_PATH}" 2>/dev/null || true)"
  if [[ "${api_key}" =~ ^AIza[A-Za-z0-9_-]{10,}$ ]]; then
    return 0
  fi

  firebase_plist_backup="$(mktemp "${SCREENSHOT_DIR}/google-service-info.backup.XXXXXX.plist")"
  cp "${FIREBASE_PLIST_PATH}" "${firebase_plist_backup}"

  if ! /usr/libexec/PlistBuddy -c "Set :API_KEY ${SIMULATOR_FIREBASE_API_KEY}" "${FIREBASE_PLIST_PATH}" >/dev/null 2>&1; then
    printf 'ERROR: Unable to patch API_KEY in %s for simulator screenshot run.\n' "${FIREBASE_PLIST_PATH}" >&2
    restore_simulator_firebase_config
    return 1
  fi

  printf 'WARN: Patched placeholder Firebase API_KEY for simulator run; original plist will be restored on exit.\n' >&2
  return 0
}

# TODO: Document check_backend_reachable.
check_backend_reachable() {
  local env_file="${repo_root}/.env.${app_env}"
  if [[ ! -f "${env_file}" ]]; then
    printf 'ERROR: Missing backend env file: %s\n' "${env_file}" >&2
    printf 'The Patrol screenshot test requires SUPABASE_URL and SUPABASE_ANON_KEY for %s.\n' "${app_env}" >&2
    return 1
  fi

  local supabase_url=""
  supabase_url="$(read_env_value "${env_file}" "SUPABASE_URL")"
  if [[ -z "${supabase_url}" ]]; then
    printf 'ERROR: Missing SUPABASE_URL in %s\n' "${env_file}" >&2
    return 1
  fi

  local anon_key=""
  anon_key="$(read_env_value "${env_file}" "SUPABASE_ANON_KEY")"
  if [[ -z "${anon_key}" ]]; then
    printf 'ERROR: Missing SUPABASE_ANON_KEY in %s\n' "${env_file}" >&2
    return 1
  fi

  local rest_url="${supabase_url%/}/rest/v1/"
  local http_code=""
  local curl_config rest_url_json apikey_header_json bearer_header_json

  printf 'Checking backend connectivity: %s\n' "${supabase_url}"
  # Any HTTP response from the REST root proves the backend is reachable.
  # Keep the anon key out of argv so it does not show up in process listings.
  rest_url_json="$(json_quote "${rest_url}")"
  apikey_header_json="$(json_quote "apikey: ${anon_key}")"
  bearer_header_json="$(json_quote "Authorization: Bearer ${anon_key}")"
  curl_config="$(cat <<EOF
url = ${rest_url_json}
connect-timeout = 5
max-time = 10
silent
output = "/dev/null"
write-out = "%{http_code}"
header = ${apikey_header_json}
header = ${bearer_header_json}
EOF
)"
  http_code="$(printf '%s\n' "${curl_config}" | curl --config - 2>/dev/null || printf '000')"
  # curl --write-out must produce exactly one 3-digit HTTP status code.
  # Treat malformed output (for example "000000") as unreachable so probe
  # ownership classification does not accept transport failures as healthy.
  if [[ ! "${http_code}" =~ ^[0-9]{3}$ || "${http_code}" == "000" ]]; then
    printf 'ERROR: Supabase backend is not reachable at %s\n' "${supabase_url}" >&2
    printf 'The Patrol screenshot test requires a running Supabase instance.\n' >&2
    printf 'Start it with: supabase start\n' >&2
    return 1
  fi

  printf 'Backend reachable (HTTP %s).\n' "${http_code}"
  return 0
}

array_contains() {
  local needle="$1"
  shift
  local value
  for value in "$@"; do
    if [[ "${value}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

is_valid_simulator_udid() {
  local candidate="$1"
  [[ "${candidate}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

list_child_pids() {
  local parent_pid="$1"
  pgrep -P "${parent_pid}" 2>/dev/null || true
}

# TODO: Document terminate_process_tree.
terminate_process_tree() {
  local root_pid="$1"
  local -a queue=("${root_pid}")
  local -a descendants=()
  local current_pid child_pid

  # Capture descendants before signaling so children cannot outlive the parent.
  while [[ ${#queue[@]} -gt 0 ]]; do
    current_pid="${queue[0]}"
    queue=("${queue[@]:1}")
    while IFS= read -r child_pid; do
      [[ -z "${child_pid}" ]] && continue
      descendants+=("${child_pid}")
      queue+=("${child_pid}")
    done < <(list_child_pids "${current_pid}")
  done

  local idx
  for (( idx=${#descendants[@]} - 1; idx>=0; idx-- )); do
    kill "${descendants[idx]}" 2>/dev/null || true
  done
  kill "${root_pid}" 2>/dev/null || true

  local -a all_pids=("${root_pid}" "${descendants[@]}")
  local settle_attempt running_pid
  local still_running
  for settle_attempt in {1..10}; do
    still_running=false
    for running_pid in "${all_pids[@]}"; do
      if kill -0 "${running_pid}" 2>/dev/null; then
        still_running=true
        break
      fi
    done

    if [[ "${still_running}" == false ]]; then
      return 0
    fi
    sleep 1
  done

  for (( idx=${#descendants[@]} - 1; idx>=0; idx-- )); do
    kill -9 "${descendants[idx]}" 2>/dev/null || true
  done
  kill -9 "${root_pid}" 2>/dev/null || true
}

# TODO: Document ensure_screenshot_simulator.
ensure_screenshot_simulator() {
  local slug="$1"
  local device_type_id="$2"
  local sim_name="Screenshot-${slug}"
  local udid
  ENSURED_SIMULATOR_UDID=""

  # Look up existing simulator by name — returns "udid|state" if found.
  local lookup_result
  lookup_result="$(xcrun simctl list devices --json 2>/dev/null \
    | python3 -c '
import json, sys
d = json.load(sys.stdin)
name = sys.argv[1]
for runtime_devices in d["devices"].values():
    for dev in runtime_devices:
        if dev["name"] == name and dev.get("isAvailable", False):
            print(dev["udid"] + "|" + dev["state"])
            sys.exit(0)
' "${sim_name}" 2>/dev/null || true)"

  local state=""
  if [[ -n "${lookup_result}" ]]; then
    IFS='|' read -r udid state <<< "${lookup_result}"
    printf 'Found existing simulator %s: %s\n' "${sim_name}" "${udid}" >&2
  else
    printf 'Creating simulator %s (%s)...\n' "${sim_name}" "${device_type_id}" >&2
    local create_output
    if ! create_output="$(xcrun simctl create "${sim_name}" "${device_type_id}" "${ios_runtime_id}" 2>&1)"; then
      printf 'ERROR: Failed to create simulator %s (%s) on runtime %s.\n' \
        "${sim_name}" "${device_type_id}" "${ios_runtime_id}" >&2
      printf '%s\n' "${create_output}" >&2
      return 1
    fi
    udid="$(printf '%s\n' "${create_output}" | tail -n 1 | tr -d '\r')"
    if ! is_valid_simulator_udid "${udid}"; then
      printf 'ERROR: Simulator create returned invalid UDID for %s: %s\n' \
        "${sim_name}" "${udid}" >&2
      printf 'Full create output:\n%s\n' "${create_output}" >&2
      return 1
    fi
    printf 'Created simulator %s: %s\n' "${sim_name}" "${udid}" >&2
    state="Shutdown"
  fi

  if ! is_valid_simulator_udid "${udid}"; then
    printf 'ERROR: Existing simulator %s has invalid UDID: %s\n' "${sim_name}" "${udid}" >&2
    return 1
  fi

  if [[ "${state}" != "Booted" ]]; then
    printf 'Booting simulator %s...\n' "${sim_name}" >&2
    xcrun simctl boot "${udid}" 2>/dev/null || true
    if ! booted_screenshot_simulator_recorded "${udid}"; then
      SIMULATORS_BOOTED_THIS_RUN+=("${udid}")
    fi
    sleep 3
  fi

  ENSURED_SIMULATOR_UDID="${udid}"
}

# --- Capture coordination loop ---
# Runs alongside the Patrol test, capturing screenshots via simctl when
# the test signals readiness.
run_capture_loop() {
  local udid="$1"
  local device_slug="$2"
  local patrol_pid="$3"
  local output_dir="${SCREENSHOT_DIR}/${device_slug}"
  local screen

  for screen in "${SCREENS[@]}"; do
    local ready_sentinel="${SCREENSHOT_DIR}/.ready_${screen}"
    local captured_ack="${SCREENSHOT_DIR}/.captured_${screen}"
    local elapsed=0

    # Clean stale ack from previous iteration (if any).
    rm -f "${captured_ack}"

    printf '  Waiting for screen: %s...\n' "${screen}"

    # Poll for ready sentinel or Patrol exit.
    while [[ ! -f "${ready_sentinel}" ]]; do
      if ! kill -0 "${patrol_pid}" 2>/dev/null; then
        printf 'ERROR: Patrol test exited before signaling %s ready.\n' "${screen}" >&2
        return 1
      fi
      if [[ ${elapsed} -ge ${SENTINEL_TIMEOUT} ]]; then
        printf 'ERROR: Timed out waiting for %s ready sentinel (%ds).\n' "${screen}" "${SENTINEL_TIMEOUT}" >&2
        return 1
      fi
      sleep "${SENTINEL_POLL_INTERVAL}"
      elapsed=$((elapsed + SENTINEL_POLL_INTERVAL))
    done

    # Small delay to let the UI settle after the test signals ready.
    sleep 1

    # Capture screenshot.
    local screenshot_path="${output_dir}/${screen}.png"
    printf '  Capturing %s -> %s\n' "${screen}" "${screenshot_path}"
    if ! xcrun simctl io "${udid}" screenshot "${screenshot_path}" 2>/dev/null; then
      printf 'ERROR: simctl screenshot failed for %s.\n' "${screen}" >&2
      return 1
    fi

    # Write acknowledgement so the test advances.
    printf '%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${captured_ack}"

    # Clean up the ready sentinel. Leave the captured ack for the Dart test
    # to poll and find — it will be cleaned at the start of the next screen
    # iteration (rm -f of stale .ready_ and .captured_ files).
    rm -f "${ready_sentinel}"

    printf '  Captured %s (%s bytes)\n' "${screen}" "$(wc -c < "${screenshot_path}" | tr -d ' ')"
  done

  return 0
}

# TODO: Document run_device_capture.
run_device_capture() {
  local slug="$1"
  local device_type_id="$2"
  local display_name="$3"
  local output_dir="${SCREENSHOT_DIR}/${slug}"
  local log_file="${SCREENSHOT_DIR}/${slug}_patrol.log"

  printf '\n========================================\n'
  printf 'Device: %s (%s)\n' "${display_name}" "${slug}"
  printf '========================================\n'

  # Ensure output directory exists and clean stale sentinel files.
  mkdir -p "${output_dir}"
  rm -f "${SCREENSHOT_DIR}"/.ready_* "${SCREENSHOT_DIR}"/.captured_*

  if ! ensure_screenshot_simulator "${slug}" "${device_type_id}"; then
    printf 'FAIL: Simulator provisioning failed for %s.\n' "${display_name}" >&2
    return 1
  fi
  local udid="${ENSURED_SIMULATOR_UDID}"

  # Launch Patrol test in background.
  printf 'Launching Patrol test on %s (UDID: %s)...\n' "${display_name}" "${udid}"
  local -a dart_defines=(
    "--dart-define=APP_ENV=${app_env}"
    # Dart-side Firebase init remains disabled for screenshot runs.
    "--dart-define=SKIP_FIREBASE=true"
    # Patrol test CWD on iOS simulator is not the project root — sentinel
    # paths must resolve absolutely.
    "--dart-define=PROJECT_ROOT=${repo_root}"
  )
  "${repo_root}/scripts/dev/patrol_fast.sh" test \
    -t "${TEST_PATH}" \
    -d "${udid}" \
    "${dart_defines[@]}" \
    > "${log_file}" 2>&1 &
  local patrol_pid=$!

  # Run capture coordination loop.
  local capture_result=0
  run_capture_loop "${udid}" "${slug}" "${patrol_pid}" || capture_result=$?

  local patrol_exit=0

  if [[ ${capture_result} -ne 0 ]]; then
    # Ensure failed capture attempts do not leave Patrol/xcodebuild orphaned.
    if kill -0 "${patrol_pid}" 2>/dev/null; then
      printf 'Stopping Patrol process tree for %s after capture failure...\n' "${display_name}" >&2
      terminate_process_tree "${patrol_pid}"
    fi

    wait "${patrol_pid}" 2>/dev/null || patrol_exit=$?
    [[ ${patrol_exit} -gt 0 && ${patrol_exit} -lt 129 ]] && printf 'FAIL: Patrol test exited %d for %s. See %s\n' "${patrol_exit}" "${display_name}" "${log_file}" >&2
    printf 'FAIL: Screenshot capture failed for %s. See %s\n' "${display_name}" "${log_file}" >&2
    return 1
  fi

  # Wait for Patrol to finish (may already be done).
  wait "${patrol_pid}" 2>/dev/null || patrol_exit=$?

  if [[ ${patrol_exit} -ne 0 ]]; then
    printf 'FAIL: Patrol test exited %d for %s. See %s\n' \
      "${patrol_exit}" "${display_name}" "${log_file}" >&2
    return 1
  fi

  # Verify all 5 screenshots exist with non-zero size.
  local missing=0
  for screen in "${SCREENS[@]}"; do
    local path="${output_dir}/${screen}.png"
    if [[ ! -s "${path}" ]]; then
      printf 'MISSING: %s\n' "${path}" >&2
      missing=$((missing + 1))
    fi
  done

  if [[ ${missing} -gt 0 ]]; then
    printf 'FAIL: %d screenshots missing for %s.\n' "${missing}" "${display_name}" >&2
    return 1
  fi

  printf 'OK: 5/5 screenshots captured for %s.\n' "${display_name}"
  return 0
}

# Validates screenshots for a single device directory.
# Sets png_count_out to the number of valid PNGs found.
# Caller must have nullglob enabled.
png_count_out=0
# TODO: Document verify_device_screenshots.
verify_device_screenshots() {
  local device_slug="$1"
  local device_dir="${SCREENSHOT_DIR}/${device_slug}"
  png_count_out=0

  if [[ ! -d "${device_dir}" ]]; then
    printf 'ERROR: Missing screenshot device directory: %s\n' "${device_dir}" >&2
    return 1
  fi

  local png_file_count=0
  local png_path
  for png_path in "${device_dir}"/*.png; do
    [[ ! -f "${png_path}" ]] && continue
    png_file_count=$((png_file_count + 1))

    if [[ ! -s "${png_path}" ]]; then
      printf 'ERROR: Screenshot file is empty: %s\n' "${png_path}" >&2
      return 1
    fi

    local file_name="${png_path##*/}"
    local screen_slug="${file_name%.png}"
    if ! array_contains "${screen_slug}" "${SCREENS[@]}"; then
      printf 'ERROR: Unexpected screenshot file for %s: %s\n' "${device_slug}" "${file_name}" >&2
      return 1
    fi
  done

  if [[ ${png_file_count} -ne ${#SCREENS[@]} ]]; then
    printf 'ERROR: Expected %d screenshots for %s, found %d.\n' \
      "${#SCREENS[@]}" "${device_slug}" "${png_file_count}" >&2
    return 1
  fi

  # If exactly N non-empty files all have names in the N-element SCREENS set,
  # every SCREENS entry is present. No second loop needed.
  png_count_out="${png_file_count}"
  return 0
}

# TODO: Document verify_aggregate_artifacts.
verify_aggregate_artifacts() {
  local selected_slugs=("$@")
  local expected_device_count="${#selected_slugs[@]}"
  local expected_png_count=$((expected_device_count * ${#SCREENS[@]}))
  local actual_device_count=0
  local actual_png_count=0

  shopt -s nullglob

  # Root PNG files are invalid; screenshots must live under device directories.
  local root_png
  for root_png in "${SCREENSHOT_DIR}"/*.png; do
    printf 'ERROR: Unexpected screenshot file at root: %s\n' "${root_png}" >&2
    shopt -u nullglob
    return 1
  done

  # Reject unexpected device directories and count selected ones.
  local device_dir
  for device_dir in "${SCREENSHOT_DIR}"/*; do
    [[ ! -d "${device_dir}" ]] && continue
    local device_slug
    device_slug="$(basename "${device_dir}")"
    if ! array_contains "${device_slug}" "${selected_slugs[@]}"; then
      printf 'ERROR: Unexpected screenshot device directory: %s\n' "${device_slug}" >&2
      shopt -u nullglob
      return 1
    fi
    actual_device_count=$((actual_device_count + 1))
  done

  if [[ ${actual_device_count} -ne ${expected_device_count} ]]; then
    printf 'ERROR: Expected %d screenshot device directories, found %d.\n' \
      "${expected_device_count}" "${actual_device_count}" >&2
    shopt -u nullglob
    return 1
  fi

  local selected_slug
  for selected_slug in "${selected_slugs[@]}"; do
    if ! verify_device_screenshots "${selected_slug}"; then
      shopt -u nullglob
      return 1
    fi
    actual_png_count=$((actual_png_count + png_count_out))
  done

  shopt -u nullglob

  if [[ ${actual_png_count} -ne ${expected_png_count} ]]; then
    printf 'ERROR: Expected %d screenshots total, found %d.\n' \
      "${expected_png_count}" "${actual_png_count}" >&2
    return 1
  fi

  printf 'OK: Aggregate artifact contract verified (%d devices, %d screenshots).\n' \
    "${actual_device_count}" "${actual_png_count}"
  return 0
}

# TODO: Document write_summary_json.
write_summary_json() {
  local devices_attempted="$1"
  local devices_passed="$2"
  local devices_failed="$3"
  local device_results="$4"
  local aggregate_contract_status="$5"
  local target_count="$6"

  local timestamp git_sha
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  git_sha="$(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  local summary_file="${SCREENSHOT_DIR}/screenshot_summary_${timestamp}_${git_sha}.json"

  local timestamp_json git_sha_json aggregate_contract_status_json
  timestamp_json="$(json_quote "${timestamp}")"
  git_sha_json="$(json_quote "${git_sha}")"
  aggregate_contract_status_json="$(json_quote "${aggregate_contract_status}")"
  local expected_screenshot_count=$(( target_count * ${#SCREENS[@]} ))

  cat > "${summary_file}" <<JSON
{
  "timestamp": ${timestamp_json},
  "git_sha": ${git_sha_json},
  "devices_attempted": ${devices_attempted},
  "devices_passed": ${devices_passed},
  "devices_failed": ${devices_failed},
  "artifact_contract_status": ${aggregate_contract_status_json},
  "expected_device_count": ${target_count},
  "expected_screenshot_count": ${expected_screenshot_count},
  "results": ${device_results}
}
JSON

  printf '\n========================================\n'
  printf 'Summary: %d/%d devices passed\n' "${devices_passed}" "${devices_attempted}"
  printf 'Results: %s\n' "${summary_file}"
  printf '========================================\n'
}

# Builds a JSON object for a single device's screenshot capture result.
# Output goes to stdout; caller appends to the results array.
build_device_result_json() {
  local slug="$1"
  local display_name="$2"
  local device_status="$3"

  local slug_json display_json status_json
  slug_json="$(json_quote "${slug}")"
  display_json="$(json_quote "${display_name}")"
  status_json="$(json_quote "${device_status}")"

  local screen_files="["
  local first_screen=true
  for screen in "${SCREENS[@]}"; do
    local path="tmp/screenshots/${slug}/${screen}.png"
    local path_json
    path_json="$(json_quote "${path}")"
    if [[ "${first_screen}" != true ]]; then
      screen_files+=","
    fi
    first_screen=false
    screen_files+="${path_json}"
  done
  screen_files+="]"

  printf '{\"slug\":%s,\"display_name\":%s,\"status\":%s,\"screen_count\":%d,\"files\":%s}' \
    "${slug_json}" "${display_json}" "${status_json}" "${#SCREENS[@]}" "${screen_files}"
}

# TODO: Document main.
main() {
  # Local dev screenshot runs depend on the Docker-backed Supabase stack.
  if [[ "${app_env}" == "dev" ]]; then
    "${docker_preflight_script}"
  fi

  discover_ios_runtime

  # Clean output directory.
  rm -rf "${SCREENSHOT_DIR}"
  mkdir -p "${SCREENSHOT_DIR}"

  trap 'cleanup_screenshot_run' EXIT
  prepare_simulator_firebase_config

  # Fail fast if the backend is unreachable instead of waiting 300s for sentinel timeout.
  check_backend_reachable

  # Filter device targets if --device specified.
  local targets=()
  local target_slugs=()
  for entry in "${DEVICE_TARGETS[@]}"; do
    local slug="${entry%%|*}"
    if [[ -n "${device_filter}" && "${slug}" != "${device_filter}" ]]; then
      continue
    fi
    targets+=("${entry}")
    target_slugs+=("${slug}")
  done

  if [[ ${#targets[@]} -eq 0 ]]; then
    printf 'ERROR: No matching device for --device %s\n' "${device_filter}" >&2
    printf 'Valid slugs: iphone-16-pro-max, iphone-11-pro-max, ipad-pro-13-inch\n' >&2
    exit 1
  fi

  local devices_attempted=0
  local devices_passed=0
  local devices_failed=0
  local device_results="["
  local first_result=true

  # Run devices sequentially (shared build dir prevents parallel builds).
  for entry in "${targets[@]}"; do
    IFS='|' read -r slug device_type_id display_name <<< "${entry}"
    devices_attempted=$((devices_attempted + 1))
    local device_status="pass"

    if run_device_capture "${slug}" "${device_type_id}" "${display_name}"; then
      devices_passed=$((devices_passed + 1))
    else
      devices_failed=$((devices_failed + 1))
      device_status="fail"
    fi

    if [[ "${first_result}" != true ]]; then
      device_results+=","
    fi
    first_result=false
    device_results+="$(build_device_result_json "${slug}" "${display_name}" "${device_status}")"
  done
  device_results+="]"

  local aggregate_contract_status="pass"
  if ! verify_aggregate_artifacts "${target_slugs[@]}"; then
    aggregate_contract_status="fail"
  fi

  write_summary_json "${devices_attempted}" "${devices_passed}" "${devices_failed}" \
    "${device_results}" "${aggregate_contract_status}" "${#target_slugs[@]}"

  if [[ ${devices_failed} -gt 0 || "${aggregate_contract_status}" != "pass" ]]; then
    exit 1
  fi
}

main "$@"
