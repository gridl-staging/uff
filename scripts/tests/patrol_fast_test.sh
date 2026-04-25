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

setup_fixture() {
  local fixture_root="$1"
  mkdir -p "${fixture_root}/scripts/dev" "${fixture_root}/scripts/lib"
  cp "${REPO_ROOT}/scripts/dev/patrol_fast.sh" "${fixture_root}/scripts/dev/"

  cat > "${fixture_root}/scripts/lib/patrol_cli_workarounds.sh" <<'SCRIPT'
#!/usr/bin/env bash
repair_patrol_cli_ios_inherited_flag_bug() {
  printf '%s\n' called > "${MOCK_HELPER_CALLED_FILE}"
}
repair_patrol_cli_analytics_version_probe_bug() {
  printf '%s\n' analytics_called > "${MOCK_ANALYTICS_HELPER_CALLED_FILE}"
}
SCRIPT

  cat > "${fixture_root}/scripts/dev/with_fast_build_dir.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "${PATROL_NO_COMPLETION:-}" > "${MOCK_NO_COMPLETION_FILE}"
printf '%s\n' "${PATROL_FLUTTER_COMMAND:-}" > "${MOCK_FLUTTER_COMMAND_FILE}"
printf '%s\n' "$*" > "${MOCK_ARGS_FILE}"
SCRIPT

  chmod +x \
    "${fixture_root}/scripts/dev/patrol_fast.sh" \
    "${fixture_root}/scripts/lib/patrol_cli_workarounds.sh" \
    "${fixture_root}/scripts/dev/with_fast_build_dir.sh"
}

test_patrol_fast_forces_ci_mode_and_preserves_wrapper_contract() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_fixture "${tmpdir}"

  local helper_called_file="${tmpdir}/helper_called.txt"
  local analytics_helper_called_file="${tmpdir}/analytics_helper_called.txt"
  local no_completion_file="${tmpdir}/no_completion.txt"
  local flutter_command_file="${tmpdir}/flutter_command.txt"
  local args_file="${tmpdir}/args.txt"

  (
    cd "${tmpdir}" &&
    MOCK_HELPER_CALLED_FILE="${helper_called_file}" \
      MOCK_ANALYTICS_HELPER_CALLED_FILE="${analytics_helper_called_file}" \
      MOCK_NO_COMPLETION_FILE="${no_completion_file}" \
      MOCK_FLUTTER_COMMAND_FILE="${flutter_command_file}" \
      MOCK_ARGS_FILE="${args_file}" \
      bash "./scripts/dev/patrol_fast.sh" test --foo bar
  )

  assert_eq "called" "$(cat "${helper_called_file}")" \
    "patrol_fast runs the Patrol CLI workaround helper before invoking Patrol"
  assert_eq "analytics_called" "$(cat "${analytics_helper_called_file}")" \
    "patrol_fast runs the Patrol analytics version-probe workaround before invoking Patrol"
  assert_eq "1" "$(cat "${no_completion_file}")" \
    "patrol_fast disables Patrol's auto completion installer via its built-in env flag"
  assert_eq "${tmpdir}/scripts/dev/flutter_fast.sh" "$(cat "${flutter_command_file}")" \
    "patrol_fast points Patrol at the repo-owned flutter wrapper"
  assert_contains "$(cat "${args_file}")" "patrol test --foo bar" \
    "patrol_fast still delegates to with_fast_build_dir.sh with the original Patrol args"

  rm -rf "${tmpdir}"
}

main() {
  test_patrol_fast_forces_ci_mode_and_preserves_wrapper_contract

  if [[ "${failures}" -ne 0 ]]; then
    echo "patrol_fast_test: ${failures} failure(s)"
    exit 1
  fi

  echo "patrol_fast_test: PASS"
}

main "$@"
