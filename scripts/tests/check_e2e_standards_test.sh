#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
failures=0

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

setup_fixture() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  mkdir -p "${tmpdir}/scripts" "${tmpdir}/e2e_test/smoke" "${tmpdir}/e2e_test/full"
  cp "${REPO_ROOT}/scripts/check_e2e_standards.sh" "${tmpdir}/scripts/"

  printf '%s\n' "$tmpdir"
}

run_checker() {
  local fixture_root="$1"
  local output=""
  local exit_code=0

  output="$(cd "${fixture_root}" && bash ./scripts/check_e2e_standards.sh 2>&1)" || exit_code=$?

  printf '%s\n' "$exit_code"
  printf '%s\n' "$output"
}

test_detects_provider_read_pattern_with_parentheses() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  cat > "${fixture_root}/e2e_test/smoke/provider_read_test.dart" <<'DART'
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('provider read is banned', ($) async {
    final value = ref.read(someProvider);
    expect(value, isNotNull);
  });
}
DART

  local result
  result="$(run_checker "${fixture_root}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "1" "${exit_code}" "checker exits non-zero for banned ref.read(...)"
  assert_contains "${output}" "Direct provider state read" "checker reports provider read violation"
  assert_contains "${output}" "provider_read_test.dart" "checker reports violating file path"

  rm -rf "${fixture_root}"
}

test_detects_raw_tester_pump_pattern_with_parentheses() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  cat > "${fixture_root}/e2e_test/smoke/raw_tester_pump_test.dart" <<'DART'
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('raw tester pump is banned', ($) async {
    await $.tester.pump(const Duration(milliseconds: 16));
  });
}
DART

  local result
  result="$(run_checker "${fixture_root}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "1" "${exit_code}" "checker exits non-zero for banned tester.pump(...)"
  assert_contains "${output}" "Raw flutter_test API (pump)" "checker reports tester.pump violation"
  assert_contains "${output}" "raw_tester_pump_test.dart" "checker reports violating pump file path"

  rm -rf "${fixture_root}"
}

test_passes_for_clean_test_file() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  cat > "${fixture_root}/e2e_test/smoke/clean_test.dart" <<'DART'
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('clean test', ($) async {
    await $(find.text('Continue')).tap();
  });
}
DART

  local result
  result="$(run_checker "${fixture_root}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"

  assert_eq "0" "${exit_code}" "checker exits zero for clean smoke test"

  rm -rf "${fixture_root}"
}

main() {
  test_detects_provider_read_pattern_with_parentheses
  test_detects_raw_tester_pump_pattern_with_parentheses
  test_passes_for_clean_test_file

  if [[ "${failures}" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "check_e2e_standards_test: PASS"
}

main "$@"
