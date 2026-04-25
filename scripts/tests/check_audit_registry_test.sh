#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
failures=0
LAST_EXIT_CODE=0
LAST_OUTPUT=""

assert_eq() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${description} (expected '${expected}', got '${actual}')"
    failures=$((failures + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: ${description} (missing '${needle}')"
    failures=$((failures + 1))
  fi
}

run_check_audit_registry() {
  local tmpdir="$1"
  shift

  local output=""
  local exit_code=0
  output="$(
    cd "${tmpdir}" &&
    ./scripts/check_audit_registry.sh "$@" 2>&1
  )" || exit_code=$?

  printf '%s\n' "${exit_code}"
  printf '%s\n' "${output}"
}

capture_run_result() {
  local result="$1"
  LAST_EXIT_CODE="$(printf '%s\n' "${result}" | sed -n '1p')"
  LAST_OUTPUT="$(printf '%s\n' "${result}" | tail -n +2)"
}

setup_fixture() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  mkdir -p "${tmpdir}/scripts" "${tmpdir}/scripts/lib" "${tmpdir}/docs" \
    "${tmpdir}/e2e_test/smoke" "${tmpdir}/integration_test" "${tmpdir}/test/src/features/demo"

  cp "${REPO_ROOT}/scripts/check_audit_registry.sh" "${tmpdir}/scripts/"
  chmod +x "${tmpdir}/scripts/check_audit_registry.sh"
  cp "${REPO_ROOT}/scripts/lib/feature_registry_headings.sh" "${tmpdir}/scripts/lib/"

  printf '%s\n' "fixture" > "${tmpdir}/e2e_test/smoke/demo_test.dart"
  printf '%s\n' "fixture" > "${tmpdir}/integration_test/demo_smoke_test.dart"
  printf '%s\n' "fixture" > "${tmpdir}/test/src/features/demo/demo_test.dart"

  printf '%s\n' "${tmpdir}"
}

write_registry_fixture() {
  local tmpdir="$1"
  local cross_user_status="$2"
  local dev_audit_line="$3"

  cat > "${tmpdir}/docs/feature_test_audit_registry.md" <<EOF
# Feature Test Audit Registry

## Features

### Demo Feature

- **Area**: lib/src/features/demo/
- **User-scoped data**: yes
- **Test files**:
  - e2e_test/smoke/demo_test.dart
  - integration_test/demo_smoke_test.dart
  - test/src/features/demo/demo_test.dart
- **Cross-user negative test**: ${cross_user_status}
- **Known gaps**: none
- **Dev-audit**: ${dev_audit_line}
- **Cross-audit**: 2026-03-31, session: fixture
EOF
}

append_stale_test_path() {
  local tmpdir="$1"
  local stale_path="$2"
  local registry_path="${tmpdir}/docs/feature_test_audit_registry.md"
  local temp_registry="${registry_path}.tmp"

  awk -v stale_path="${stale_path}" '
    /^- \*\*Cross-user negative test\*\*:/ {
      print "  - " stale_path
    }
    { print }
  ' "${registry_path}" > "${temp_registry}"
  mv "${temp_registry}" "${registry_path}"
}

test_strict_fails_for_partial() {
  local tmpdir
  local result

  tmpdir="$(setup_fixture)"
  write_registry_fixture "${tmpdir}" "PARTIAL" "2026-03-31, session: fixture"

  result="$(run_check_audit_registry "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict fails when cross-user status is PARTIAL"
  assert_contains "${LAST_OUTPUT}" "PARTIAL statuses:" "strict output reports PARTIAL count"
  assert_contains "${LAST_OUTPUT}" "PARTIAL features:        Demo Feature" "strict output names the PARTIAL feature"
  assert_contains "${LAST_OUTPUT}" "incomplete cross-user proof" "strict output explains incomplete proof"

  rm -rf "${tmpdir}"
}

test_strict_fails_for_missing() {
  local tmpdir
  local result

  tmpdir="$(setup_fixture)"
  write_registry_fixture "${tmpdir}" "MISSING" "2026-03-31, session: fixture"

  result="$(run_check_audit_registry "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict fails when cross-user status is MISSING"
  assert_contains "${LAST_OUTPUT}" "MISSING statuses:" "strict output reports MISSING count"
  assert_contains "${LAST_OUTPUT}" "MISSING features:        Demo Feature" "strict output names the MISSING feature"

  rm -rf "${tmpdir}"
}

test_strict_passes_for_yes() {
  local tmpdir
  local result

  tmpdir="$(setup_fixture)"
  write_registry_fixture "${tmpdir}" "YES" "2026-03-31, session: fixture"

  result="$(run_check_audit_registry "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "strict passes when cross-user status is YES"
  assert_contains "${LAST_OUTPUT}" "Incomplete cross-user proof: 0" "strict output reports zero incomplete proof"

  rm -rf "${tmpdir}"
}

test_stale_paths_warn_but_do_not_block_any_mode() {
  local tmpdir
  local result

  tmpdir="$(setup_fixture)"
  write_registry_fixture "${tmpdir}" "YES" "2026-03-31, session: fixture"
  append_stale_test_path "${tmpdir}" "test/src/features/demo/missing_test.dart"

  result="$(run_check_audit_registry "${tmpdir}")"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "default mode keeps stale-path warnings non-blocking"
  assert_contains "${LAST_OUTPUT}" "Stale test paths:" "default output reports stale test paths"
  assert_contains "${LAST_OUTPUT}" "WARNING: 1 test paths in the registry point to files/directories that don't exist" "default output reports stale-path warning"

  result="$(run_check_audit_registry "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "strict mode keeps stale-path warnings non-blocking"
  assert_contains "${LAST_OUTPUT}" "Stale test paths:" "strict output reports stale test paths"
  assert_contains "${LAST_OUTPUT}" "WARNING: 1 test paths in the registry point to files/directories that don't exist" "strict output reports stale-path warning"

  result="$(run_check_audit_registry "${tmpdir}" --release)"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "release mode keeps stale-path warnings non-blocking"
  assert_contains "${LAST_OUTPUT}" "Stale test paths:" "release output reports stale test paths"
  assert_contains "${LAST_OUTPUT}" "WARNING: 1 test paths in the registry point to files/directories that don't exist" "release output reports stale-path warning"

  rm -rf "${tmpdir}"
}

test_release_still_fails_for_unaudited() {
  local tmpdir
  local result

  tmpdir="$(setup_fixture)"
  write_registry_fixture "${tmpdir}" "YES" "Unaudited"

  result="$(run_check_audit_registry "${tmpdir}" --release)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "release fails when feature is unaudited"
  assert_contains "${LAST_OUTPUT}" "features are Unaudited" "release output reports unaudited failure"

  rm -rf "${tmpdir}"
}

test_release_fails_for_partial_even_when_audited() {
  local tmpdir
  local result

  tmpdir="$(setup_fixture)"
  write_registry_fixture "${tmpdir}" "PARTIAL" "2026-03-31, session: fixture"

  result="$(run_check_audit_registry "${tmpdir}" --release)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "release fails when cross-user status is PARTIAL"
  assert_contains "${LAST_OUTPUT}" "PARTIAL features:        Demo Feature" "release output names the PARTIAL feature"
  assert_contains "${LAST_OUTPUT}" "incomplete cross-user proof" "release output reports incomplete proof"

  rm -rf "${tmpdir}"
}

test_strict_fails_for_partial
test_strict_fails_for_missing
test_strict_passes_for_yes
test_stale_paths_warn_but_do_not_block_any_mode
test_release_still_fails_for_unaudited
test_release_fails_for_partial_even_when_audited

if [ "${failures}" -ne 0 ]; then
  echo "check_audit_registry_test: FAIL (${failures} assertion(s))"
  exit 1
fi

echo "check_audit_registry_test: PASS"
