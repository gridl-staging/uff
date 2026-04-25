#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/lib/workflow_contract_fixtures.sh"
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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "FAIL: ${description} (unexpected '${needle}')"
    failures=$((failures + 1))
  fi
}

run_check_workflow_contracts() {
  local tmpdir="$1"
  shift

  local output=""
  local exit_code=0
  output="$(
    cd "${tmpdir}" &&
    ./scripts/check_workflow_contracts.sh "$@" 2>&1
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

  mkdir -p "${tmpdir}/scripts" "${tmpdir}/scripts/lib" "${tmpdir}/docs" "${tmpdir}/docs/feature_archetypes"

  # TDD red-phase support: allow the harness to run even before the script exists.
  if [[ -f "${REPO_ROOT}/scripts/check_workflow_contracts.sh" ]]; then
    cp "${REPO_ROOT}/scripts/check_workflow_contracts.sh" "${tmpdir}/scripts/"
    chmod +x "${tmpdir}/scripts/check_workflow_contracts.sh"
  fi

  if [[ -f "${REPO_ROOT}/scripts/lib/feature_registry_headings.sh" ]]; then
    cp "${REPO_ROOT}/scripts/lib/feature_registry_headings.sh" "${tmpdir}/scripts/lib/"
  fi

  printf '%s\n' "${tmpdir}"
}

write_registry_with_onboarded_feature() {
  local tmpdir="$1"
  local workflow_lines="${2:-}"
  local feature_name="${3:-Photos}"
  local feature_area="${4:-lib/src/features/photos/}"
  local feature_user_scoped="${5:-yes}"
  local test_files_lines="${6:-  - e2e_test/smoke/photo_flow_test.dart}"
  local cross_user_negative="${7:-YES}"
  local archetypes_raw="${8:-media, user_scoped_data, crud}"

  if [[ -z "${workflow_lines}" ]]; then
    workflow_lines="$(cat <<'EOF'
- [x] `media.select_source` - e2e_test/smoke/photo_flow_test.dart
- [x] `user_scoped_data.metadata_read_rls` - integration_test/activity_photo_rls_smoke_test.dart
- [x] `crud.create` - lib/src/features/photos/data/supabase_photo_repository.dart
EOF
)"
  fi

  {
    cat <<EOF
# Feature Test Audit Registry

## Features

### ${feature_name}

- **Area**: ${feature_area}
- **User-scoped data**: ${feature_user_scoped}
- **Test files**:
EOF
    printf '%s\n' "${test_files_lines}"
    cat <<EOF
- **Cross-user negative test**: ${cross_user_negative}
- **Archetypes**: ${archetypes_raw}
- **Workflow Contract**:
EOF
    printf '%s\n' "${workflow_lines}"
    cat <<'EOF'
- **Known gaps**: none
- **Dev-audit**: 2026-03-29, session: fixture
- **Cross-audit**: 2026-03-29, session: fixture
EOF
  } > "${tmpdir}/docs/feature_test_audit_registry.md"

  local -a archetype_names=()
  local archetype_name=""
  local trimmed_archetype=""
  IFS=',' read -r -a archetype_names <<< "${archetypes_raw}"
  for archetype_name in "${archetype_names[@]}"; do
    trimmed_archetype="$(trim_whitespace "${archetype_name}")"
    if [[ -z "${trimmed_archetype}" ]]; then
      continue
    fi

    case "${trimmed_archetype}" in
      media)
        write_archetype_catalog "${tmpdir}" "media" "media.select_source" "media.upload_lifecycle"
        ;;
      user_scoped_data)
        write_archetype_catalog "${tmpdir}" "user_scoped_data" "user_scoped_data.metadata_read_rls" "user_scoped_data.cross_user_mutation_denied" "user_scoped_data.storage_bucket_rls" "user_scoped_data.binds_mutations_to_session_user"
        ;;
      crud)
        write_archetype_catalog "${tmpdir}" "crud" "crud.create" "crud.read" "crud.update" "crud.delete"
        ;;
      platform_smoke)
        write_archetype_catalog "${tmpdir}" "platform_smoke" "platform_smoke.maestro_smoke_flow"
        ;;
      *)
        write_archetype_catalog "${tmpdir}" "${trimmed_archetype}" "${trimmed_archetype}.fixture_requirement"
        ;;
    esac
  done

  build_workflow_evidence_stubs "${tmpdir}" "${workflow_lines}"
}

write_registry_non_onboarded_feature() {
  local tmpdir="$1"

  cat > "${tmpdir}/docs/feature_test_audit_registry.md" <<'EOF'
# Feature Test Audit Registry

## Features

### Onboarding

- **Area**: lib/src/features/onboarding/
- **User-scoped data**: no
- **Test files**:
  - test/src/features/onboarding/presentation/onboarding_screen_test.dart
- **Cross-user negative test**: N/A
- **Known gaps**: none
- **Dev-audit**: 2026-03-29, session: fixture
- **Cross-audit**: 2026-03-29, session: fixture
EOF
}

test_strict_mode_failure_classes() {
  local tmpdir
  local result

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `media.select_source` - e2e_test/smoke/photo_flow_test.dart
- [x] `unknown.requirement` - test/src/features/photos/unknown_requirement_test.dart
EOF
)"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict fails when workflow requirement is not declared in archetype catalogs"
  assert_contains "${LAST_OUTPUT}" "unknown.requirement" "strict output includes undefined requirement ID"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  cat > "${tmpdir}/docs/feature_test_audit_registry.md" <<'EOF'
# Feature Test Audit Registry

## Features

### Photos

- **Area**: lib/src/features/photos/
- **User-scoped data**: yes
- **Test files**:
  - e2e_test/smoke/photo_flow_test.dart
- **Cross-user negative test**: YES
- **Archetypes**: media, user_scoped_data, crud
- **Known gaps**: none
- **Dev-audit**: 2026-03-29, session: fixture
- **Cross-audit**: 2026-03-29, session: fixture
EOF
  write_archetype_catalog "${tmpdir}" "media" "media.select_source"
  write_archetype_catalog "${tmpdir}" "user_scoped_data" "user_scoped_data.metadata_read_rls"
  write_archetype_catalog "${tmpdir}" "crud" "crud.create"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict fails when archetypes exist without workflow contract block"
  assert_contains "${LAST_OUTPUT}" "missing **Workflow Contract** block" "strict output includes missing workflow block violation"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}"
  rm -f "${tmpdir}/integration_test/activity_photo_rls_smoke_test.dart"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict fails when [x] evidence path is missing on disk"
  assert_contains "${LAST_OUTPUT}" "missing evidence path" "strict output includes missing evidence violation"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `media.select_source` - e2e_test/smoke/photo_flow_test.dart
- [ ] `crud.update` - NOT_IMPLEMENTED
EOF
)"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict fails when NOT_IMPLEMENTED item is present"
  assert_contains "${LAST_OUTPUT}" "NOT_IMPLEMENTED" "strict output includes NOT_IMPLEMENTED violation"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}"
  rm -f "${tmpdir}/docs/feature_archetypes/user_scoped_data.md"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict fails when a declared archetype catalog is missing"
  assert_contains "${LAST_OUTPUT}" "declared archetype catalog is missing" "strict output includes missing catalog violation"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `media.select_source` - e2e_test/smoke/photo_flow_test.dart
- [ ] `crud.update` - lib/src/features/photos/data/supabase_photo_repository.dart
EOF
)"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict fails when unchecked item uses a non-reserved marker"
  assert_contains "${LAST_OUTPUT}" "must use NOT_IMPLEMENTED or DEFERRED:" "strict output includes malformed unchecked marker violation"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  printf '%s\n' "outside fixture evidence" > "$(dirname "${tmpdir}")/workflow-contract-outside-proof.txt"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `media.select_source` - ../workflow-contract-outside-proof.txt
EOF
)"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict fails when checked evidence path escapes the repo root"
  assert_contains "${LAST_OUTPUT}" "not repo-relative" "strict output includes repo-relative evidence violation"
  rm -f "$(dirname "${tmpdir}")/workflow-contract-outside-proof.txt"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  cat > "${tmpdir}/docs/feature_test_audit_registry.md" <<'REGEOF'
# Feature Test Audit Registry

## Features

### Photos

- **Area**: lib/src/features/photos/
- **User-scoped data**: yes
- **Test files**:
  - e2e_test/smoke/photo_flow_test.dart
- **Cross-user negative test**: YES
- **Archetypes**: media
- **Workflow Contract**:
- [x] `media.select_source` - ..
- **Known gaps**: none
- **Dev-audit**: 2026-03-29, session: fixture
- **Cross-audit**: 2026-03-29, session: fixture
REGEOF
  write_archetype_catalog "${tmpdir}" "media" "media.select_source"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict fails when checked evidence path is bare dotdot"
  assert_contains "${LAST_OUTPUT}" "not repo-relative" "strict output rejects bare dotdot evidence path"
  rm -rf "${tmpdir}"
}

test_strict_mode_maestro_test_file_contract_gap() {
  local tmpdir
  local result

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `user_scoped_data.metadata_read_rls` - integration_test/profile_rls_smoke_test.dart
EOF
)" "Notifications" "lib/src/features/notifications/" "yes" "$(cat <<'EOF'
  - .maestro/smoke/notification_smoke.yaml
EOF
)" "PARTIAL" "user_scoped_data"
  mkdir -p "${tmpdir}/.maestro/smoke"
  printf '%s\n' "fixture maestro smoke flow" > "${tmpdir}/.maestro/smoke/notification_smoke.yaml"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict fails when Notifications keeps .maestro smoke proof only under **Test files**"
  assert_contains "${LAST_OUTPUT}" "Notifications" "strict output names Notifications for missing .maestro contract gap"
  assert_contains "${LAST_OUTPUT}" ".maestro/smoke/notification_smoke.yaml" "strict output names missing .maestro contract gap evidence path"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `user_scoped_data.metadata_read_rls` - integration_test/profile_rls_smoke_test.dart
- [x] `platform_smoke.maestro_smoke_flow` - .maestro/smoke/notification_smoke.yaml
EOF
)" "Notifications" "lib/src/features/notifications/" "yes" "$(cat <<'EOF'
  - .maestro/smoke/notification_smoke.yaml
EOF
)" "PARTIAL" "user_scoped_data, platform_smoke"
  mkdir -p "${tmpdir}/.maestro/smoke"
  printf '%s\n' "fixture maestro smoke flow" > "${tmpdir}/.maestro/smoke/notification_smoke.yaml"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "strict passes when Notifications declares matching checked .maestro workflow requirement"
  assert_not_contains "${LAST_OUTPUT}" ".maestro/smoke/notification_smoke.yaml" "strict success output omits .maestro contract-gap violations"
  rm -rf "${tmpdir}"
}

test_release_and_report_modes() {
  local tmpdir
  local result

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `media.select_source` - e2e_test/smoke/photo_flow_test.dart
- [ ] `user_scoped_data.storage_bucket_rls` - DEFERRED: awaiting storage policy test
EOF
  )"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "strict ignores DEFERRED markers"

  result="$(run_check_workflow_contracts "${tmpdir}" --release)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "release fails on DEFERRED markers"
  assert_contains "${LAST_OUTPUT}" "DEFERRED" "release output includes DEFERRED violation"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `unknown.requirement` - test/src/features/photos/unknown_requirement_test.dart
EOF
  )"
  result="$(run_check_workflow_contracts "${tmpdir}" --release)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "release enforces strict-class violations"
  assert_contains "${LAST_OUTPUT}" "unknown.requirement" "release output includes strict-class unknown ID violation"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `unknown.requirement` - test/src/features/photos/unknown_requirement_test.dart
EOF
  )"
  result="$(run_check_workflow_contracts "${tmpdir}" --report)"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "report mode exits zero despite violations"
  assert_contains "${LAST_OUTPUT}" "WARNING" "report mode includes advisory warning text"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `user_scoped_data.storage_bucket_rls` - N/A: feature has no storage bucket
EOF
  )"
  result="$(run_check_workflow_contracts "${tmpdir}" --report)"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "report accepts checked N/A workflow evidence"
  assert_not_contains "${LAST_OUTPUT}" "not repo-relative" "report checked N/A bypasses repo-relative path check"
  assert_not_contains "${LAST_OUTPUT}" "missing evidence path" "report checked N/A bypasses missing path check"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "strict accepts checked N/A workflow evidence"
  assert_not_contains "${LAST_OUTPUT}" "not repo-relative" "strict checked N/A bypasses repo-relative path check"
  assert_not_contains "${LAST_OUTPUT}" "missing evidence path" "strict checked N/A bypasses missing path check"
  result="$(run_check_workflow_contracts "${tmpdir}" --release)"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "release accepts checked N/A workflow evidence"
  assert_not_contains "${LAST_OUTPUT}" "not repo-relative" "release checked N/A bypasses repo-relative path check"
  assert_not_contains "${LAST_OUTPUT}" "missing evidence path" "release checked N/A bypasses missing path check"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `user_scoped_data.storage_bucket_rls` -   N/A: feature has no storage bucket
EOF
  )"
  if [[ -e "${tmpdir}/  N/A: feature has no storage bucket" ]]; then
    echo "FAIL: checked N/A fixture trim parity does not create a whitespace-padded fake evidence path"
    failures=$((failures + 1))
  fi
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "strict accepts checked N/A workflow evidence with padded leading whitespace"
  assert_not_contains "${LAST_OUTPUT}" "missing evidence path" "strict padded checked N/A does not depend on a fake evidence stub"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [ ] `user_scoped_data.storage_bucket_rls` - N/A: feature has no storage bucket
EOF
  )"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict rejects unchecked N/A workflow evidence"
  assert_contains "${LAST_OUTPUT}" "must use NOT_IMPLEMENTED or DEFERRED:" "strict unchecked N/A keeps existing malformed unchecked marker message"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `user_scoped_data.storage_bucket_rls` - N/A:   
EOF
  )"
  result="$(run_check_workflow_contracts "${tmpdir}" --report)"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "report keeps malformed checked N/A advisory"
  assert_contains "${LAST_OUTPUT}" "malformed checked N/A evidence" "report surfaces malformed checked N/A message"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "strict rejects checked N/A without a reason"
  assert_contains "${LAST_OUTPUT}" "malformed checked N/A evidence" "strict reports malformed checked N/A message"
  result="$(run_check_workflow_contracts "${tmpdir}" --release)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "release rejects checked N/A without a reason"
  assert_contains "${LAST_OUTPUT}" "malformed checked N/A evidence" "release reports malformed checked N/A message"
  rm -rf "${tmpdir}"
}

test_non_onboarded_and_valid_onboarded() {
  local tmpdir
  local result
  local strict_exit
  local release_exit
  local report_exit
  local output

  tmpdir="$(setup_fixture)"
  write_registry_non_onboarded_feature "${tmpdir}"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  strict_exit="${LAST_EXIT_CODE}"
  result="$(run_check_workflow_contracts "${tmpdir}" --release)"
  capture_run_result "${result}"
  release_exit="${LAST_EXIT_CODE}"
  assert_eq "0" "${strict_exit}" "strict ignores non-onboarded features"
  assert_eq "0" "${release_exit}" "release ignores non-onboarded features"
  rm -rf "${tmpdir}"

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}"
  result="$(run_check_workflow_contracts "${tmpdir}" --report)"
  capture_run_result "${result}"
  report_exit="${LAST_EXIT_CODE}"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  strict_exit="${LAST_EXIT_CODE}"
  result="$(run_check_workflow_contracts "${tmpdir}" --release)"
  capture_run_result "${result}"
  release_exit="${LAST_EXIT_CODE}"
  output="${LAST_OUTPUT}"
  assert_eq "0" "${report_exit}" "valid onboarded feature passes report mode"
  assert_eq "0" "${strict_exit}" "valid onboarded feature passes strict mode"
  assert_eq "0" "${release_exit}" "valid onboarded feature passes release mode"
  assert_not_contains "${output}" "VIOLATION" "valid onboarded feature does not print violations"
  rm -rf "${tmpdir}"
}

test_repo_notifications_maestro_contract_is_onboarded() {
  local output=""
  local exit_code=0

  output="$(
    cd "${REPO_ROOT}" &&
    bash ./scripts/check_workflow_contracts.sh --strict 2>&1
  )" || exit_code=$?

  LAST_EXIT_CODE="${exit_code}"
  LAST_OUTPUT="${output}"
  assert_eq "0" "${LAST_EXIT_CODE}" "strict passes in-repo Notifications onboarding when .maestro evidence has a matching checked workflow-contract item"
  assert_not_contains "${LAST_OUTPUT}" "Notifications: .maestro test file '.maestro/smoke/notification_smoke.yaml'" "strict output omits Notifications .maestro contract-gap violation when onboarding is complete"
}

test_repo_workflow_contract_script_is_executable() {
  if [[ ! -x "${REPO_ROOT}/scripts/check_workflow_contracts.sh" ]]; then
    echo "FAIL: scripts/check_workflow_contracts.sh must be executable for documented ./scripts/check_workflow_contracts.sh usage"
    failures=$((failures + 1))
  fi
}

test_repo_workflow_contract_script_exec_mode_is_staged() {
  local script_mode=""
  script_mode="$(
    cd "${REPO_ROOT}" &&
    git ls-files --stage scripts/check_workflow_contracts.sh | awk '{print $1}'
  )"

  if [[ "${script_mode}" != "100755" ]]; then
    echo "FAIL: scripts/check_workflow_contracts.sh must be staged as mode 100755 (got '${script_mode:-<missing>}')"
    failures=$((failures + 1))
  fi
}

test_argument_and_registry_errors() {
  local tmpdir
  local result

  tmpdir="$(setup_fixture)"
  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `unknown.requirement` - test/src/features/photos/unknown_requirement_test.dart
EOF
)"

  result="$(run_check_workflow_contracts "${tmpdir}" --wat)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "unknown argument exits 1"
  assert_contains "${LAST_OUTPUT}" "Unknown argument" "unknown argument message is shown"

  rm -f "${tmpdir}/docs/feature_test_audit_registry.md"
  result="$(run_check_workflow_contracts "${tmpdir}" --strict)"
  capture_run_result "${result}"
  assert_eq "1" "${LAST_EXIT_CODE}" "missing registry file exits 1"
  assert_contains "${LAST_OUTPUT}" "not found" "missing registry error mentions missing file"

  write_registry_with_onboarded_feature "${tmpdir}" "$(cat <<'EOF'
- [x] `unknown.requirement` - test/src/features/photos/unknown_requirement_test.dart
EOF
)"
  result="$(run_check_workflow_contracts "${tmpdir}")"
  capture_run_result "${result}"
  assert_eq "0" "${LAST_EXIT_CODE}" "no-flag invocation defaults to report mode"
  assert_contains "${LAST_OUTPUT}" "WARNING" "no-flag invocation keeps advisory output"

  rm -rf "${tmpdir}"
}

main() {
  test_repo_workflow_contract_script_is_executable
  test_repo_workflow_contract_script_exec_mode_is_staged
  test_strict_mode_failure_classes
  test_strict_mode_maestro_test_file_contract_gap
  test_release_and_report_modes
  test_non_onboarded_and_valid_onboarded
  test_repo_notifications_maestro_contract_is_onboarded
  test_argument_and_registry_errors

  if [[ "${failures}" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "check_workflow_contracts_test: PASS"
}

main "$@"
