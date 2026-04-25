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

setup_fixture() {
  local fixture_root
  fixture_root="$(mktemp -d)"

  mkdir -p \
    "${fixture_root}/scripts/dev" \
    "${fixture_root}/scripts/lib" \
    "${fixture_root}/.maestro/smoke" \
    "${fixture_root}/bin"

  cp "${REPO_ROOT}/scripts/dev/run_maestro_smoke.sh" "${fixture_root}/scripts/dev/"
  cp "${REPO_ROOT}/scripts/lib/deployment_common.sh" "${fixture_root}/scripts/lib/"
  chmod +x "${fixture_root}/scripts/dev/run_maestro_smoke.sh"

  cat > "${fixture_root}/.maestro/smoke/auth_smoke.yaml" <<'YAML'
appId: com.gridl.uff
---
- launchApp
YAML

  cat > "${fixture_root}/.maestro/smoke/notification_smoke.yaml" <<'YAML'
appId: com.gridl.uff
---
- launchApp
YAML

  cat > "${fixture_root}/bin/maestro" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${MAESTRO_CALL_LOG}"
exit 0
SCRIPT
  chmod +x "${fixture_root}/bin/maestro"

  cat > "${fixture_root}/bin/java" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
exit 0
SCRIPT
  chmod +x "${fixture_root}/bin/java"

  printf '%s\n' "${fixture_root}"
}

last_exit_code=0
last_output=""

run_script() {
  local fixture_root="$1"
  shift

  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    MAESTRO_CALL_LOG="${fixture_root}/maestro_calls.log" \
    PATH="${fixture_root}/bin:${PATH}" \
    "./scripts/dev/run_maestro_smoke.sh" "$@" 2>&1
  )" || exit_code=$?

  last_exit_code="${exit_code}"
  last_output="${output}"
}

test_notification_only_prints_skip_firebase_note() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_script "${fixture_root}" --only notification_smoke

  assert_eq "0" "${last_exit_code}" "notification-only run exits zero"
  assert_contains "${last_output}" "SKIP_FIREBASE=true" "notification-only run prints SKIP_FIREBASE prerequisite"
  assert_contains "${last_output}" "notification-status-error" "notification-only run explains the assertion that depends on the prerequisite"
  assert_contains "$(cat "${fixture_root}/maestro_calls.log")" "notification_smoke.yaml" "notification-only run targets the notification flow"

  rm -rf "${fixture_root}"
}

test_non_notification_only_omits_skip_firebase_note() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_script "${fixture_root}" --only auth_smoke

  assert_eq "0" "${last_exit_code}" "auth-only run exits zero"
  assert_not_contains "${last_output}" "SKIP_FIREBASE=true" "auth-only run omits notification prerequisite note"
  assert_contains "$(cat "${fixture_root}/maestro_calls.log")" "auth_smoke.yaml" "auth-only run targets the auth flow"

  rm -rf "${fixture_root}"
}

test_smoke_tag_prints_skip_firebase_note() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  run_script "${fixture_root}" --tags smoke

  assert_eq "0" "${last_exit_code}" "smoke-tag run exits zero"
  assert_contains "${last_output}" "SKIP_FIREBASE=true" "smoke-tag run prints notification prerequisite because notification_smoke is included"
  assert_contains "$(cat "${fixture_root}/maestro_calls.log")" "--include-tags smoke" "smoke-tag run forwards the tag filter to Maestro"

  rm -rf "${fixture_root}"
}

main() {
  test_notification_only_prints_skip_firebase_note
  test_non_notification_only_omits_skip_firebase_note
  test_smoke_tag_prints_skip_firebase_note

  if [[ "${failures}" -gt 0 ]]; then
    echo "FAIL: ${failures} run_maestro_smoke assertion(s) failed."
    exit 1
  fi

  echo "PASS: run_maestro_smoke script tests passed."
}

main "$@"
