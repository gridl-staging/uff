#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: dispatch_fcm_test_push.sh --device-token <token> --correlation-id <id> --platform <ios|android> [--dry-run]

Dispatches a single FCM HTTP v1 push for push-receipt smoke coverage.

Required:
  --device-token      Recipient FCM registration token
  --correlation-id    Correlation id propagated to message.data.correlation_id
  --platform          Platform marker propagated to message.data.platform

Optional:
  --dry-run           Print machine-readable JSON and skip auth/curl side effects
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

# shellcheck source=/dev/null
source "${repo_root}/scripts/lib/deployment_common.sh"

device_token=""
correlation_id=""
platform=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-token)
      device_token="${2:-}"
      shift 2
      ;;
    --correlation-id)
      correlation_id="${2:-}"
      shift 2
      ;;
    --platform)
      platform="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
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

if [[ -z "${device_token}" ]]; then
  printf 'Missing required argument: --device-token\n' >&2
  exit 1
fi
if [[ -z "${correlation_id}" ]]; then
  printf 'Missing required argument: --correlation-id\n' >&2
  exit 1
fi
if [[ -z "${platform}" ]]; then
  printf 'Missing required argument: --platform\n' >&2
  exit 1
fi
if [[ "${platform}" != "ios" && "${platform}" != "android" ]]; then
  printf 'Invalid --platform value: %s (expected ios|android)\n' "${platform}" >&2
  exit 1
fi

env_file="${repo_root}/.env.prod"
project_id="${FCM_PROJECT_ID:-}"
if [[ -z "${project_id}" && -f "${env_file}" ]]; then
  project_id="$(read_env_value "${env_file}" "FCM_PROJECT_ID")"
fi
if [[ -z "${project_id}" ]]; then
  printf 'Missing FCM project id. Set FCM_PROJECT_ID or populate %s with FCM_PROJECT_ID.\n' "${env_file}" >&2
  exit 1
fi

payload_json="$(
  DEVICE_TOKEN="${device_token}" \
  CORRELATION_ID="${correlation_id}" \
  PLATFORM="${platform}" \
  python3 - <<'PY'
import json
import os

print(json.dumps({
    "message": {
        "token": os.environ["DEVICE_TOKEN"],
        "data": {
            "correlation_id": os.environ["CORRELATION_ID"],
            "platform": os.environ["PLATFORM"],
        },
    },
}, separators=(",", ":")))
PY
)"

if [[ "${dry_run}" -eq 1 ]]; then
  PROJECT_ID="${project_id}" \
  DEVICE_TOKEN="${device_token}" \
  CORRELATION_ID="${correlation_id}" \
  PLATFORM="${platform}" \
  python3 - <<'PY'
import json
import os

print(json.dumps({
    "dry_run": True,
    "project_id": os.environ["PROJECT_ID"],
    "device_token": os.environ["DEVICE_TOKEN"],
    "correlation_id": os.environ["CORRELATION_ID"],
    "platform": os.environ["PLATFORM"],
}, separators=(",", ":")))
PY
  exit 0
fi

credentials_path="${GOOGLE_APPLICATION_CREDENTIALS:-}"
if [[ -z "${credentials_path}" ]]; then
  printf 'Missing GOOGLE_APPLICATION_CREDENTIALS for host-side bearer auth.\n' >&2
  exit 1
fi
if [[ ! -f "${credentials_path}" ]]; then
  printf 'GOOGLE_APPLICATION_CREDENTIALS file not found: %s\n' "${credentials_path}" >&2
  exit 1
fi

if ! command -v gcloud >/dev/null 2>&1; then
  printf 'gcloud is required for bearer-token minting.\n' >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  printf 'curl is required for FCM dispatch.\n' >&2
  exit 1
fi

if ! gcloud auth activate-service-account --key-file="${credentials_path}" --quiet >/dev/null; then
  printf 'Failed to activate service account from GOOGLE_APPLICATION_CREDENTIALS: %s\n' "${credentials_path}" >&2
  exit 1
fi

access_token="$(gcloud auth print-access-token)"
if [[ -z "${access_token}" ]]; then
  printf 'Failed to mint access token via gcloud auth print-access-token.\n' >&2
  exit 1
fi

fcm_url="https://fcm.googleapis.com/v1/projects/${project_id}/messages:send"
fcm_response_with_status="$(
  printf '%s' "${payload_json}" | curl -sS -X POST \
    "${fcm_url}" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    --data-binary @- \
    -w $'\n%{http_code}'
)"
fcm_http_status="${fcm_response_with_status##*$'\n'}"
fcm_response="${fcm_response_with_status%$'\n'*}"

if [[ ! "${fcm_http_status}" =~ ^[0-9]{3}$ ]]; then
  printf 'FCM send failed: unable to parse HTTP status from curl response.\n' >&2
  exit 1
fi
if [[ "${fcm_http_status}" -lt 200 || "${fcm_http_status}" -ge 300 ]]; then
  printf 'FCM send failed with HTTP %s. Response: %s\n' "${fcm_http_status}" "${fcm_response}" >&2
  exit 1
fi

FCM_RESPONSE="${fcm_response}" \
CORRELATION_ID="${correlation_id}" \
DEVICE_TOKEN="${device_token}" \
PLATFORM="${platform}" \
PROJECT_ID="${project_id}" \
python3 - <<'PY'
import json
import os

response_raw = os.environ["FCM_RESPONSE"]
response_name = ""
expected_message_id = ""

try:
    response_obj = json.loads(response_raw)
except Exception:
    response_obj = None

if isinstance(response_obj, dict):
    maybe_name = response_obj.get("name")
    if isinstance(maybe_name, str):
        response_name = maybe_name
        expected_message_id = maybe_name.rsplit("/", 1)[-1]

print(json.dumps({
    "dry_run": False,
    "project_id": os.environ["PROJECT_ID"],
    "device_token": os.environ["DEVICE_TOKEN"],
    "correlation_id": os.environ["CORRELATION_ID"],
    "platform": os.environ["PLATFORM"],
    "response_name": response_name,
    "expected_message_id": expected_message_id,
    "raw_response": response_obj if response_obj is not None else response_raw,
}, separators=(",", ":")))
PY
