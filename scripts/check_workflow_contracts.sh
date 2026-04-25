#!/usr/bin/env bash
# Workflow Contract Validation
#
# Parses docs/feature_test_audit_registry.md and validates workflow-contract items
# against declared archetype catalogs under docs/feature_archetypes/.
#
# Modes:
#   (default / --report): advisory only, always exits 0
#   --strict: exit 1 for missing IDs, missing workflow contract block, missing
#             evidence paths, or NOT_IMPLEMENTED markers
#   --release: strict + exit 1 when DEFERRED markers are present

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REGISTRY="$PROJECT_ROOT/docs/feature_test_audit_registry.md"
ARCHETYPE_DIR="$PROJECT_ROOT/docs/feature_archetypes"
# shellcheck source=lib/feature_registry_headings.sh
source "$SCRIPT_DIR/lib/feature_registry_headings.sh"

STRICT=false
RELEASE=false

for arg in "$@"; do
  case "$arg" in
    --report)
      STRICT=false
      RELEASE=false
      ;;
    --strict)
      STRICT=true
      RELEASE=false
      ;;
    --release)
      STRICT=true
      RELEASE=true
      ;;
    *)
      echo "Unknown argument: $arg"
      exit 1
      ;;
  esac
done

if [ ! -f "$REGISTRY" ]; then
  echo "ERROR: Workflow contract registry not found at $REGISTRY"
  exit 1
fi

# Color output if terminal supports it.
if [ -t 1 ]; then
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  GREEN='\033[0;32m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED='' YELLOW='' GREEN='' BOLD='' NC=''
fi

trim_whitespace() {
  local raw="$1"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  printf '%s' "$raw"
}

checked_na_reason() {
  local trimmed_evidence="$1"

  if [[ "$trimmed_evidence" != N/A:* ]]; then
    return 1
  fi

  trim_whitespace "${trimmed_evidence#N/A:}"
}

checked_evidence_path_is_repo_relative() {
  local evidence="$1"
  [[ -n "$evidence" ]] || return 1
  [[ "$evidence" == /* ]] && return 1
  [[ "$evidence" == ".." ]] && return 1
  [[ "$evidence" == ../* ]] && return 1
  [[ "$evidence" == *"/../"* ]] && return 1
  [[ "$evidence" == */.. ]] && return 1
  return 0
}

emit_issue() {
  local message="$1"
  if [ "$STRICT" = true ] || [ "$RELEASE" = true ]; then
    echo -e "${RED}VIOLATION${NC}: ${message}"
  else
    echo -e "${YELLOW}WARNING${NC}: ${message}"
  fi
}

# TODO: Document load_archetype_requirement_ids.
load_archetype_requirement_ids() {
  local archetype="$1"

  local catalog_path="$ARCHETYPE_DIR/${archetype}.md"
  if [ ! -f "$catalog_path" ]; then
    printf '%s\n' "__MISSING_CATALOG__"
    return
  fi

  local line=""
  local first_col=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^\|[[:space:]]*([^|]+)[[:space:]]*\| ]]; then
      first_col="$(trim_whitespace "${BASH_REMATCH[1]}")"
      if [[ "$first_col" == "ID" ]] || [[ "$first_col" == "---" ]] || [[ "$first_col" == "" ]]; then
        continue
      fi
      printf '%s\n' "$first_col"
    fi
  done < "$catalog_path"
}

TOTAL_FEATURES=0
ONBOARDED_FEATURES=0
NON_ONBOARDED_FEATURES=0
STRICT_FAIL_COUNT=0
DEFERRED_FAIL_COUNT=0
ISSUE_COUNT=0

CURRENT_FEATURE=""
CURRENT_ARCHETYPES_RAW=""
CURRENT_HAS_WORKFLOW_HEADER=false
CURRENT_IN_WORKFLOW_BLOCK=false
CURRENT_IN_TEST_FILES_BLOCK=false
CURRENT_FEATURE_ALLOWED_IDS=""

declare -a CURRENT_WORKFLOW_IDS
declare -a CURRENT_WORKFLOW_STATUS
declare -a CURRENT_WORKFLOW_EVIDENCE
declare -a CURRENT_MAESTRO_TEST_FILES

reset_current_feature_state() {
  CURRENT_ARCHETYPES_RAW=""
  CURRENT_HAS_WORKFLOW_HEADER=false
  CURRENT_IN_WORKFLOW_BLOCK=false
  CURRENT_IN_TEST_FILES_BLOCK=false
  CURRENT_WORKFLOW_IDS=()
  CURRENT_WORKFLOW_STATUS=()
  CURRENT_WORKFLOW_EVIDENCE=()
  CURRENT_MAESTRO_TEST_FILES=()
}

record_strict_failure() {
  local message="$1"
  emit_issue "$message"
  STRICT_FAIL_COUNT=$((STRICT_FAIL_COUNT + 1))
  ISSUE_COUNT=$((ISSUE_COUNT + 1))
}

record_deferred_issue() {
  local message="$1"
  if [ "$RELEASE" = true ]; then
    emit_issue "$message"
  else
    echo -e "${YELLOW}WARNING${NC}: ${message}"
  fi
  DEFERRED_FAIL_COUNT=$((DEFERRED_FAIL_COUNT + 1))
  ISSUE_COUNT=$((ISSUE_COUNT + 1))
}

# TODO: Document load_current_feature_allowed_ids.
load_current_feature_allowed_ids() {
  local archetype_token=""
  local archetype_name=""
  local catalog_ids=""
  local catalog_id=""
  local archetype_tokens=()

  CURRENT_FEATURE_ALLOWED_IDS=""
  IFS=',' read -r -a archetype_tokens <<< "$CURRENT_ARCHETYPES_RAW"
  for archetype_token in "${archetype_tokens[@]}"; do
    archetype_name="$(trim_whitespace "$archetype_token")"
    if [[ -z "$archetype_name" ]]; then
      continue
    fi

    catalog_ids="$(load_archetype_requirement_ids "$archetype_name")"
    if [[ "$catalog_ids" == "__MISSING_CATALOG__" ]]; then
      record_strict_failure "${CURRENT_FEATURE}: declared archetype catalog is missing: docs/feature_archetypes/${archetype_name}.md"
      continue
    fi

    while IFS= read -r catalog_id; do
      if [[ -n "$catalog_id" ]]; then
        CURRENT_FEATURE_ALLOWED_IDS="${CURRENT_FEATURE_ALLOWED_IDS}"$'\n'"${catalog_id}"
      fi
    done <<< "$catalog_ids"
  done
}

# TODO: Document validate_checked_workflow_item.
validate_checked_workflow_item() {
  local requirement_id="$1"
  local evidence="$2"
  local trimmed_evidence=""
  local na_reason=""
  local full_evidence_path=""

  trimmed_evidence="$(trim_whitespace "$evidence")"
  if [[ "$trimmed_evidence" == N/A:* ]]; then
    na_reason="$(checked_na_reason "$trimmed_evidence")"
    if [[ -n "$na_reason" ]]; then
      return
    fi
    record_strict_failure "${CURRENT_FEATURE}: malformed checked N/A evidence for '${requirement_id}': ${evidence}"
    return
  fi

  if ! checked_evidence_path_is_repo_relative "$trimmed_evidence"; then
    record_strict_failure "${CURRENT_FEATURE}: evidence path for '${requirement_id}' is not repo-relative: ${trimmed_evidence}"
    return
  fi

  full_evidence_path="$PROJECT_ROOT/$trimmed_evidence"
  if [ ! -e "$full_evidence_path" ]; then
    record_strict_failure "${CURRENT_FEATURE}: missing evidence path for '${requirement_id}': ${trimmed_evidence}"
  fi
}

validate_unchecked_workflow_item() {
  local requirement_id="$1"
  local evidence="$2"

  # Unchecked items use reserved markers to indicate implementation state.
  if [[ "$evidence" == "NOT_IMPLEMENTED" ]]; then
    record_strict_failure "${CURRENT_FEATURE}: '${requirement_id}' is marked NOT_IMPLEMENTED."
  elif [[ "$evidence" == DEFERRED:* ]]; then
    record_deferred_issue "${CURRENT_FEATURE}: '${requirement_id}' is marked ${evidence}"
  else
    record_strict_failure "${CURRENT_FEATURE}: unchecked workflow item '${requirement_id}' must use NOT_IMPLEMENTED or DEFERRED:, found '${evidence}'."
  fi
}

# TODO: Document extract_test_file_path_entry.
extract_test_file_path_entry() {
  local list_line="$1"
  local raw_entry=""
  local path_entry=""

  if [[ "$list_line" =~ ^-[[:space:]]+(.+)$ ]]; then
    raw_entry="$(trim_whitespace "${BASH_REMATCH[1]}")"
  else
    return 1
  fi

  if [[ "$raw_entry" =~ ^\`([^\`]+)\` ]]; then
    path_entry="${BASH_REMATCH[1]}"
  elif [[ "$raw_entry" =~ ^([^[:space:]]+) ]]; then
    path_entry="${BASH_REMATCH[1]}"
  else
    return 1
  fi

  printf '%s' "$(trim_whitespace "$path_entry")"
}

# TODO: Document workflow_has_checked_evidence_path.
workflow_has_checked_evidence_path() {
  local target_path="$1"
  local workflow_index=0
  local workflow_status=""
  local workflow_evidence=""

  for ((workflow_index=0; workflow_index<${#CURRENT_WORKFLOW_IDS[@]}; workflow_index++)); do
    workflow_status="${CURRENT_WORKFLOW_STATUS[$workflow_index]}"
    workflow_evidence="$(trim_whitespace "${CURRENT_WORKFLOW_EVIDENCE[$workflow_index]}")"
    if [[ "$workflow_status" == "x" ]] && [[ "$workflow_evidence" == "$target_path" ]]; then
      return 0
    fi
  done

  return 1
}

# TODO: Document evaluate_workflow_item.
evaluate_workflow_item() {
  local requirement_id="$1"
  local status="$2"
  local evidence="$3"
  local feature_allowed_ids="$4"

  if ! printf '%s\n' "${feature_allowed_ids}" | grep -Fxq "${requirement_id}"; then
    record_strict_failure "${CURRENT_FEATURE}: requirement ID '${requirement_id}' is not defined by declared archetype catalogs."
  fi

  if [[ "$status" == "x" ]]; then
    validate_checked_workflow_item "$requirement_id" "$evidence"
  else
    validate_unchecked_workflow_item "$requirement_id" "$evidence"
  fi
}

# TODO: Document evaluate_current_feature.
evaluate_current_feature() {
  if [[ -z "$CURRENT_FEATURE" ]]; then
    return
  fi

  TOTAL_FEATURES=$((TOTAL_FEATURES + 1))

  if [[ -z "$CURRENT_ARCHETYPES_RAW" ]]; then
    NON_ONBOARDED_FEATURES=$((NON_ONBOARDED_FEATURES + 1))
    echo -e "${YELLOW}WARNING${NC}: ${CURRENT_FEATURE}: feature is not onboarded (missing **Archetypes** line). Advisory only."
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    return
  fi

  ONBOARDED_FEATURES=$((ONBOARDED_FEATURES + 1))

  if [ "$CURRENT_HAS_WORKFLOW_HEADER" = false ] || [ "${#CURRENT_WORKFLOW_IDS[@]}" -eq 0 ]; then
    record_strict_failure "${CURRENT_FEATURE}: missing **Workflow Contract** block for onboarded feature."
    return
  fi

  local index=0
  local requirement_id=""
  local status=""
  local evidence=""
  local maestro_test_file=""

  # Build allowed IDs as a newline-separated set for Bash 3 compatibility.
  load_current_feature_allowed_ids
  for ((index=0; index<${#CURRENT_WORKFLOW_IDS[@]}; index++)); do
    requirement_id="${CURRENT_WORKFLOW_IDS[$index]}"
    status="${CURRENT_WORKFLOW_STATUS[$index]}"
    evidence="${CURRENT_WORKFLOW_EVIDENCE[$index]}"
    evaluate_workflow_item "$requirement_id" "$status" "$evidence" "$CURRENT_FEATURE_ALLOWED_IDS"
  done

  if [ "${#CURRENT_MAESTRO_TEST_FILES[@]}" -gt 0 ]; then
    for maestro_test_file in "${CURRENT_MAESTRO_TEST_FILES[@]}"; do
      if ! workflow_has_checked_evidence_path "$maestro_test_file"; then
        record_strict_failure "${CURRENT_FEATURE}: .maestro test file '${maestro_test_file}' in **Test files** is missing a matching checked workflow-contract item with the same evidence path."
      fi
    done
  fi
}

reset_current_feature_state

while IFS= read -r line; do
  # Stop feature parsing once the audit log starts.
  if [[ "$line" =~ ^##[[:space:]]Audit[[:space:]]Log ]]; then
    evaluate_current_feature
    CURRENT_FEATURE=""
    break
  fi

  # Detect feature headings.
  if [[ "$line" =~ ^###[[:space:]]+(.*) ]]; then
    heading_name="${BASH_REMATCH[1]}"
    if is_registry_non_feature_heading "$heading_name"; then
      continue
    fi

    evaluate_current_feature
    CURRENT_FEATURE="$heading_name"
    reset_current_feature_state
    continue
  fi

  if [[ -z "$CURRENT_FEATURE" ]]; then
    continue
  fi

  # Parse contiguous test-file list rows after the Test files header.
  if [ "$CURRENT_IN_TEST_FILES_BLOCK" = true ]; then
    if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+.+$ ]]; then
      test_file_entry="$(extract_test_file_path_entry "$(trim_whitespace "$line")" || true)"
      if [[ -n "$test_file_entry" ]] && [[ "$test_file_entry" == .maestro/* ]]; then
        validate_checked_workflow_item "test_files.maestro_entry" "$test_file_entry"
        CURRENT_MAESTRO_TEST_FILES+=("$test_file_entry")
      fi
      continue
    fi
    CURRENT_IN_TEST_FILES_BLOCK=false
  fi

  # Parse contiguous checklist rows after workflow header.
  if [ "$CURRENT_IN_WORKFLOW_BLOCK" = true ]; then
    if [[ "$line" =~ ^-[[:space:]]\[(x|[[:space:]])\][[:space:]]\`([^\`]+)\`[[:space:]]-[[:space:]](.+)$ ]]; then
      CURRENT_WORKFLOW_STATUS+=("$(trim_whitespace "${BASH_REMATCH[1]}")")
      CURRENT_WORKFLOW_IDS+=("$(trim_whitespace "${BASH_REMATCH[2]}")")
      CURRENT_WORKFLOW_EVIDENCE+=("$(trim_whitespace "${BASH_REMATCH[3]}")")
      continue
    fi
    CURRENT_IN_WORKFLOW_BLOCK=false
  fi

  if [[ "$line" =~ ^-[[:space:]]\*\*Archetypes\*\*:[[:space:]]*(.+)$ ]]; then
    CURRENT_ARCHETYPES_RAW="$(trim_whitespace "${BASH_REMATCH[1]}")"
    continue
  fi

  if [[ "$line" =~ ^-[[:space:]]\*\*Test[[:space:]]files\*\*:[[:space:]]*$ ]]; then
    CURRENT_IN_TEST_FILES_BLOCK=true
    continue
  fi

  if [[ "$line" =~ ^-[[:space:]]\*\*Workflow[[:space:]]Contract\*\*:[[:space:]]*$ ]]; then
    CURRENT_HAS_WORKFLOW_HEADER=true
    CURRENT_IN_WORKFLOW_BLOCK=true
    continue
  fi
done < "$REGISTRY"

evaluate_current_feature

echo ""
echo -e "${BOLD}Workflow Contract Scorecard${NC}"
echo "========================================"
echo "  Total features:         $TOTAL_FEATURES"
echo "  Onboarded features:     $ONBOARDED_FEATURES"
echo "  Non-onboarded features: $NON_ONBOARDED_FEATURES"
echo "  Strict failures:        $STRICT_FAIL_COUNT"
echo "  Deferred markers:       $DEFERRED_FAIL_COUNT"
echo "========================================"

EXIT_CODE=0

if [ "$RELEASE" = true ]; then
  if [ "$STRICT_FAIL_COUNT" -gt 0 ] || [ "$DEFERRED_FAIL_COUNT" -gt 0 ]; then
    EXIT_CODE=1
  fi
elif [ "$STRICT" = true ]; then
  if [ "$STRICT_FAIL_COUNT" -gt 0 ]; then
    EXIT_CODE=1
  fi
fi

if [ "$EXIT_CODE" -eq 0 ]; then
  echo -e "${GREEN}Workflow contract check passed.${NC}"
else
  echo -e "${RED}Workflow contract check failed.${NC}"
fi

exit "$EXIT_CODE"
