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

assert_success() {
  local description="$1"
  shift
  if "$@"; then
    return 0
  fi
  echo "FAIL: ${description} (command failed)"
  failures=$((failures + 1))
}

setup_fixture() {
  local device_state="$1"
  local fixture_root
  local simulator_name

  fixture_root="$(mktemp -d)"
  simulator_name="$(
    REPO_ROOT="${fixture_root}" python3 - <<'PY'
import hashlib
import os

print(f"Uff-{hashlib.sha1(os.path.realpath(os.environ['REPO_ROOT']).encode()).hexdigest()[:6]}")
PY
  )"

  mkdir -p "${fixture_root}/scripts/dev" "${fixture_root}/bin"
  cp "${REPO_ROOT}/scripts/dev/ensure_worktree_ios_simulator.sh" "${fixture_root}/scripts/dev/"
  chmod +x "${fixture_root}/scripts/dev/ensure_worktree_ios_simulator.sh"

  cat > "${fixture_root}/bin/xcrun" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail

if [[ "\${1:-}" != "simctl" ]]; then
  printf 'unexpected xcrun invocation: %s\\n' "\$*" >&2
  exit 1
fi
shift

if [[ "\${1:-}" == "list" && "\${2:-}" == "-j" && "\${3:-}" == "devices" && "\${4:-}" == "devicetypes" && "\${5:-}" == "runtimes" ]]; then
  cat <<'JSON'
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-2":[{"name":"${simulator_name}","udid":"fixture-udid","state":"${device_state}","isAvailable":true}]},"devicetypes":[{"name":"iPhone 17 Pro","identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"}],"runtimes":[{"platform":"iOS","isAvailable":true,"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-2","name":"iOS 18.2","version":"18.2"}]}
JSON
  exit 0
fi

if [[ "\${1:-}" == "boot" ]]; then
  printf '%s\\n' "\${2:-}" >> "${fixture_root}/boot_calls.txt"
  exit 0
fi

printf 'unexpected simctl invocation: %s\\n' "\$*" >&2
exit 1
SCRIPT
  chmod +x "${fixture_root}/bin/xcrun"

  cat > "${fixture_root}/bin/open" <<SCRIPT
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "${fixture_root}/open_calls.txt"
exit 0
SCRIPT
  chmod +x "${fixture_root}/bin/open"

  printf '%s\n' "${fixture_root}"
}

json_field() {
  local json_payload="$1"
  local field_name="$2"
  JSON_PAYLOAD="${json_payload}" JSON_FIELD="${field_name}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["JSON_PAYLOAD"])
value = payload[os.environ["JSON_FIELD"]]
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

test_json_output_marks_prebooted_simulator_as_not_owned() {
  local fixture_root
  fixture_root="$(setup_fixture "Booted")"

  local output
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    bash "./scripts/dev/ensure_worktree_ios_simulator.sh" --json
  )"

  assert_eq "fixture-udid" "$(json_field "${output}" "udid")" \
    "helper JSON output returns the simulator UDID"
  assert_eq "false" "$(json_field "${output}" "booted_by_this_run")" \
    "helper marks an already-booted simulator as not owned by this run"
  assert_success "helper does not boot an already-booted simulator" \
    test ! -f "${fixture_root}/boot_calls.txt"

  rm -rf "${fixture_root}"
}

test_json_output_marks_shutdown_simulator_as_owned_after_boot() {
  local fixture_root
  fixture_root="$(setup_fixture "Shutdown")"

  local output
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    bash "./scripts/dev/ensure_worktree_ios_simulator.sh" --json
  )"

  assert_eq "fixture-udid" "$(json_field "${output}" "udid")" \
    "helper JSON output returns the shutdown simulator UDID"
  assert_eq "true" "$(json_field "${output}" "booted_by_this_run")" \
    "helper marks a shutdown simulator as booted by this run"
  assert_eq "fixture-udid" "$(cat "${fixture_root}/boot_calls.txt")" \
    "helper boots the shutdown simulator before returning metadata"

  rm -rf "${fixture_root}"
}

main() {
  test_json_output_marks_prebooted_simulator_as_not_owned
  test_json_output_marks_shutdown_simulator_as_owned_after_boot

  if [[ "${failures}" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "ensure_worktree_ios_simulator_test: PASS"
}

main "$@"
