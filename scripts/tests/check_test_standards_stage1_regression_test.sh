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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "FAIL: ${description} (unexpected '${needle}')"
    failures=$((failures + 1))
  fi
}

run_check_test_standards() {
  local tmpdir="$1"
  shift

  local output=""
  local exit_code=0
  output="$(
    cd "${tmpdir}" &&
    ./scripts/check_test_standards.sh "$@" 2>&1
  )" || exit_code=$?

  printf '%s\n' "${exit_code}"
  printf '%s\n' "${output}"
}

setup_fixture() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p \
    "${tmpdir}/scripts" \
    "${tmpdir}/scripts/lib" \
    "${tmpdir}/docs" \
    "${tmpdir}/test/integration" \
    "${tmpdir}/test/src/features/alpha/presentation" \
    "${tmpdir}/test/src/features/beta/presentation" \
    "${tmpdir}/test/src/features/delta/presentation" \
    "${tmpdir}/test/src/features/gamma/presentation" \
    "${tmpdir}/test/src/features/ambiguous/presentation" \
    "${tmpdir}/test/src/features/unmapped/presentation" \
    "${tmpdir}/test/src/routing" \
    "${tmpdir}/integration_test" \
    "${tmpdir}/e2e_test/smoke"
  cp "${REPO_ROOT}/scripts/check_test_standards.sh" "${tmpdir}/scripts/"
  cp "${REPO_ROOT}/scripts/lib/feature_registry_headings.sh" "${tmpdir}/scripts/lib/"
  chmod +x "${tmpdir}/scripts/check_test_standards.sh"

  cat > "${tmpdir}/docs/feature_test_audit_registry.md" <<'EOF'
# Feature Test Audit Registry

## Features

### Alpha Feature

- **Area**: lib/src/features/alpha/
- **User-scoped data**: yes
- **Test files**:
  - test/src/features/alpha/presentation/alpha_missing_required_tags_test.dart
- **Cross-user negative test**: YES (fixture)
- **Known gaps**: fixture
- **Dev-audit**: 2026-03-29, session: fixture
- **Cross-audit**: 2026-03-29, session: fixture

### Beta Feature

- **Area**: lib/src/features/beta/
- **User-scoped data**: no
- **Test files**:
  - test/src/features/beta/presentation/beta_non_user_scoped_header_test.dart
- **Cross-user negative test**: N/A
- **Known gaps**: fixture
- **Dev-audit**: 2026-03-29, session: fixture
- **Cross-audit**: 2026-03-29, session: fixture

### Gamma Feature

- **Area**: lib/src/features/gamma/
- **User-scoped data**: yes
- **Test files**:
  - test/src/features/gamma/presentation/gamma_missing_cross_user_test.dart
- **Cross-user negative test**: MISSING
- **Known gaps**: fixture
- **Dev-audit**: 2026-03-29, session: fixture
- **Cross-audit**: 2026-03-29, session: fixture

### Delta Feature

- **Area**: lib/src/features/delta/
- **User-scoped data**: yes
- **Test files**:
  - test/src/features/delta/presentation/delta_partial_cross_user_test.dart
- **Cross-user negative test**: PARTIAL (fixture reason)
- **Known gaps**: fixture
- **Dev-audit**: 2026-03-29, session: fixture
- **Cross-audit**: 2026-03-29, session: fixture

### Ambiguous Feature A

- **Area**: lib/src/features/ambiguous/
- **User-scoped data**: yes
- **Test files**:
  - test/src/features/ambiguous/presentation/ambiguous_mapping_test.dart
- **Cross-user negative test**: MISSING
- **Known gaps**: fixture
- **Dev-audit**: 2026-03-29, session: fixture
- **Cross-audit**: 2026-03-29, session: fixture

### Ambiguous Feature B

- **Area**: lib/src/features/ambiguous/
- **User-scoped data**: yes
- **Test files**:
  - test/src/features/ambiguous/presentation/ambiguous_mapping_test.dart
- **Cross-user negative test**: MISSING
- **Known gaps**: fixture
- **Dev-audit**: 2026-03-29, session: fixture
- **Cross-audit**: 2026-03-29, session: fixture

## Audit Log

- fixture
EOF

  cat > "${tmpdir}/test/integration/annotated_weak_assertion_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Annotated weak contracts are exempt when explicitly allowed
void main() {
  test('annotated weak contracts are intentional', () {
    // test-standards:allow-weak-assertion Stage 1 fixture: runtime-generated
    expect('value', isNotEmpty);
    // test-standards:allow-weak-assertion Stage 1 fixture: type guard only
    expect(const Object(), isA<Object>());
  });
}
EOF

  cat > "${tmpdir}/test/integration/unannotated_weak_assertion_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Unannotated weak assertion remains blocking
void main() {
  test('unannotated weak assertion stays blocking', () {
    expect('value', isNotNull);
  });
}
EOF

  cat > "${tmpdir}/test/integration/commented_out_weak_assertion_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Commented-out weak assertions should be ignored
void main() {
  test('commented weak assertion stays non-blocking', () {
    // expect('value', isNotNull);
    expect(true, isTrue);
  });
}
EOF

  cat > "${tmpdir}/test/integration/annotated_multiline_weak_assertion_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Annotated multiline weak assertion remains exempted
void main() {
  test('annotated multiline weak assertion is exempted', () {
    // test-standards:allow-weak-assertion Stage 1 fixture: profile-style
    // runtime-dependent default.
    expect(
      'runtime-default',
      isNotEmpty,
      reason: 'profile trigger default is runtime dependent',
    );
  });
}
EOF

  cat > "${tmpdir}/test/integration/matcher_line_annotated_multiline_weak_assertion_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Matcher-line exemption token remains supported
void main() {
  test('matcher-line token exempts multiline weak assertion', () {
    expect(
      'runtime-default',
      isNotEmpty, // test-standards:allow-weak-assertion
      reason: 'matcher line carries the exemption token',
    );
  });
}
EOF

  cat > "${tmpdir}/test/integration/unannotated_multiline_weak_assertion_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Unannotated multiline weak assertion remains blocking
void main() {
  test('unannotated multiline weak assertion remains blocking', () {
    expect(
      'runtime-default',
      isNotEmpty,
      reason: 'still weak when value should be exact',
    );
  });
}
EOF

  cat > "${tmpdir}/integration_test/privacy_zone_contract_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backing integration test contains concrete assertions', () {
    expect(1 + 1, 2);
  });
}
EOF

  cat > "${tmpdir}/integration_test/top_level_integration_weak_assertion_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Top-level integration tests are still scanned in staged mode
void main() {
  test('top-level integration tests are scanned in staged mode', () {
    expect('value', isNotEmpty);
  });
}
EOF

  cat > "${tmpdir}/test/integration/privacy_zone_wrapper_test.dart" <<'EOF'
import '../../integration_test/privacy_zone_contract_test.dart' as contract_test;

void main() => contract_test.main();
EOF

  cat > "${tmpdir}/test/integration/no_expect_non_wrapper_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Non-wrapper files with zero expect still warn
void main() {
  test('no expect should warn when not a wrapper', () async {
    await Future<void>.value();
  });
}
EOF

  cat > "${tmpdir}/test/integration/preimport_comment_then_header_test.dart" <<'EOF'
// Fixture note before imports should not satisfy or block CHECK 4.

import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] First comment block after imports still satisfies CHECK 4
void main() {
  test('pre-import comment stays non-blocking', () {
    expect(16 + 16, 32);
  });
}
EOF

cat > "${tmpdir}/test/src/features/gamma/presentation/gamma_missing_cross_user_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Fixture keeps exact assertion style
/// - [negative] Registry-backed enforcement consumes this tag instead of greps
/// - [isolation] Registry-backed enforcement consumes this tag instead of greps
void main() {
  test('mapped user-scoped fixture uses exact values', () {
    expect(1 + 1, 2);
  });
}
EOF

  cat > "${tmpdir}/test/src/features/delta/presentation/delta_partial_cross_user_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Delta feature has partial cross-user coverage
/// - [negative] Partial cross-user negative test exists
/// - [isolation] Partial isolation test exists
void main() {
  test('delta partial cross-user fixture', () {
    expect(19 + 19, 38);
  });
}
EOF

  cat > "${tmpdir}/test/src/features/alpha/presentation/alpha_missing_scenario_header_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing scenario header remains deterministic', () {
    expect(2 + 2, 4);
  });
}
EOF

  cat > "${tmpdir}/test/src/features/alpha/presentation/alpha_missing_required_tags_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Header exists but omits user-scope tags
void main() {
  test('fixture omits negative and isolation tags', () {
    expect(3 + 3, 6);
  });
}
EOF

  cat > "${tmpdir}/test/src/features/alpha/presentation/alpha_missing_statemachine_tag_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Fixture repeats one interaction call without statemachine tag
/// - [negative] Maintains explicit cross-user negative tag
/// - [isolation] Maintains explicit isolation tag
void main() {
  test('repeated single interaction without statemachine tag is non-blocking', () {
    didMapViewInputsChange();
    didMapViewInputsChange();
    didMapViewInputsChange();
    expect(4 + 4, 8);
  });
}

void didMapViewInputsChange() {}
EOF

  cat > "${tmpdir}/test/src/features/alpha/presentation/alpha_tagged_statemachine_without_distinct_calls_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Fixture uses tagged statemachine scenario
/// - [negative] Maintains explicit cross-user negative tag
/// - [isolation] Maintains explicit isolation tag
/// - [statemachine] Tagged statemachine scenario must include distinct calls
void main() {
  test('tagged statemachine fixture repeats one interaction call', () {
    didMapViewInputsChange();
    didMapViewInputsChange();
    didMapViewInputsChange();
    expect(13 + 13, 26);
  });
}

void didMapViewInputsChange() {}
EOF

  cat > "${tmpdir}/test/src/features/alpha/presentation/alpha_statemachine_calls_split_across_tests_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Fixture mixes stateful and non-stateful expectations in one file
/// - [negative] Maintains explicit cross-user negative tag
/// - [isolation] Maintains explicit isolation tag
/// - [statemachine] Tagged flow must satisfy the contract within a single test block
void main() {
  test('first test block only uses one interaction type', () {
    didMapViewInputsChange();
    didMapViewInputsChange();
    expect(17 + 17, 34);
  });

  test('second test block adds different interactions elsewhere in the file', () {
    buildUserLocationViewportState();
    waitForVisibleState();
    expect(18 + 18, 36);
  });
}

void didMapViewInputsChange() {}
void buildUserLocationViewportState() {}
void waitForVisibleState() {}
EOF

  cat > "${tmpdir}/test/src/features/alpha/presentation/alpha_double_slash_header_tags_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

// ## Test Scenarios
// - [positive] Double-slash header style should parse
// - [negative] Bare negative tag should parse
// - [isolation] Bare isolation tag should parse
// - [statemachine] Bare statemachine tag should parse
void main() {
  test('double slash header fixture', () {
    didMapViewInputsChange();
    buildUserLocationViewportState();
    waitForVisibleState();
    expect(5 + 5, 10);
  });
}

void didMapViewInputsChange() {}
void buildUserLocationViewportState() {}
void waitForVisibleState() {}
EOF

  cat > "${tmpdir}/test/src/features/alpha/presentation/alpha_backticked_header_tags_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - `[positive]` Backticked positive tag should parse
/// - `[negative]` Backticked negative tag should parse
/// - `[isolation]` Backticked isolation tag should parse
/// - `[statemachine]` Backticked statemachine tag should parse
void main() {
  test('backticked header fixture', () {
    didMapViewInputsChange();
    buildUserLocationViewportState();
    waitForVisibleState();
    expect(6 + 6, 12);
  });
}

void didMapViewInputsChange() {}
void buildUserLocationViewportState() {}
void waitForVisibleState() {}
EOF

  cat > "${tmpdir}/test/src/features/beta/presentation/beta_non_user_scoped_header_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Non-user-scoped feature should not require negative/isolation tags
void main() {
  test('non-user-scoped fixture', () {
    expect(7 + 7, 14);
  });
}
EOF

  # Late-header fixture: scenario block appears AFTER code, not in the first block.
  # CHECK 4 must reject this — the header must precede any non-import code.
  cat > "${tmpdir}/test/src/features/alpha/presentation/alpha_late_scenario_header_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('late header should not satisfy CHECK 4', () {
    expect(14 + 14, 28);
  });
}

/// ## Test Scenarios
/// - [positive] This header appears after code, not in the first block
/// - [negative] Late negative tag should not count
/// - [isolation] Late isolation tag should not count
EOF

  # Leading-comment-gap fixture: first comment block is not the scenario header.
  # CHECK 4 must reject this — the first comment block after imports must be
  # the scenario header block.
  cat > "${tmpdir}/test/src/features/alpha/presentation/alpha_scenario_header_after_leading_comment_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// TODO: fixture note that is intentionally not the scenario header.
/// This leading comment block should force CHECK 4 failure.

/// ## Test Scenarios
/// - [positive] Header exists but not in the first comment block
/// - [negative] This should not satisfy user-scoped requirements
/// - [isolation] This should not satisfy user-scoped requirements
void main() {
  test('leading comment gap should fail CHECK 4', () {
    expect(15 + 15, 30);
  });
}
EOF

  cat > "${tmpdir}/test/src/features/ambiguous/presentation/ambiguous_mapping_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Ambiguous mapping fixture
void main() {
  test('ambiguous fixture', () {
    expect(8 + 8, 16);
  });
}
EOF

  cat > "${tmpdir}/test/src/features/unmapped/presentation/unmapped_mapping_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Unmapped mapping fixture
void main() {
  test('unmapped fixture', () {
    expect(9 + 9, 18);
  });
}
EOF

  cat > "${tmpdir}/test/src/routing/routing_contract_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Routing path is a known mapping skip
void main() {
  test('routing fixture', () {
    expect(10 + 10, 20);
  });
}
EOF

  cat > "${tmpdir}/integration_test/integration_info_skip_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

/// ## Test Scenarios
/// - [positive] Integration path is a known mapping skip
void main() {
  test('integration fixture', () {
    expect(11 + 11, 22);
  });
}
EOF

  cat > "${tmpdir}/e2e_test/smoke/e2e_info_skip_test.dart" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('e2e fixture', () {
    expect('value', isNotEmpty);
  });
}
EOF

  printf '%s\n' "$tmpdir"
}

test_stage1_contract() {
  local tmpdir
  tmpdir="$(setup_fixture)"

  local full_result
  full_result="$(run_check_test_standards "${tmpdir}")"
  local full_exit_code
  full_exit_code="$(printf '%s\n' "${full_result}" | sed -n '1p')"
  local full_output
  full_output="$(printf '%s\n' "${full_result}" | tail -n +2)"

  assert_eq "1" "${full_exit_code}" "stage1 full-scan fixture run exits non-zero due bad unannotated weak assertion"
  assert_contains "${full_output}" "VIOLATION: test/integration/unannotated_weak_assertion_test.dart:" \
    "bad unannotated weak assertion is still reported"
  assert_contains "${full_output}" "VIOLATION: test/integration/unannotated_multiline_weak_assertion_test.dart:" \
    "bad unannotated multiline weak assertion is still reported"
  assert_contains "${full_output}" "VIOLATION: integration_test/top_level_integration_weak_assertion_test.dart:" \
    "full scan includes top-level integration tests"
  assert_not_contains "${full_output}" "VIOLATION: test/integration/commented_out_weak_assertion_test.dart:" \
    "commented-out weak assertion is ignored"
  assert_not_contains "${full_output}" "VIOLATION: test/integration/annotated_weak_assertion_test.dart:" \
    "annotated isNotEmpty/isA contracts are exempted"
  assert_not_contains "${full_output}" "VIOLATION: test/integration/annotated_multiline_weak_assertion_test.dart:" \
    "annotated multiline weak assertion is exempted"
  assert_not_contains "${full_output}" "VIOLATION: test/integration/matcher_line_annotated_multiline_weak_assertion_test.dart:" \
    "matcher-line token exempts multiline weak assertion"
  assert_not_contains "${full_output}" "WARNING: test/integration/privacy_zone_wrapper_test.dart" \
    "wrapper file with zero expect does not warn"
  assert_contains "${full_output}" "WARNING: test/integration/no_expect_non_wrapper_test.dart" \
    "non-wrapper file with zero expect still warns"
  assert_contains "${full_output}" "WARNING: test/src/features/delta/presentation/delta_partial_cross_user_test.dart" \
    "full-scan emits CHECK 3 WARNING for PARTIAL cross-user feature"
  assert_contains "${full_output}" "PARTIAL" \
    "full-scan CHECK 3 WARNING message includes the word PARTIAL"
  assert_contains "${full_output}" "scripts/check_audit_registry.sh --strict" \
    "full-scan CHECK 3 PARTIAL warning points to strict audit gate owner for blocking enforcement"
  assert_not_contains "${full_output}" "VIOLATION: test/src/features/delta/presentation/delta_partial_cross_user_test.dart:" \
    "full-scan does NOT emit VIOLATION for PARTIAL cross-user feature"

  (
    cd "${tmpdir}" &&
    git init >/dev/null &&
    git add test integration_test e2e_test docs
  )

  local staged_result
  staged_result="$(run_check_test_standards "${tmpdir}" --staged)"
  local staged_exit_code
  staged_exit_code="$(printf '%s\n' "${staged_result}" | sed -n '1p')"
  local staged_output
  staged_output="$(printf '%s\n' "${staged_result}" | tail -n +2)"

  assert_eq "1" "${staged_exit_code}" "stage1 staged fixture run exits non-zero due bad unannotated weak assertion"
  assert_contains "${staged_output}" "VIOLATION: test/integration/unannotated_weak_assertion_test.dart:" \
    "staged scan still reports unannotated weak assertion"
  assert_contains "${staged_output}" "VIOLATION: test/integration/unannotated_multiline_weak_assertion_test.dart:" \
    "staged scan still reports unannotated multiline weak assertion"
  assert_contains "${staged_output}" "VIOLATION: integration_test/top_level_integration_weak_assertion_test.dart:" \
    "staged scan includes top-level integration tests"
  assert_not_contains "${staged_output}" "VIOLATION: test/integration/commented_out_weak_assertion_test.dart:" \
    "staged scan ignores commented-out weak assertion"
  assert_not_contains "${staged_output}" "VIOLATION: test/integration/annotated_weak_assertion_test.dart:" \
    "staged scan exempts annotated weak assertions"
  assert_not_contains "${staged_output}" "VIOLATION: test/integration/annotated_multiline_weak_assertion_test.dart:" \
    "staged scan exempts annotated multiline weak assertion"
  assert_not_contains "${staged_output}" "VIOLATION: test/integration/matcher_line_annotated_multiline_weak_assertion_test.dart:" \
    "staged scan honors matcher-line multiline exemption tokens"
  assert_not_contains "${staged_output}" "WARNING: test/integration/privacy_zone_wrapper_test.dart" \
    "staged scan skips pass-through wrappers with zero expect"
  assert_contains "${staged_output}" "WARNING: test/integration/no_expect_non_wrapper_test.dart" \
    "staged scan still warns for non-wrapper files with zero expect"
  assert_not_contains "${staged_output}" "VIOLATION: test/integration/preimport_comment_then_header_test.dart:" \
    "CHECK 4 ignores pre-import comment blocks when the first post-import comment block is the scenario header"
  assert_contains "${staged_output}" "VIOLATION: test/src/features/gamma/presentation/gamma_missing_cross_user_test.dart:" \
    "CHECK 3 violation is attached to mapped staged user-scoped file"
  assert_contains "${staged_output}" "CHECK 3: Registry marks mapped feature 'Gamma Feature' user-scoped data as yes, but '**Cross-user negative test**' is MISSING." \
    "CHECK 3 reads User-scoped and Cross-user values from registry fields"
  assert_contains "${staged_output}" "WARNING: test/src/features/delta/presentation/delta_partial_cross_user_test.dart" \
    "staged scan emits CHECK 3 WARNING for PARTIAL cross-user feature"
  assert_contains "${staged_output}" "PARTIAL" \
    "staged scan CHECK 3 WARNING message includes the word PARTIAL"
  assert_contains "${staged_output}" "scripts/check_audit_registry.sh --strict" \
    "staged scan CHECK 3 PARTIAL warning points to strict audit gate owner for blocking enforcement"
  assert_not_contains "${staged_output}" "VIOLATION: test/src/features/delta/presentation/delta_partial_cross_user_test.dart:" \
    "staged scan does NOT emit VIOLATION for PARTIAL cross-user feature"
  assert_contains "${staged_output}" "INFO: test/src/features/unmapped/presentation/unmapped_mapping_test.dart" \
    "CHECK 3 emits INFO-only output for unmappable staged feature paths"
  assert_contains "${staged_output}" "INFO: test/src/features/ambiguous/presentation/ambiguous_mapping_test.dart" \
    "CHECK 3 emits INFO-only output for ambiguous staged feature paths"
  assert_contains "${staged_output}" "INFO: test/src/routing/routing_contract_test.dart" \
    "CHECK 3 emits INFO-only output for known skip routing paths"
  assert_contains "${staged_output}" "INFO: integration_test/integration_info_skip_test.dart" \
    "CHECK 3 emits INFO-only output for known skip integration paths"
  assert_not_contains "${staged_output}" "INFO: e2e_test/smoke/e2e_info_skip_test.dart" \
    "staged scan does not emit CHECK 3 output for e2e files outside this script's contract"
  assert_not_contains "${staged_output}" "VIOLATION: e2e_test/smoke/e2e_info_skip_test.dart:" \
    "staged scan does not enforce CHECK 1 or CHECK 4 on e2e files"
  assert_contains "${staged_output}" "VIOLATION: test/src/features/alpha/presentation/alpha_missing_scenario_header_test.dart:" \
    "CHECK 4 blocks staged non-wrapper files missing scenario header"
  assert_contains "${staged_output}" "CHECK 4: Missing scenario header block ('## Test Scenarios') for staged test file." \
    "CHECK 4 reports deterministic missing-header message"
  assert_contains "${staged_output}" "VIOLATION: test/src/features/alpha/presentation/alpha_missing_required_tags_test.dart:" \
    "CHECK 4 blocks staged mapped user-scoped files missing required tags"
  assert_contains "${staged_output}" "CHECK 4: Mapped user-scoped staged file is missing required scenario tag [negative]." \
    "CHECK 4 enforces required [negative] tag on mapped user-scoped staged files"
  assert_contains "${staged_output}" "CHECK 4: Mapped user-scoped staged file is missing required scenario tag [isolation]." \
    "CHECK 4 enforces required [isolation] tag on mapped user-scoped staged files"
  assert_not_contains "${staged_output}" "VIOLATION: test/src/features/alpha/presentation/alpha_missing_statemachine_tag_test.dart:" \
    "CHECK 4 does not infer statemachine violations from repeated copied calls in untagged files"
  assert_contains "${staged_output}" "VIOLATION: test/src/features/alpha/presentation/alpha_tagged_statemachine_without_distinct_calls_test.dart:" \
    "CHECK 4 blocks tagged statemachine scenarios that lack three distinct interaction calls"
  assert_contains "${staged_output}" "VIOLATION: test/src/features/alpha/presentation/alpha_statemachine_calls_split_across_tests_test.dart:" \
    "CHECK 4 requires three distinct interaction calls within a single test block, not across the whole file"
  assert_contains "${staged_output}" "CHECK 4: [statemachine] scenario requires at least 3 distinct interaction calls." \
    "CHECK 4 enforces the frozen distinct-call statemachine rule"
  assert_not_contains "${staged_output}" "VIOLATION: test/src/features/alpha/presentation/alpha_double_slash_header_tags_test.dart:" \
    "CHECK 4 accepts double-slash scenario headers with bare tags"
  assert_not_contains "${staged_output}" "VIOLATION: test/src/features/alpha/presentation/alpha_backticked_header_tags_test.dart:" \
    "CHECK 4 accepts triple-slash headers with backticked tags"
  assert_not_contains "${staged_output}" "VIOLATION: test/src/features/beta/presentation/beta_non_user_scoped_header_test.dart:" \
    "CHECK 4 does not require user-scope tags for mapped non-user-scoped features"
  assert_contains "${staged_output}" "VIOLATION: test/src/features/alpha/presentation/alpha_late_scenario_header_test.dart:" \
    "CHECK 4 rejects late scenario header that appears after code"
  assert_contains "${staged_output}" "VIOLATION: test/src/features/alpha/presentation/alpha_scenario_header_after_leading_comment_test.dart:" \
    "CHECK 4 rejects scenario header that appears after an earlier non-scenario comment block"

  rm -rf "${tmpdir}"
}

test_enforcement_contract_partial_owner_split_doc_text() {
  local contract_text
  contract_text="$(cat "${REPO_ROOT}/docs/enforcement_contract.md")"

  assert_contains "${contract_text}" \
    'PARTIAL`: warning-only in both modes. Blocking enforcement for incomplete cross-user proof remains owned by `check_audit_registry.sh --strict` (and `--release` for release gating).' \
    "enforcement contract documents PARTIAL as warning-only with strict/release audit ownership for blocking behavior"
  assert_not_contains "${contract_text}" \
    'PARTIAL`: warning-only in both modes. `PARTIAL` remains an open 3-tier workflow gap.' \
    "enforcement contract no longer states the Stage 3 remediation-signal gap as open"
  assert_not_contains "${contract_text}" \
    'Residual gap: CHECK 3 blocks staged `MISSING`, but `PARTIAL` stays warning-only in `check_test_standards.sh`. Full closure still depends on `check_audit_registry.sh --strict/--release`.' \
    "residual gap list no longer treats PARTIAL warning semantics as an unresolved lane blocker"
}

main() {
  test_enforcement_contract_partial_owner_split_doc_text
  test_stage1_contract

  if [[ "${failures}" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "check_test_standards_stage1_regression_test: PASS"
}

main "$@"
