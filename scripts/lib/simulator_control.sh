#!/usr/bin/env bash

# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
# TODO: Document resolve_worktree_simulator_metadata.
resolve_worktree_simulator_metadata() {
  local helper_path="$1"
  local helper_output

  helper_output="$("${helper_path}" --json)"

  SIMULATOR_HELPER_OUTPUT="${helper_output}" python3 - <<'PY'
import json
import os
import sys

raw_output = os.environ["SIMULATOR_HELPER_OUTPUT"].strip()
if not raw_output:
    print("Simulator helper returned empty output.", file=sys.stderr)
    sys.exit(1)

udid = ""
booted_by_this_run = False

if raw_output.startswith("{"):
    try:
        payload = json.loads(raw_output)
    except json.JSONDecodeError as exc:
        print(f"Simulator helper returned invalid JSON: {exc}", file=sys.stderr)
        sys.exit(1)

    udid = str(payload.get("udid") or "").strip()
    booted_by_this_run = bool(payload.get("booted_by_this_run", False))
else:
    udid = raw_output

if not udid:
    print("Simulator helper did not provide a UDID.", file=sys.stderr)
    sys.exit(1)

print(json.dumps({
    "udid": udid,
    "booted_by_this_run": booted_by_this_run,
}))
PY
}

# TODO: Document simulator_metadata_field.
simulator_metadata_field() {
  local simulator_metadata_json="$1"
  local field_name="$2"

  SIMULATOR_METADATA_JSON="${simulator_metadata_json}" SIMULATOR_METADATA_FIELD="${field_name}" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["SIMULATOR_METADATA_JSON"])
field_name = os.environ["SIMULATOR_METADATA_FIELD"]
value = payload.get(field_name)

if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

shutdown_simulator_if_owned() {
  local simulator_udid="$1"
  local booted_by_this_run="${2:-false}"

  if [[ "${booted_by_this_run}" != "true" || -z "${simulator_udid}" ]]; then
    return 0
  fi

  xcrun simctl shutdown "${simulator_udid}" >/dev/null 2>&1 || true
}
