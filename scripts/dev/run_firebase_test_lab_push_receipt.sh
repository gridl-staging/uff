#!/usr/bin/env bash
set -euo pipefail

# TODO: Document usage.
usage() {
  cat <<'USAGE'
usage: run_firebase_test_lab_push_receipt.sh --platform <ios|android> --device-token <token> --correlation-id <id> [options]

Required:
  --platform <ios|android>
  --device-token <token>
  --correlation-id <id>

Optional:
  --app <path>                  Android app APK path (required for non-dry-run android)
  --test <path>                 Android androidTest APK path (required for non-dry-run android)
  --dry-run                     Skip Test Lab submission and force dispatch --dry-run
  --output-dir <path>           Artifact directory (default: tmp/firebase_test_lab)
  --env-file <path>             Env file for fallback lookups (default: .env.prod)
  --secret-source <path>        Secret source for fallback lookups (default: .secret/.env.secret)
  --android-device-model <id>   Override pinned android model (default: redfin)
  --android-version <id>        Override pinned android version (default: 30)
  --ios-device-model <id>       Override pinned iOS model (default: iphone8plus)
  --ios-version <id>            Override pinned iOS version (default: 15.7)
  --matrix-timeout <duration>   gcloud matrix timeout flag (default: 15m)
  --dispatch-timeout-sec <n>    Dispatch timeout seconds (default: 60)
  --matrix-timeout-sec <n>      Matrix submission timeout seconds (default: 900)
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

# shellcheck source=/dev/null
source "${repo_root}/scripts/lib/deployment_common.sh"

dispatch_script="${repo_root}/scripts/ci/dispatch_fcm_test_push.sh"
setup_script="${repo_root}/scripts/dev/setup_firebase_test_lab.sh"

platform=""
device_token=""
correlation_id=""
app_path=""
test_path=""
dry_run=0
output_dir="${repo_root}/tmp/firebase_test_lab"
env_file="${repo_root}/.env.prod"
secret_source="${repo_root}/.secret/.env.secret"

# Runner-owned pinned defaults. CI should call this runner, not duplicate these.
android_device_model="redfin"
android_version="30"
ios_device_model="iphone8plus"
ios_version="15.7"
matrix_timeout="15m"
dispatch_timeout_sec="60"
matrix_timeout_sec="900"

submission_request_path=""
dispatch_result_path=""
matrix_summary_path=""
stage_summary_path=""

# TODO: Document run_with_timeout_capture.
run_with_timeout_capture() {
  local timeout_sec="$1"
  shift
  python3 - "${timeout_sec}" "$@" <<'PY'
import subprocess
import sys

timeout = int(sys.argv[1])
cmd = sys.argv[2:]

try:
    completed = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
except subprocess.TimeoutExpired as exc:
    if exc.stdout:
        sys.stdout.write(exc.stdout)
    if exc.stderr:
        sys.stderr.write(exc.stderr)
    sys.stderr.write(f"Command timed out after {timeout}s: {' '.join(cmd)}\n")
    raise SystemExit(124)

if completed.stdout:
    sys.stdout.write(completed.stdout)
if completed.stderr:
    sys.stderr.write(completed.stderr)
raise SystemExit(completed.returncode)
PY
}

# TODO: Document write_json_or_wrapped_output.
write_json_or_wrapped_output() {
  local output_path="$1"
  local raw_output="$2"

  RAW_OUTPUT="${raw_output}" python3 - "${output_path}" <<'PY'
import json
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
raw = os.environ.get("RAW_OUTPUT", "")

try:
    payload = json.loads(raw)
except Exception:
    payload = {"raw_output": raw}

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
PY
}

# TODO: Document json_write_stage_summary.
json_write_stage_summary() {
  local status="$1"
  local message="$2"
  local failure_code="${3:-}"

  python3 - "${stage_summary_path}" "${status}" "${message}" "${failure_code}" \
    "${platform}" "${dry_run}" \
    "${android_device_model}" "${android_version}" "${ios_device_model}" "${ios_version}" \
    "${submission_request_path}" "${dispatch_result_path}" "${matrix_summary_path}" <<'PY'
import json
import pathlib
import sys

(
    out_path,
    status,
    message,
    failure_code,
    platform,
    dry_run_raw,
    android_model,
    android_version,
    ios_model,
    ios_version,
    submission_path,
    dispatch_path,
    matrix_path,
) = sys.argv[1:]

payload = {
    "status": status,
    "message": message,
    "platform": platform,
    "dry_run": dry_run_raw == "1",
    "pinned_defaults": {
        "android": {"model": android_model, "version": android_version},
        "ios": {"model": ios_model, "version": ios_version},
    },
    "artifacts": {
        "submission_request": submission_path,
        "dispatch_result": dispatch_path,
        "matrix_summary": matrix_path,
    },
}

if failure_code:
    payload["failure"] = {"code": failure_code}

path = pathlib.Path(out_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
PY
}

fail_with_artifact() {
  local code="$1"
  local message="$2"
  printf 'ERROR: %s\n' "${message}" >&2
  json_write_stage_summary "failure" "${message}" "${code}"
  exit 1
}

# TODO: Document write_submission_request.
write_submission_request() {
  python3 - "${submission_request_path}" "${platform}" "${dry_run}" \
    "${android_device_model}" "${android_version}" "${ios_device_model}" "${ios_version}" \
    "${matrix_timeout}" "${dispatch_timeout_sec}" "${matrix_timeout_sec}" \
    "${device_token}" "${correlation_id}" "${app_path}" "${test_path}" <<'PY'
import json
import pathlib
import sys

(
    out_path,
    platform,
    dry_run_raw,
    android_model,
    android_version,
    ios_model,
    ios_version,
    matrix_timeout,
    dispatch_timeout_sec,
    matrix_timeout_sec,
    device_token,
    correlation_id,
    app_path,
    test_path,
) = sys.argv[1:]

device = {"model": android_model, "version": android_version}
if platform == "ios":
    device = {"model": ios_model, "version": ios_version}

payload = {
    "platform": platform,
    "dry_run": dry_run_raw == "1",
    "device": device,
    "timeouts": {
        "matrix": matrix_timeout,
        "dispatch_seconds": int(dispatch_timeout_sec),
        "matrix_seconds": int(matrix_timeout_sec),
    },
    "dispatch_contract": {
        "script": "scripts/ci/dispatch_fcm_test_push.sh",
        "args": [
            "--device-token",
            device_token,
            "--correlation-id",
            correlation_id,
            "--platform",
            platform,
        ],
    },
    "setup_owner": "scripts/dev/setup_firebase_test_lab.sh",
}

if payload["dry_run"]:
    payload["dispatch_contract"]["args"].append("--dry-run")

if app_path:
    payload["android_app_path"] = app_path
if test_path:
    payload["android_test_path"] = test_path

path = pathlib.Path(out_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) platform="${2:-}"; shift 2 ;;
    --device-token) device_token="${2:-}"; shift 2 ;;
    --correlation-id) correlation_id="${2:-}"; shift 2 ;;
    --app) app_path="${2:-}"; shift 2 ;;
    --test) test_path="${2:-}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --output-dir) output_dir="${2:-}"; shift 2 ;;
    --env-file) env_file="${2:-}"; shift 2 ;;
    --secret-source) secret_source="${2:-}"; shift 2 ;;
    --android-device-model) android_device_model="${2:-}"; shift 2 ;;
    --android-version) android_version="${2:-}"; shift 2 ;;
    --ios-device-model) ios_device_model="${2:-}"; shift 2 ;;
    --ios-version) ios_version="${2:-}"; shift 2 ;;
    --matrix-timeout) matrix_timeout="${2:-}"; shift 2 ;;
    --dispatch-timeout-sec) dispatch_timeout_sec="${2:-}"; shift 2 ;;
    --matrix-timeout-sec) matrix_timeout_sec="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

submission_request_path="${output_dir}/submission_request.json"
dispatch_result_path="${output_dir}/dispatch_result.json"
matrix_summary_path="${output_dir}/matrix_summary.json"
stage_summary_path="${output_dir}/stage_summary.json"
mkdir -p "${output_dir}"

missing_args=()
if [[ -z "${platform}" ]]; then missing_args+=("--platform"); fi
if [[ -z "${device_token}" ]]; then missing_args+=("--device-token"); fi
if [[ -z "${correlation_id}" ]]; then missing_args+=("--correlation-id"); fi
if [[ "${#missing_args[@]}" -gt 0 ]]; then
  fail_with_artifact "missing_required_args" "Missing required argument(s): ${missing_args[*]}"
fi
if [[ "${platform}" != "android" && "${platform}" != "ios" ]]; then
  fail_with_artifact "invalid_platform" "Invalid --platform value: ${platform} (expected ios|android)"
fi
if [[ -z "${android_device_model}" || -z "${android_version}" || -z "${ios_device_model}" || -z "${ios_version}" ]]; then
  fail_with_artifact "missing_pinned_defaults" "Pinned device/version defaults are required and may not be empty"
fi
if [[ ! -f "${dispatch_script}" ]]; then
  fail_with_artifact "dispatch_owner_missing" "Dispatch owner script missing: ${dispatch_script}"
fi
if [[ ! -f "${setup_script}" ]]; then
  fail_with_artifact "setup_owner_missing" "Setup owner script missing: ${setup_script}"
fi

write_submission_request

credentials_path=""
if [[ "${dry_run}" -eq 0 ]]; then
  credentials_error="$(
    resolve_google_application_credentials_path "${env_file}" "${secret_source}" "${repo_root}" 2>&1
  )" || fail_with_artifact "missing_credentials" "${credentials_error}"
  credentials_path="${credentials_error}"
fi

dispatch_args=(
  "${dispatch_script}"
  --device-token "${device_token}"
  --correlation-id "${correlation_id}"
  --platform "${platform}"
)
if [[ "${dry_run}" -eq 1 ]]; then
  dispatch_args+=(--dry-run)
fi

dispatch_output=""
if [[ "${dry_run}" -eq 1 ]]; then
  dispatch_output="$(run_with_timeout_capture "${dispatch_timeout_sec}" bash "${dispatch_args[@]}")" || {
    write_json_or_wrapped_output "${dispatch_result_path}" "${dispatch_output}"
    fail_with_artifact "dispatch_failed" "Dispatch helper failed in dry-run mode"
  }
else
  dispatch_output="$(
    GOOGLE_APPLICATION_CREDENTIALS="${credentials_path}" \
      run_with_timeout_capture "${dispatch_timeout_sec}" bash "${dispatch_args[@]}" 2>&1
  )" || {
    write_json_or_wrapped_output "${dispatch_result_path}" "${dispatch_output}"
    fail_with_artifact "dispatch_failed" "Dispatch helper failed"
  }
fi

write_json_or_wrapped_output "${dispatch_result_path}" "${dispatch_output}"

if [[ "${dry_run}" -eq 1 ]]; then
  python3 - "${matrix_summary_path}" "${platform}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
platform = sys.argv[2]
payload = {
    "matrix_id": "dry-run-matrix",
    "status": "dry_run",
    "platform": platform,
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
PY
  json_write_stage_summary "success" "Dry-run contract validated"
  printf 'Runner succeeded. Artifacts written under %s\n' "${output_dir}"
  exit 0
fi

if [[ "${platform}" != "android" ]]; then
  fail_with_artifact "unsupported_live_platform" "Live Firebase Test Lab submission currently supports --platform android only"
fi
if [[ -z "${app_path}" || -z "${test_path}" ]]; then
  fail_with_artifact "missing_android_artifacts" "--app and --test are required for non-dry-run android submission"
fi
if [[ ! -f "${app_path}" ]]; then
  fail_with_artifact "missing_android_app" "Android app APK not found: ${app_path}"
fi
if [[ ! -f "${test_path}" ]]; then
  fail_with_artifact "missing_android_test" "Android androidTest APK not found: ${test_path}"
fi

matrix_output="$(
  run_with_timeout_capture "${matrix_timeout_sec}" \
    gcloud firebase test android run \
      --type instrumentation \
      --app "${app_path}" \
      --test "${test_path}" \
      --device "model=${android_device_model},version=${android_version},locale=en,orientation=portrait" \
      --timeout "${matrix_timeout}" \
      --format json 2>&1
)" || {
  write_json_or_wrapped_output "${matrix_summary_path}" "${matrix_output}"
  fail_with_artifact "matrix_submission_failed" "Firebase Test Lab matrix submission failed"
}

MATRIX_OUTPUT="${matrix_output}" python3 - "${matrix_summary_path}" "${platform}" <<'PY'
import json
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
platform = sys.argv[2]
raw = os.environ.get("MATRIX_OUTPUT", "")
parsed = None

try:
    parsed = json.loads(raw)
except Exception:
    parsed = None

matrix_id = ""
status = "submitted"
if isinstance(parsed, dict):
    matrix_id = parsed.get("testMatrixId") or parsed.get("matrixId") or ""
    state = parsed.get("state")
    if isinstance(state, str) and state:
        status = state

payload = {
    "platform": platform,
    "matrix_id": matrix_id,
    "status": status,
    "raw_response": parsed if parsed is not None else raw,
}

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
PY

json_write_stage_summary "success" "Firebase Test Lab matrix submitted"
printf 'Runner succeeded. Artifacts written under %s\n' "${output_dir}"
