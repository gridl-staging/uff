#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
json_output=false
default_device_name="iPhone 17 Pro"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      json_output=true
      shift
      ;;
    -h|--help)
      cat <<'EOF'
usage: ensure_worktree_ios_simulator.sh [--json] [device-name]

Creates or reuses the stable simulator owned by the current worktree, boots it,
opens Simulator.app, and prints the device UDID by default.

Options:
  --json        Print JSON metadata instead of a bare UDID
  device-name   Optional simulator device type name (default: iPhone 17 Pro)
EOF
      exit 0
      ;;
    *)
      if [[ "${default_device_name}" != "iPhone 17 Pro" ]]; then
        printf 'Unexpected argument: %s\n' "$1" >&2
        exit 1
      fi
      default_device_name="$1"
      shift
      ;;
  esac
done

simulator_info="$(
  REPO_ROOT="${repo_root}" DEFAULT_DEVICE_NAME="${default_device_name}" python3 - <<'PY'
import hashlib
import json
import os
import subprocess
import sys

repo_root = os.path.realpath(os.environ["REPO_ROOT"])
default_device_name = os.environ["DEFAULT_DEVICE_NAME"]
worktree_hash = hashlib.sha1(repo_root.encode()).hexdigest()[:6]
simulator_name = f"Uff-{worktree_hash}"

simctl = subprocess.run(
    ["xcrun", "simctl", "list", "-j", "devices", "devicetypes", "runtimes"],
    check=True,
    capture_output=True,
    text=True,
)
payload = json.loads(simctl.stdout)

def parse_version(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in value.split("."))

device_type_id = None
for device_type in payload["devicetypes"]:
    if device_type["name"] == default_device_name:
        device_type_id = device_type["identifier"]
        break

if device_type_id is None:
    print(f"Unable to find simulator device type named: {default_device_name}", file=sys.stderr)
    sys.exit(1)

runtime = None
for candidate in payload["runtimes"]:
    if (
        candidate.get("platform") == "iOS"
        and candidate.get("isAvailable")
        and candidate.get("identifier")
    ):
        if runtime is None or parse_version(candidate["version"]) > parse_version(runtime["version"]):
            runtime = candidate

if runtime is None:
    print("Unable to find an available iOS simulator runtime.", file=sys.stderr)
    sys.exit(1)

existing_udid = None
existing_state = ""
for devices in payload["devices"].values():
    for device in devices:
        if device.get("name") == simulator_name:
            existing_udid = device["udid"]
            existing_state = device.get("state") or ""
            break
    if existing_udid:
        break

result = {
    "device_type_id": device_type_id,
    "runtime_id": runtime["identifier"],
    "runtime_name": runtime["name"],
    "simulator_name": simulator_name,
    "existing_udid": existing_udid,
    "existing_state": existing_state,
}
print(json.dumps(result))
PY
)"

simulator_name="$(
  SIM_INFO="${simulator_info}" python3 - <<'PY'
import json
import os

print(json.loads(os.environ["SIM_INFO"])["simulator_name"])
PY
)"

simulator_udid="$(
  SIM_INFO="${simulator_info}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["SIM_INFO"])
print(payload["existing_udid"] or "")
PY
)"

simulator_state="$(
  SIM_INFO="${simulator_info}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["SIM_INFO"])
print(payload.get("existing_state") or "")
PY
)"

if [ -z "${simulator_udid}" ]; then
  device_type_id="$(
    SIM_INFO="${simulator_info}" python3 - <<'PY'
import json
import os

print(json.loads(os.environ["SIM_INFO"])["device_type_id"])
PY
  )"
  runtime_id="$(
    SIM_INFO="${simulator_info}" python3 - <<'PY'
import json
import os

print(json.loads(os.environ["SIM_INFO"])["runtime_id"])
PY
  )"
  simulator_udid="$(xcrun simctl create "${simulator_name}" "${device_type_id}" "${runtime_id}")"
  simulator_state="Shutdown"
fi

booted_by_this_run=false
if [[ "${simulator_state}" != "Booted" ]]; then
  xcrun simctl boot "${simulator_udid}" >/dev/null 2>&1 || true
  booted_by_this_run=true
fi
open -a Simulator >/dev/null 2>&1 || true

if [[ "${json_output}" == true ]]; then
  SIMULATOR_UDID="${simulator_udid}" SIMULATOR_NAME="${simulator_name}" \
    BOOTED_BY_THIS_RUN="${booted_by_this_run}" python3 - <<'PY'
import json
import os

print(json.dumps({
    "udid": os.environ["SIMULATOR_UDID"],
    "simulator_name": os.environ["SIMULATOR_NAME"],
    "booted_by_this_run": os.environ["BOOTED_BY_THIS_RUN"] == "true",
}))
PY
  exit 0
fi

printf '%s\n' "${simulator_udid}"
