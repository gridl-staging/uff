#!/usr/bin/env bash
# Regression test: pre-commit hook must catch violations even when check scripts
# lose their execute bits. Verifies the -f + bash invocation hardening.
#
# Pattern: temp git repo, assert helpers, fixture setup, cleanup.
# See check_test_standards_stage1_regression_test.sh for the established harness.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/lib/workflow_contract_fixtures.sh"
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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "FAIL: ${description} (unexpected '${needle}')"
    failures=$((failures + 1))
  fi
}

# Set up a temp git repo with the pre-commit hook and both check scripts,
# plus violating fixture files staged for commit.
setup_fixture() {
  local hook_path="${1:-.git/hooks/pre-commit}"
  local include_workflow_contract_script="${2:-0}"
  local tmpdir
  tmpdir="$(mktemp -d)"

  # Init a git repo so git diff --cached works
  (cd "${tmpdir}" && git init -q && git config user.email "test@test" && git config user.name "test")

  # Directory structure matching what the hook expects
  mkdir -p "${tmpdir}/scripts"
  mkdir -p "${tmpdir}/scripts/lib"
  mkdir -p "${tmpdir}/docs/feature_archetypes"
  mkdir -p "${tmpdir}/e2e_test/smoke"
  mkdir -p "${tmpdir}/test/unit"
  mkdir -p "${tmpdir}/lib"
  mkdir -p "${tmpdir}/$(dirname "${hook_path}")"

  # Copy check scripts from the real repo
  cp "${REPO_ROOT}/scripts/check_e2e_standards.sh" "${tmpdir}/scripts/"
  cp "${REPO_ROOT}/scripts/check_test_standards.sh" "${tmpdir}/scripts/"
  cp "${REPO_ROOT}/scripts/check_audit_registry.sh" "${tmpdir}/scripts/"
  cp "${REPO_ROOT}/scripts/lib/feature_registry_headings.sh" "${tmpdir}/scripts/lib/"
  if [[ "${include_workflow_contract_script}" == "1" ]]; then
    cp "${REPO_ROOT}/scripts/check_workflow_contracts.sh" "${tmpdir}/scripts/"
  fi

  # Copy the pre-commit hook under test
  cp "${REPO_ROOT}/.scrai/hooks/pre-commit" "${tmpdir}/${hook_path}"
  chmod +x "${tmpdir}/${hook_path}"

  if [[ "${hook_path}" == .githooks/* ]]; then
    (cd "${tmpdir}" && git config core.hooksPath .githooks)
  fi

  # Create a violating e2e test file (uses ref.read which is banned)
  cat > "${tmpdir}/e2e_test/smoke/bad_test.dart" <<'DART'
import 'package:patrol/patrol.dart';

/// ## Test Scenarios
/// - [positive] Banned provider-read fixture for pre-commit gate coverage
void main() {
  patrolTest('bad test', ($) async {
    final val = ref.read(someProvider);
  });
}
DART

  # Create a violating unit test file (bare isNotNull — weak assertion)
  cat > "${tmpdir}/test/unit/bad_test.dart" <<'DART'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Weak assertion fixture for pre-commit gate coverage
void main() {
  test('weak assertion', () {
    expect('value', isNotNull);
  });
}
DART

  # Create a clean e2e test file (no violations)
  cat > "${tmpdir}/e2e_test/smoke/good_test.dart" <<'DART'
import 'package:patrol/patrol.dart';

/// ## Test Scenarios
/// - [positive] Human-like interaction fixture for pre-commit gate coverage
void main() {
  patrolTest('good test', ($) async {
    await $.pumpAndSettle();
  });
}
DART

  # Create a clean unit test file (no violations)
  cat > "${tmpdir}/test/unit/good_test.dart" <<'DART'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Exact assertion fixture for pre-commit gate coverage
void main() {
  test('good assertion', () {
    expect(1 + 1, equals(2));
  });
}
DART

  printf '%s\n' "$tmpdir"
}

write_project_local_bypass_hook() {
  local tmpdir="$1"

  mkdir -p "${tmpdir}/.scrai/hooks"
  cat > "${tmpdir}/.scrai/hooks/pre-commit-local" <<'SH'
#!/usr/bin/env bash
# Intentional escape hatch for urgent snapshot commits.
# The parent pre-commit hook sources this file before any checks.
if [ "${UFF_PRECOMMIT_BYPASS:-0}" = "1" ]; then
  echo "pre-commit bypassed: UFF_PRECOMMIT_BYPASS=1"
  exit 0
fi

# Fall through to the parent hook when the bypass is not enabled.
return 0 2>/dev/null || exit 0
SH
  chmod +x "${tmpdir}/.scrai/hooks/pre-commit-local"
}

# Run the pre-commit hook in the temp repo. Returns "exit_code\noutput".
run_hook() {
  local tmpdir="$1"
  local hook_path="${2:-.git/hooks/pre-commit}"
  local path_override="${3:-}"
  local output=""
  local exit_code=0
  if [[ -n "${path_override}" ]]; then
    output="$(cd "${tmpdir}" && PATH="${path_override}" /bin/bash "${hook_path}" 2>&1)" || exit_code=$?
  else
    output="$(cd "${tmpdir}" && /bin/bash "${hook_path}" 2>&1)" || exit_code=$?
  fi
  printf '%s\n' "${exit_code}"
  printf '%s\n' "${output}"
}

write_registry_with_onboarded_feature() {
  local tmpdir="$1"
  local workflow_lines="${2:-}"
  local cross_user_status="${3:-YES}"

  if [[ -z "${workflow_lines}" ]]; then
    workflow_lines="$(cat <<'EOF'
- [x] `media.select_source` - e2e_test/smoke/photo_flow_test.dart
- [ ] `crud.update` - NOT_IMPLEMENTED
EOF
)"
  fi

  {
    cat <<EOF
# Feature Test Audit Registry

## Features

### Photos

- **Area**: lib/src/features/photos/
- **User-scoped data**: yes
- **Test files**:
  - e2e_test/smoke/photo_flow_test.dart
- **Cross-user negative test**: ${cross_user_status}
- **Archetypes**: media, crud
- **Workflow Contract**:
EOF
    printf '%s\n' "${workflow_lines}"
    cat <<'EOF'
- **Known gaps**: none
- **Dev-audit**: 2026-03-29, session: fixture
- **Cross-audit**: 2026-03-29, session: fixture
EOF
  } > "${tmpdir}/docs/feature_test_audit_registry.md"

  write_archetype_catalog "${tmpdir}" "media" "media.select_source"
  write_archetype_catalog "${tmpdir}" "crud" "crud.create" "crud.read" "crud.update" "crud.delete"

  build_workflow_evidence_stubs "${tmpdir}" "${workflow_lines}"
}

# Test: violations are caught even when check scripts have no execute bits
test_catches_violations_without_exec_bits() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  # Stage the violating files
  (cd "${tmpdir}" && git add e2e_test/smoke/bad_test.dart test/unit/bad_test.dart)

  # Strip execute bits from both check scripts — simulates the mar26 incident
  chmod -x "${tmpdir}/scripts/check_e2e_standards.sh"
  chmod -x "${tmpdir}/scripts/check_test_standards.sh"

  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "1" "${exit_code}" \
    "hook exits non-zero when violations present and scripts lack +x"
  assert_contains "${output}" "VIOLATION" \
    "hook output includes VIOLATION despite missing execute bits"

  rm -rf "${tmpdir}"
}

# Test: configured .githooks path still enforces checks when scripts lose +x
test_catches_violations_from_githooks_path_without_exec_bits() {
  local tmpdir
  tmpdir="$(setup_fixture ".githooks/pre-commit")"

  # Stage the violating files
  (cd "${tmpdir}" && git add e2e_test/smoke/bad_test.dart test/unit/bad_test.dart)

  # Strip execute bits from both check scripts — simulates the mar26 incident
  chmod -x "${tmpdir}/scripts/check_e2e_standards.sh"
  chmod -x "${tmpdir}/scripts/check_test_standards.sh"

  local result
  result="$(run_hook "${tmpdir}" ".githooks/pre-commit")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "1" "${exit_code}" \
    "configured .githooks hook exits non-zero when violations present and scripts lack +x"
  assert_contains "${output}" "VIOLATION" \
    "configured .githooks hook output includes VIOLATION despite missing execute bits"

  rm -rf "${tmpdir}"
}

# Test: staged e2e files must block commits if the e2e checker is missing
test_blocks_when_e2e_check_script_is_missing() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  # Stage an e2e file so the hook must run the e2e standards checker
  (cd "${tmpdir}" && git add e2e_test/smoke/bad_test.dart)

  # Remove the checker entirely — enforcement must fail closed, not skip
  rm -f "${tmpdir}/scripts/check_e2e_standards.sh"

  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "1" "${exit_code}" \
    "hook exits non-zero when staged e2e files cannot be validated"
  assert_contains "${output}" "missing scripts/check_e2e_standards.sh" \
    "hook reports the missing e2e standards checker"

  rm -rf "${tmpdir}"
}

# Test: staged unit/integration files must block commits if the test checker is missing
test_blocks_when_test_check_script_is_missing() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  # Stage a test file so the hook must run the staged test standards checker
  (cd "${tmpdir}" && git add test/unit/bad_test.dart)

  # Remove the checker entirely — enforcement must fail closed, not skip
  rm -f "${tmpdir}/scripts/check_test_standards.sh"

  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "1" "${exit_code}" \
    "hook exits non-zero when staged test files cannot be validated"
  assert_contains "${output}" "missing scripts/check_test_standards.sh" \
    "hook reports the missing staged test checker"

  rm -rf "${tmpdir}"
}

# Test: hook passes cleanly when no violating files are staged
test_passes_with_clean_staged_files() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  # Stage only the clean files
  (cd "${tmpdir}" && git add e2e_test/smoke/good_test.dart test/unit/good_test.dart)

  # Strip execute bits here too — should still pass (no violations to find)
  chmod -x "${tmpdir}/scripts/check_e2e_standards.sh"
  chmod -x "${tmpdir}/scripts/check_test_standards.sh"

  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"

  assert_eq "0" "${exit_code}" \
    "hook exits zero when clean files staged and scripts lack +x"

  rm -rf "${tmpdir}"
}

# Test: hook passes when nothing is staged (no e2e or test files)
test_passes_with_nothing_staged() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  # Don't stage anything — hook should be a no-op
  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"

  assert_eq "0" "${exit_code}" \
    "hook exits zero when nothing is staged"

  rm -rf "${tmpdir}"
}

test_project_local_hook_keeps_normal_checks_when_bypass_is_disabled() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  write_project_local_bypass_hook "${tmpdir}"

  (cd "${tmpdir}" && git add e2e_test/smoke/bad_test.dart test/unit/bad_test.dart)

  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "1" "${exit_code}" \
    "local hook must not disable normal enforcement when the bypass env var is absent"
  assert_contains "${output}" "VIOLATION" \
    "normal enforcement still reports violations when the local hook is present"
  assert_not_contains "${output}" "pre-commit bypassed: UFF_PRECOMMIT_BYPASS=1" \
    "bypass message stays hidden unless the override is explicitly enabled"

  rm -rf "${tmpdir}"
}

test_project_local_hook_bypasses_checks_when_explicitly_enabled() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  write_project_local_bypass_hook "${tmpdir}"

  (cd "${tmpdir}" && git add e2e_test/smoke/bad_test.dart test/unit/bad_test.dart)

  local result
  result="$(UFF_PRECOMMIT_BYPASS=1 run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "0" "${exit_code}" \
    "local hook must allow an explicit bypass for urgent snapshot commits"
  assert_contains "${output}" "pre-commit bypassed: UFF_PRECOMMIT_BYPASS=1" \
    "bypass output makes the override explicit"
  assert_not_contains "${output}" "VIOLATION" \
    "bypass path skips the parent checks entirely"

  rm -rf "${tmpdir}"
}

test_dart_format_gate_blocks_on_unformatted_staged_dart() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  cat > "${tmpdir}/lib/bad.dart" <<'DART'
void main( ){
  print("bad");
}
DART
  (cd "${tmpdir}" && git add lib/bad.dart)

  local shim_dir
  shim_dir="$(mktemp -d)"
  cat > "${shim_dir}/dart" <<'SH'
#!/usr/bin/env bash
echo "Could not format because the source could not be parsed." >&2
exit 1
SH
  chmod +x "${shim_dir}/dart"

  local result
  result="$(run_hook "${tmpdir}" ".git/hooks/pre-commit" "${shim_dir}:${PATH}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "1" "${exit_code}" "hook exits non-zero when staged dart file fails format check"
  assert_contains "${output}" "Could not format because the source could not be parsed." \
    "hook output includes dart format failure details"

  rm -rf "${shim_dir}"
  rm -rf "${tmpdir}"
}

test_dart_format_gate_passes_on_clean_staged_dart() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  cat > "${tmpdir}/lib/good.dart" <<'DART'
void main() {
  print("good");
}
DART
  (cd "${tmpdir}" && git add lib/good.dart)

  local shim_dir
  shim_dir="$(mktemp -d)"
  cat > "${shim_dir}/dart" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "${shim_dir}/dart"

  local result
  result="$(run_hook "${tmpdir}" ".git/hooks/pre-commit" "${shim_dir}:${PATH}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"

  assert_eq "0" "${exit_code}" "hook exits zero when staged dart file passes format check"

  rm -rf "${shim_dir}"
  rm -rf "${tmpdir}"
}

test_dart_format_gate_skips_when_dart_not_on_path() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  cat > "${tmpdir}/lib/no_dart_tool.dart" <<'DART'
void main() {
  print("no dart");
}
DART
  (cd "${tmpdir}" && git add lib/no_dart_tool.dart)

  local empty_bin
  empty_bin="$(mktemp -d)"

  local result
  result="$(run_hook "${tmpdir}" ".git/hooks/pre-commit" "${empty_bin}:/usr/bin:/bin")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "0" "${exit_code}" "hook exits zero when dart is missing from PATH"
  assert_contains "${output}" "pre-commit: dart is not on PATH; skipping staged Dart format check." \
    "hook warns when dart is unavailable"

  rm -rf "${empty_bin}"
  rm -rf "${tmpdir}"
}

test_workflow_contract_gate_blocks_on_trigger_paths() {
  local tmpdir
  tmpdir="$(setup_fixture ".git/hooks/pre-commit" "1")"

  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `media.select_source` - e2e_test/smoke/photo_flow_test.dart
- [ ] `crud.update` - NOT_IMPLEMENTED
EOF
)"
  (cd "${tmpdir}" && git add docs/feature_test_audit_registry.md)

  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "1" "${exit_code}" "hook exits non-zero when staged workflow contract input fails strict check"
  assert_contains "${output}" "NOT_IMPLEMENTED" \
    "hook output includes workflow-contract strict failure details"

  rm -rf "${tmpdir}"
}

test_workflow_contract_gate_blocks_on_staged_archetype_catalog() {
  local tmpdir
  tmpdir="$(setup_fixture ".git/hooks/pre-commit" "1")"

  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `media.select_source` - e2e_test/smoke/photo_flow_test.dart
- [ ] `crud.update` - NOT_IMPLEMENTED
EOF
)"
  printf '\n| media.capture | Added trigger coverage | Always |\n' >> "${tmpdir}/docs/feature_archetypes/media.md"
  (cd "${tmpdir}" && git add docs/feature_archetypes/media.md)

  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "1" "${exit_code}" \
    "hook exits non-zero when a staged archetype catalog triggers strict workflow validation"
  assert_contains "${output}" "NOT_IMPLEMENTED" \
    "hook output includes workflow-contract failure details for staged archetype catalogs"

  rm -rf "${tmpdir}"
}

test_workflow_contract_gate_blocks_on_staged_checker_script() {
  local tmpdir
  tmpdir="$(setup_fixture ".git/hooks/pre-commit" "1")"

  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `media.select_source` - e2e_test/smoke/photo_flow_test.dart
- [ ] `crud.update` - NOT_IMPLEMENTED
EOF
)"
  printf '\n# staged trigger coverage\n' >> "${tmpdir}/scripts/check_workflow_contracts.sh"
  (cd "${tmpdir}" && git add scripts/check_workflow_contracts.sh)

  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "1" "${exit_code}" \
    "hook exits non-zero when the staged workflow checker script triggers strict validation"
  assert_contains "${output}" "NOT_IMPLEMENTED" \
    "hook output includes workflow-contract failure details for staged checker script changes"

  rm -rf "${tmpdir}"
}

test_workflow_contract_gate_skips_when_no_trigger_paths_staged() {
  local tmpdir
  tmpdir="$(setup_fixture ".git/hooks/pre-commit" "1")"

  cat > "${tmpdir}/scripts/check_workflow_contracts.sh" <<'SH'
#!/usr/bin/env bash
echo "unexpected workflow gate invocation"
exit 1
SH
  chmod +x "${tmpdir}/scripts/check_workflow_contracts.sh"
  printf '%s\n' "no trigger file" > "${tmpdir}/README.md"
  (cd "${tmpdir}" && git add README.md)

  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "0" "${exit_code}" "hook exits zero when no workflow trigger path is staged"
  assert_not_contains "${output}" "unexpected workflow gate invocation" \
    "hook does not run workflow-contract script without trigger paths"

  rm -rf "${tmpdir}"
}

# Test: advisory audit-registry scorecard appears when registry is staged, hook still exits 0
test_advisory_audit_registry_scorecard_on_staged_registry() {
  local tmpdir
  tmpdir="$(setup_fixture ".git/hooks/pre-commit" "1")"

  # Generate a registry with PARTIAL cross-user status and a valid workflow contract
  # (all requirements satisfied) so the workflow-contract gate passes.
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `media.select_source` - e2e_test/smoke/photo_flow_test.dart
- [x] `crud.update` - e2e_test/smoke/photo_flow_test.dart
EOF
)" "PARTIAL"
  (cd "${tmpdir}" && git add docs/feature_test_audit_registry.md)

  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "0" "${exit_code}" \
    "hook exits zero when advisory audit scorecard runs (non-blocking)"
  assert_contains "${output}" "Feature Test Audit Registry Scorecard" \
    "hook output includes the audit registry scorecard heading"
  assert_contains "${output}" "PARTIAL" \
    "hook output includes PARTIAL status from the audit registry scorecard"

  rm -rf "${tmpdir}"
}

# Test: advisory audit section does NOT fire when registry is not staged
test_advisory_audit_registry_skips_when_registry_not_staged() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  # Replace the provisioned audit script with a sentinel that would fail if invoked
  cat > "${tmpdir}/scripts/check_audit_registry.sh" <<'SH'
#!/usr/bin/env bash
echo "SENTINEL: unexpected audit invocation"
exit 1
SH

  printf '%s\n' "no trigger file" > "${tmpdir}/README.md"
  (cd "${tmpdir}" && git add README.md)

  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "0" "${exit_code}" \
    "hook exits zero when registry is not staged"
  assert_not_contains "${output}" "SENTINEL: unexpected audit invocation" \
    "hook does not invoke audit registry script when registry is not staged"

  rm -rf "${tmpdir}"
}

test_blocks_when_workflow_contract_script_is_missing() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `media.select_source` - e2e_test/smoke/photo_flow_test.dart
- [ ] `crud.update` - NOT_IMPLEMENTED
EOF
)"
  (cd "${tmpdir}" && git add docs/feature_test_audit_registry.md)

  local result
  result="$(run_hook "${tmpdir}")"
  local exit_code
  exit_code="$(printf '%s\n' "${result}" | sed -n '1p')"
  local output
  output="$(printf '%s\n' "${result}" | tail -n +2)"

  assert_eq "1" "${exit_code}" \
    "hook exits non-zero when workflow trigger path is staged but script is missing"
  assert_contains "${output}" "missing scripts/check_workflow_contracts.sh" \
    "hook reports missing workflow-contract script"

  rm -rf "${tmpdir}"
}

main() {
  test_catches_violations_without_exec_bits
  test_catches_violations_from_githooks_path_without_exec_bits
  test_blocks_when_e2e_check_script_is_missing
  test_blocks_when_test_check_script_is_missing
  test_passes_with_clean_staged_files
  test_passes_with_nothing_staged
  test_dart_format_gate_blocks_on_unformatted_staged_dart
  test_dart_format_gate_passes_on_clean_staged_dart
  test_dart_format_gate_skips_when_dart_not_on_path
  test_workflow_contract_gate_blocks_on_trigger_paths
  test_workflow_contract_gate_blocks_on_staged_archetype_catalog
  test_workflow_contract_gate_blocks_on_staged_checker_script
  test_workflow_contract_gate_skips_when_no_trigger_paths_staged
  test_blocks_when_workflow_contract_script_is_missing
  test_advisory_audit_registry_scorecard_on_staged_registry
  test_advisory_audit_registry_skips_when_registry_not_staged

  if [[ "${failures}" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "precommit_hook_hardening_test: PASS"
}

main "$@"
