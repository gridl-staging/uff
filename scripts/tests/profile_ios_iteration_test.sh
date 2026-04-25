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

setup_profile_fixture() {
  local fixture_root
  fixture_root="$(mktemp -d)"

  mkdir -p "${fixture_root}/scripts/dev" "${fixture_root}/scripts/lib" "${fixture_root}/bin" "${fixture_root}/ios/Runner.xcworkspace"
  cp "${REPO_ROOT}/scripts/dev/profile_ios_iteration.sh" "${fixture_root}/scripts/dev/"
  cp "${REPO_ROOT}/scripts/lib/simulator_control.sh" "${fixture_root}/scripts/lib/"
  chmod +x "${fixture_root}/scripts/dev/profile_ios_iteration.sh"

  cat > "${fixture_root}/scripts/dev/flutter_fast_nopub.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'flutter config-only output\n'
exit 0
SCRIPT
  chmod +x "${fixture_root}/scripts/dev/flutter_fast_nopub.sh"

  cat > "${fixture_root}/bin/xcodebuild" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${XCODEBUILD_ARGS_MARKER}"
cat <<'EOF'
Build Timing Summary
====================
SwiftCompile 1.0
EOF
SCRIPT
  chmod +x "${fixture_root}/bin/xcodebuild"

  cat > "${fixture_root}/bin/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "simctl" && "${2:-}" == "shutdown" ]]; then
  printf '%s\n' "${3:-}" >> "${SHUTDOWN_MARKER}"
  exit 0
fi
printf 'unexpected xcrun invocation: %s\n' "$*" >&2
exit 1
SCRIPT
  chmod +x "${fixture_root}/bin/xcrun"

  printf '%s\n' "${fixture_root}"
}

test_profile_shuts_down_helper_owned_simulator() {
  local fixture_root
  fixture_root="$(setup_profile_fixture)"

  cat > "${fixture_root}/scripts/dev/ensure_worktree_ios_simulator.sh" <<'SCRIPT'
#!/usr/bin/env bash
cat <<'JSON'
{"udid":"fixture-auto-udid","booted_by_this_run":true}
JSON
SCRIPT
  chmod +x "${fixture_root}/scripts/dev/ensure_worktree_ios_simulator.sh"

  local shutdown_marker="${fixture_root}/shutdown_calls.txt"
  local xcodebuild_args_marker="${fixture_root}/xcodebuild_args.txt"
  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    SHUTDOWN_MARKER="${shutdown_marker}" \
    XCODEBUILD_ARGS_MARKER="${xcodebuild_args_marker}" \
    bash "./scripts/dev/profile_ios_iteration.sh" 2>&1
  )" || exit_code=$?

  assert_eq "0" "${exit_code}" \
    "profile script succeeds when helper returns owned simulator metadata"
  assert_success "profile script records xcodebuild arguments" \
    test -f "${xcodebuild_args_marker}"
  assert_success "profile script shuts down helper-owned simulator on exit" \
    test -f "${shutdown_marker}"
  assert_eq "fixture-auto-udid" "$(cat "${shutdown_marker}")" \
    "profile script shuts down exactly the owned simulator"
  assert_success "profile script passes the helper UDID to xcodebuild" \
    grep -q -- "-destination id=fixture-auto-udid" "${xcodebuild_args_marker}"

  rm -rf "${fixture_root}"
}

test_profile_leaves_prebooted_helper_simulator_running() {
  local fixture_root
  fixture_root="$(setup_profile_fixture)"

  cat > "${fixture_root}/scripts/dev/ensure_worktree_ios_simulator.sh" <<'SCRIPT'
#!/usr/bin/env bash
cat <<'JSON'
{"udid":"fixture-auto-udid","booted_by_this_run":false}
JSON
SCRIPT
  chmod +x "${fixture_root}/scripts/dev/ensure_worktree_ios_simulator.sh"

  local shutdown_marker="${fixture_root}/shutdown_calls.txt"
  local xcodebuild_args_marker="${fixture_root}/xcodebuild_args.txt"
  local output=""
  local exit_code=0
  output="$(
    cd "${fixture_root}" &&
    PATH="${fixture_root}/bin:${PATH}" \
    SHUTDOWN_MARKER="${shutdown_marker}" \
    XCODEBUILD_ARGS_MARKER="${xcodebuild_args_marker}" \
    bash "./scripts/dev/profile_ios_iteration.sh" 2>&1
  )" || exit_code=$?

  assert_eq "0" "${exit_code}" \
    "profile script succeeds when helper reports a prebooted simulator"
  assert_success "profile script records xcodebuild arguments for prebooted simulator" \
    test -f "${xcodebuild_args_marker}"
  assert_success "profile script does not shut down a prebooted simulator" \
    test ! -f "${shutdown_marker}"

  rm -rf "${fixture_root}"
}

main() {
  test_profile_shuts_down_helper_owned_simulator
  test_profile_leaves_prebooted_helper_simulator_running

  if [[ "${failures}" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "profile_ios_iteration_test: PASS"
}

main "$@"
