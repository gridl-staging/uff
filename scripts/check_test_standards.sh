#!/usr/bin/env bash
# Test Standards Enforcement
#
# Scans test files for patterns that indicate weak or incomplete coverage.
# Companion to check_e2e_standards.sh (which covers e2e_test/ only).
# This script covers test/ and integration_test/.
#
# Modes:
#   (default)  Scan all test files. Fails with non-zero exit if violations found.
#   --staged   Only scan files staged for commit (for pre-commit hook use).
#
# See docs/mobile_frontend_testing_standards.md for rationale.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$PROJECT_ROOT/test"
INTEGRATION_DIR="$PROJECT_ROOT/integration_test"
REGISTRY="$PROJECT_ROOT/docs/feature_test_audit_registry.md"
# shellcheck source=lib/feature_registry_headings.sh
source "$SCRIPT_DIR/lib/feature_registry_headings.sh"

STAGED_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --staged) STAGED_ONLY=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

VIOLATIONS=0
WARNINGS=0

# Stage 1 exemption contract for legitimate non-deterministic assertions.
# Add this token on the expect() line or an immediately adjacent comment line.
WEAK_ASSERTION_EXEMPT_TOKEN='test-standards:allow-weak-assertion'

# Color output if terminal supports it
if [ -t 1 ]; then
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  GREEN='\033[0;32m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED='' YELLOW='' GREEN='' BOLD='' NC=''
fi

record_violation() {
  local file="$1" line_num="$2" desc="$3" fix="$4"
  local rel_path="${file#$PROJECT_ROOT/}"
  echo -e "${RED}VIOLATION${NC}: ${rel_path}:${line_num}"
  echo "  Pattern: $desc"
  echo "  Fix:     $fix"
  echo ""
  VIOLATIONS=$((VIOLATIONS + 1))
}

record_warning() {
  local file="$1" desc="$2"
  local rel_path="${file#$PROJECT_ROOT/}"
  echo -e "${YELLOW}WARNING${NC}: ${rel_path}"
  echo "  $desc"
  echo ""
  WARNINGS=$((WARNINGS + 1))
}

record_info() {
  local path="$1" desc="$2"
  local rel_path="${path#$PROJECT_ROOT/}"
  echo -e "${YELLOW}INFO${NC}: ${rel_path}"
  echo "  $desc"
  echo ""
}

line_contains_exemption_token() {
  local line="$1"
  [[ "$line" == *"$WEAK_ASSERTION_EXEMPT_TOKEN"* ]]
}

is_comment_only_line() {
  local line="$1"
  [[ "$line" =~ ^[[:space:]]*// ]]
}

get_file_line() {
  local file="$1" line_num="$2"
  sed -n "${line_num}p" "$file"
}

# TODO: Document comment_block_has_exemption_token.
comment_block_has_exemption_token() {
  local file="$1" cursor="$2" step="$3"
  local comment_line

  while [ "$cursor" -ge 1 ]; do
    comment_line="$(get_file_line "$file" "$cursor")"
    if [ -z "$comment_line" ] || ! is_comment_only_line "$comment_line"; then
      break
    fi
    if line_contains_exemption_token "$comment_line"; then
      return 0
    fi
    cursor=$((cursor + step))
  done

  return 1
}

is_weak_assertion_exempted() {
  local file="$1" line_num="$2"
  local current_line
  current_line="$(get_file_line "$file" "$line_num")"

  if line_contains_exemption_token "$current_line"; then
    return 0
  fi

  comment_block_has_exemption_token "$file" "$((line_num - 1))" -1 ||
    comment_block_has_exemption_token "$file" "$((line_num + 1))" 1
}

# TODO: Document is_pass_through_wrapper_file.
is_pass_through_wrapper_file() {
  local file="$1"
  local significant_lines line_count import_line main_line import_alias
  significant_lines="$(grep -v '^[[:space:]]*$' "$file" | grep -v '^[[:space:]]*//' || true)"
  line_count="$(printf '%s\n' "$significant_lines" | sed '/^$/d' | wc -l | tr -d ' ')"

  # Wrapper shape:
  #   import '...' as alias;
  #   void main() => alias.main();
  if [ "$line_count" -ne 2 ]; then
    return 1
  fi

  import_line="$(printf '%s\n' "$significant_lines" | sed -n '1p')"
  main_line="$(printf '%s\n' "$significant_lines" | sed -n '2p')"

  if ! echo "$import_line" | grep -Eq "^[[:space:]]*import[[:space:]]+.+[[:space:]]+as[[:space:]]+[A-Za-z_][A-Za-z0-9_]*;[[:space:]]*$"; then
    return 1
  fi

  import_alias="$(echo "$import_line" | sed -E "s/^[[:space:]]*import[[:space:]]+.+[[:space:]]+as[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*;[[:space:]]*$/\\1/")"

  echo "$main_line" | grep -Eq "^[[:space:]]*void[[:space:]]+main\\(\\)[[:space:]]*=>[[:space:]]*${import_alias}\\.main\\(\\);[[:space:]]*$"
}

# TODO: Document collect_multiline_expect_blocks.
collect_multiline_expect_blocks() {
  local file="$1"
  awk '
    function emit_block() {
      if (in_expect == 1 && start_line > 0 && end_line > start_line) {
        normalized = block
        gsub(/[[:space:]]+/, " ", normalized)
        print start_line "\t" end_line "\t" normalized
      }
      in_expect = 0
      start_line = 0
      end_line = 0
      block = ""
    }

    {
      if (in_expect == 0 && $0 ~ /expect[[:space:]]*\(/) {
        in_expect = 1
        start_line = NR
        block = $0
      } else if (in_expect == 1) {
        block = block " " $0
      }

      if (in_expect == 1 && $0 ~ /\);[[:space:]]*$/) {
        end_line = NR
        emit_block()
      }
    }

    END {
      if (in_expect == 1) {
        emit_block()
      }
    }
  ' "$file"
}

weak_assertion_line_pattern() {
  local block_pattern="$1"
  case "$block_pattern" in
    *'isNotNull'*) printf '%s\n' 'isNotNull' ;;
    *'isA<'*) printf '%s\n' 'isA<[^>]*>\(\)' ;;
    *'isNotEmpty'*) printf '%s\n' 'isNotEmpty' ;;
    *'greaterThan(0)'*) printf '%s\n' 'greaterThan\(0\)' ;;
    *) return 1 ;;
  esac
}

# TODO: Document find_multiline_match_line.
find_multiline_match_line() {
  local file="$1" start_line="$2" end_line="$3" block_pattern="$4"
  local line_pattern relative_line
  line_pattern="$(weak_assertion_line_pattern "$block_pattern" || true)"

  if [ -z "$line_pattern" ]; then
    printf '%s\n' "$start_line"
    return 0
  fi

  relative_line="$(
    sed -n "${start_line},${end_line}p" "$file" |
      grep -n -E "$line_pattern" |
      head -1 |
      cut -d: -f1 ||
      true
  )"

  if [ -z "$relative_line" ]; then
    printf '%s\n' "$start_line"
    return 0
  fi

  printf '%s\n' "$((start_line + relative_line - 1))"
}

trim_whitespace() {
  local raw="$1"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  printf '%s' "$raw"
}

REGISTRY_PARSED=false
REGISTRY_MISSING=false
REGISTRY_MISSING_INFO_EMITTED=false
declare -a REGISTRY_FEATURE_NAMES=()
declare -a REGISTRY_FEATURE_AREAS=()
declare -a REGISTRY_FEATURE_USER_SCOPED=()
declare -a REGISTRY_FEATURE_CROSS_USER=()

append_registry_feature_entry() {
  local feature_name="$1"
  local area="$2"
  local user_scoped="$3"
  local cross_user="$4"
  REGISTRY_FEATURE_NAMES+=("$feature_name")
  REGISTRY_FEATURE_AREAS+=("$area")
  REGISTRY_FEATURE_USER_SCOPED+=("$user_scoped")
  REGISTRY_FEATURE_CROSS_USER+=("$cross_user")
}

# TODO: Document parse_feature_registry_entries.
parse_feature_registry_entries() {
  if [ "$REGISTRY_PARSED" = true ]; then
    return
  fi
  REGISTRY_PARSED=true

  if [ ! -f "$REGISTRY" ]; then
    REGISTRY_MISSING=true
    return
  fi

  local line feature_heading=""
  local area_value="" user_scoped_value="" cross_user_value=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]Audit[[:space:]]Log ]]; then
      break
    fi

    if [[ "$line" =~ ^###[[:space:]]+(.*)$ ]]; then
      if [ -n "$feature_heading" ]; then
        append_registry_feature_entry "$feature_heading" "$area_value" "$user_scoped_value" "$cross_user_value"
      fi
      feature_heading="$(trim_whitespace "${BASH_REMATCH[1]}")"
      if is_registry_non_feature_heading "$feature_heading"; then
        feature_heading=""
        area_value=""
        user_scoped_value=""
        cross_user_value=""
        continue
      fi
      area_value=""
      user_scoped_value=""
      cross_user_value=""
      continue
    fi

    if [ -z "$feature_heading" ]; then
      continue
    fi

    if [[ "$line" =~ ^-[[:space:]]\*\*Area\*\*:[[:space:]]*(.*)$ ]]; then
      area_value="$(trim_whitespace "${BASH_REMATCH[1]}")"
      continue
    fi

    if [[ "$line" =~ ^-[[:space:]]\*\*User-scoped[[:space:]]data\*\*:[[:space:]]*(.*)$ ]]; then
      user_scoped_value="$(trim_whitespace "${BASH_REMATCH[1]}")"
      continue
    fi

    if [[ "$line" =~ ^-[[:space:]]\*\*Cross-user[[:space:]]negative[[:space:]]test\*\*:[[:space:]]*(.*)$ ]]; then
      cross_user_value="$(trim_whitespace "${BASH_REMATCH[1]}")"
      continue
    fi
  done < "$REGISTRY"

  if [ -n "$feature_heading" ]; then
    append_registry_feature_entry "$feature_heading" "$area_value" "$user_scoped_value" "$cross_user_value"
  fi
}

MAP_STATUS=""
MAP_FEATURE_INDEX=-1
MAP_FEATURE_SEGMENT=""
MAP_SKIP_CLASS=""

# TODO: Document known_mapping_skip_class.
known_mapping_skip_class() {
  local rel_path="$1"
  if [[ "$rel_path" == integration_test/* ]]; then
    printf '%s\n' "integration_test"
    return 0
  fi
  if [[ "$rel_path" == e2e_test/* ]]; then
    printf '%s\n' "e2e_test"
    return 0
  fi
  if [[ "$rel_path" == test/src/routing/* ]]; then
    printf '%s\n' "test_src_routing"
    return 0
  fi
  if [[ "$rel_path" == test/* ]] && [[ ! "$rel_path" =~ ^test/src/features/[^/]+/ ]]; then
    printf '%s\n' "test_outside_feature_path"
    return 0
  fi

  return 1
}

# TODO: Document map_test_path_to_registry_feature.
map_test_path_to_registry_feature() {
  local rel_path="$1"
  local skip_class="" match_count=0 area_needle=""
  local i

  MAP_STATUS=""
  MAP_FEATURE_INDEX=-1
  MAP_FEATURE_SEGMENT=""
  MAP_SKIP_CLASS=""

  parse_feature_registry_entries
  if [ "$REGISTRY_MISSING" = true ]; then
    MAP_STATUS="registry_missing"
    return
  fi

  skip_class="$(known_mapping_skip_class "$rel_path" || true)"
  if [ -n "$skip_class" ]; then
    MAP_STATUS="known_skip"
    MAP_SKIP_CLASS="$skip_class"
    return
  fi

  if [[ ! "$rel_path" =~ ^test/src/features/([^/]+)/ ]]; then
    MAP_STATUS="known_skip"
    MAP_SKIP_CLASS="outside_contract_path"
    return
  fi

  MAP_FEATURE_SEGMENT="${BASH_REMATCH[1]}"
  area_needle="lib/src/features/${MAP_FEATURE_SEGMENT}/"

  for i in "${!REGISTRY_FEATURE_NAMES[@]}"; do
    if [[ "${REGISTRY_FEATURE_AREAS[$i]}" == *"$area_needle"* ]]; then
      match_count=$((match_count + 1))
      MAP_FEATURE_INDEX="$i"
    fi
  done

  if [ "$match_count" -eq 1 ]; then
    MAP_STATUS="mapped"
    return
  fi

  if [ "$match_count" -eq 0 ]; then
    MAP_STATUS="unmappable"
    return
  fi

  MAP_STATUS="ambiguous"
}

is_registry_user_scoped_yes() {
  local raw="$1"
  local lowered
  lowered="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  [[ "$lowered" == yes* ]]
}

is_registry_cross_user_missing() {
  local raw="$1"
  local lowered
  lowered="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  [[ "$lowered" == missing* ]]
}

# PARTIAL is advisory-only — warns but never blocks commits.
# The blocking gate for PARTIAL is check_audit_registry.sh --strict.
is_registry_cross_user_partial() {
  local raw="$1"
  local lowered
  lowered="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  [[ "$lowered" == partial* ]]
}

# TODO: Document emit_mapping_info.
emit_mapping_info() {
  local path="$1" check_label="$2"
  case "$MAP_STATUS" in
    registry_missing)
      if [ "$REGISTRY_MISSING_INFO_EMITTED" = false ]; then
        echo -e "${YELLOW}INFO${NC}: docs/feature_test_audit_registry.md"
        echo "  ${check_label}: Registry file is missing. Contract mapping checks are skipped."
        echo ""
        REGISTRY_MISSING_INFO_EMITTED=true
      fi
      ;;
    known_skip)
      case "$MAP_SKIP_CLASS" in
        integration_test)
          record_info "$path" "${check_label}: Known INFO-only mapping skip for integration_test/** (CONTRACT:MAPPING-FUNCTION-V1)."
          ;;
        e2e_test)
          record_info "$path" "${check_label}: Known INFO-only mapping skip for e2e_test/** (CONTRACT:MAPPING-FUNCTION-V1)."
          ;;
        test_src_routing)
          record_info "$path" "${check_label}: Known INFO-only mapping skip for test/src/routing/** (CONTRACT:MAPPING-FUNCTION-V1)."
          ;;
        test_outside_feature_path|outside_contract_path)
          record_info "$path" "${check_label}: Known INFO-only mapping skip for test paths outside test/src/features/<feature>/... (CONTRACT:MAPPING-FUNCTION-V1)."
          ;;
      esac
      ;;
    unmappable)
      record_info "$path" "${check_label}: No registry **Area** match for feature segment '${MAP_FEATURE_SEGMENT}'. Skipping enforcement."
      ;;
    ambiguous)
      record_info "$path" "${check_label}: Multiple registry **Area** matches for feature segment '${MAP_FEATURE_SEGMENT}'. Skipping enforcement."
      ;;
  esac
}

# TODO: Document extract_first_scenario_header_block.
extract_first_scenario_header_block() {
  local file="$1"
  awk '
    function is_comment(line) { return line ~ /^[[:space:]]*\/\/\/?/ }
    function is_blank(line) { return line ~ /^[[:space:]]*$/ }
    function is_import(line) { return line ~ /^[[:space:]]*(import|library|part)[[:space:]]/ }

    {
      lines[NR] = $0
      if (is_import($0)) {
        saw_import = 1
        last_import_line = NR
      }
    }

    END {
      start_line = 1
      if (saw_import == 1) {
        start_line = last_import_line + 1
      }

      for (i = start_line; i <= NR; i++) {
        if (is_blank(lines[i])) {
          continue
        }

        if (is_comment(lines[i])) {
          first_block = ""
          has_scenario_marker = 0
          for (j = i; j <= NR; j++) {
            if (!is_comment(lines[j])) {
              break
            }
            first_block = first_block lines[j] ORS
            if (lines[j] ~ /[Tt]est[[:space:]]+[Ss]cenarios/) {
              has_scenario_marker = 1
            }
          }

          if (has_scenario_marker == 1) {
            printf "%s", first_block
            exit 0
          }
          exit 1
        }

        exit 1
      }

      exit 1
    }
  ' "$file"
}

scenario_header_has_tag() {
  local header_block="$1"
  local tag_name="$2"
  printf '%s\n' "$header_block" | grep -Eiq "\`?\\[${tag_name}\\]\`?"
}

# TODO: Document has_statemachine_contract_coverage.
has_statemachine_contract_coverage() {
  local file="$1"
  awk '
    function clear_interactions(    key) {
      for (key in interactions) {
        delete interactions[key]
      }
    }

    function note_interactions(line,    remaining, token) {
      remaining = line
      while (match(remaining, /\.tap\(|\.longPress\(|\.drag\(|\.enterText\(|\.pumpWidget\(|\.pumpAndSettle\(|\.pump\(|didMapViewInputsChange\(|buildUserLocationViewportState\(|waitFor[A-Za-z0-9_]*\(/)) {
        token = substr(remaining, RSTART, RLENGTH)
        interactions[token] = 1
        file_interactions[token] = 1
        remaining = substr(remaining, RSTART + RLENGTH)
      }
    }

    function count_distinct_interactions(    count, key) {
      count = 0
      for (key in interactions) {
        count++
      }
      return count
    }

    function count_file_distinct_interactions(    count, key) {
      count = 0
      for (key in file_interactions) {
        count++
      }
      return count
    }

    function finalize_test_block(    block_distinct_count) {
      block_distinct_count = count_distinct_interactions()
      if (block_distinct_count >= 1) {
        interaction_test_blocks++
      }
      if (block_distinct_count >= 3) {
        matched_contract = 1
        return 1
      }
      return 0
    }

    function brace_delta(line,    open_count, close_count) {
      open_count = gsub(/\{/, "{", line)
      close_count = gsub(/\}/, "}", line)
      return open_count - close_count
    }

    BEGIN {
      in_test_block = 0
      block_depth = 0
      matched_contract = 0
      interaction_test_blocks = 0
      saw_block_body = 0
      clear_interactions()
    }

    {
      if (in_test_block == 0 && $0 ~ /^[[:space:]]*(test|testWidgets|patrolTest)[[:space:]]*\(/) {
        in_test_block = 1
        block_depth = 0
        saw_block_body = 0
        clear_interactions()
      }

      if (in_test_block == 1) {
        note_interactions($0)
        current_brace_delta = brace_delta($0)
        block_depth += current_brace_delta
        if (current_brace_delta > 0 || $0 ~ /=>/) {
          saw_block_body = 1
        }

        if (saw_block_body == 1 && block_depth <= 0) {
          if (finalize_test_block() == 1) {
            exit 0
          }
          in_test_block = 0
          block_depth = 0
          saw_block_body = 0
          clear_interactions()
        }
      }
    }

    END {
      if (matched_contract == 1) {
        exit 0
      }
      if (in_test_block == 1 && finalize_test_block() == 1) {
        exit 0
      }
      if (interaction_test_blocks >= 3 && count_file_distinct_interactions() >= 3) {
        exit 0
      }
      exit 1
    }
  ' "$file"
}

# --- Collect test files ---

if [ "$STAGED_ONLY" = true ]; then
  # Only check the staged paths owned by this script's pre-commit contract.
  ALL_TEST_FILES=$(
    cd "$PROJECT_ROOT" &&
      git diff --cached --name-only --diff-filter=ACM -- \
        'test/*_test.dart' \
        'test/**/*_test.dart' \
        'integration_test/*_test.dart' \
        'integration_test/**/*_test.dart' 2>/dev/null |
      while read -r f; do
        echo "$PROJECT_ROOT/$f"
      done || true
  )
  if [ -z "$ALL_TEST_FILES" ]; then
    echo "No staged test files. Nothing to check."
    exit 0
  fi
else
  UNIT_TEST_FILES=""
  if [ -d "$TEST_DIR" ]; then
    UNIT_TEST_FILES=$(find "$TEST_DIR" -name '*_test.dart' 2>/dev/null || true)
  fi

  INTEGRATION_TEST_FILES=""
  if [ -d "$INTEGRATION_DIR" ]; then
    INTEGRATION_TEST_FILES=$(find "$INTEGRATION_DIR" -name '*_test.dart' 2>/dev/null || true)
  fi

  ALL_TEST_FILES="$UNIT_TEST_FILES"
  if [ -n "$INTEGRATION_TEST_FILES" ]; then
    ALL_TEST_FILES="$ALL_TEST_FILES
$INTEGRATION_TEST_FILES"
  fi
fi

if [ -z "$ALL_TEST_FILES" ]; then
  echo "No test files found. Nothing to check."
  exit 0
fi

CHECK12_FILES="$ALL_TEST_FILES"

# ============================================================
# CHECK 1: Banned weak assertion patterns
# ============================================================
# These patterns give false confidence. They pass for almost any value.

declare -a WEAK_ASSERTIONS=(
  'expect(.*,\s*isNotNull\s*[,;)]'
    'Bare isNotNull assertion'
    'Assert a specific expected value instead of just isNotNull'
  'expect(.*,\s*isA<[^>]*>()\s*[,;)]'
    'Bare isA<Type>() assertion without further matchers'
    'Assert specific properties of the value, not just its type'
  'expect(.*,\s*isNotEmpty\s*[,;)]'
    'Bare isNotEmpty assertion'
    'Assert exact content or length instead of just isNotEmpty'
  'expect(.*,\s*greaterThan(0)\s*[,;)]'
    'Bare greaterThan(0) assertion'
    'Assert the exact expected value instead of just > 0'
)

for FILE in $CHECK12_FILES; do
  MULTILINE_EXPECT_BLOCKS="$(collect_multiline_expect_blocks "$FILE")"
  i=0
  while [ $i -lt ${#WEAK_ASSERTIONS[@]} ]; do
    PATTERN="${WEAK_ASSERTIONS[$i]}"
    DESC="${WEAK_ASSERTIONS[$((i+1))]}"
    FIX="${WEAK_ASSERTIONS[$((i+2))]}"
    i=$((i+3))

    MATCHES=$(grep -n "$PATTERN" "$FILE" 2>/dev/null || true)

    if [ -n "$MATCHES" ]; then
      while IFS= read -r LINE; do
        LINE_NUM=$(echo "$LINE" | cut -d: -f1)
        if is_comment_only_line "$(get_file_line "$FILE" "$LINE_NUM")"; then
          continue
        fi
        if is_weak_assertion_exempted "$FILE" "$LINE_NUM"; then
          continue
        fi
        record_violation "$FILE" "$LINE_NUM" "$DESC" "$FIX"
      done <<< "$MATCHES"
    fi

    if [ -n "$MULTILINE_EXPECT_BLOCKS" ]; then
      while IFS=$'\t' read -r START_LINE END_LINE BLOCK_TEXT; do
        local_match_line=""
        if [ -z "$START_LINE" ]; then
          continue
        fi
        if ! echo "$BLOCK_TEXT" | grep -q "$PATTERN"; then
          continue
        fi
        local_match_line="$(find_multiline_match_line "$FILE" "$START_LINE" "$END_LINE" "$PATTERN")"
        if is_comment_only_line "$(get_file_line "$FILE" "$local_match_line")"; then
          continue
        fi
        if is_weak_assertion_exempted "$FILE" "$START_LINE" || is_weak_assertion_exempted "$FILE" "$local_match_line"; then
          continue
        fi
        record_violation "$FILE" "$local_match_line" "$DESC" "$FIX"
      done <<< "$MULTILINE_EXPECT_BLOCKS"
    fi
  done
done

# ============================================================
# CHECK 2: Test files with zero expect() calls
# ============================================================

for FILE in $CHECK12_FILES; do
  EXPECT_COUNT=$(grep -c 'expect(' "$FILE" 2>/dev/null || true)
  if [ "$EXPECT_COUNT" -eq 0 ] && ! is_pass_through_wrapper_file "$FILE"; then
    record_warning "$FILE" "Test file contains zero expect() calls. Does this test assert anything?"
  fi
done

# ============================================================
# CHECK 3: User-scoped feature tests missing negative/isolation tests
# ============================================================
# Contract mapping is staged-path-driven:
#   test/src/features/<feature>/... -> registry Area match
# Mapping misses or ambiguities are INFO-only skips.
for FILE in $ALL_TEST_FILES; do
  REL_PATH="${FILE#$PROJECT_ROOT/}"
  map_test_path_to_registry_feature "$REL_PATH"

  case "$MAP_STATUS" in
    mapped)
      MAPPED_USER_SCOPED="${REGISTRY_FEATURE_USER_SCOPED[$MAP_FEATURE_INDEX]}"
      MAPPED_CROSS_USER="${REGISTRY_FEATURE_CROSS_USER[$MAP_FEATURE_INDEX]}"
      MAPPED_FEATURE_NAME="${REGISTRY_FEATURE_NAMES[$MAP_FEATURE_INDEX]}"
      if ! is_registry_user_scoped_yes "$MAPPED_USER_SCOPED"; then
        continue
      fi
      if is_registry_cross_user_missing "$MAPPED_CROSS_USER"; then
        CHECK3_DESC="CHECK 3: Registry marks mapped feature '${MAPPED_FEATURE_NAME}' user-scoped data as ${MAPPED_USER_SCOPED}, but '**Cross-user negative test**' is MISSING."
        CHECK3_FIX="Update docs/feature_test_audit_registry.md with real cross-user coverage before staging this file."
        if [ "$STAGED_ONLY" = true ]; then
          record_violation "$FILE" "1" "$CHECK3_DESC" "$CHECK3_FIX"
        else
          record_warning "$FILE" "$CHECK3_DESC"
        fi
      elif is_registry_cross_user_partial "$MAPPED_CROSS_USER"; then
        CHECK3_PARTIAL_DESC="CHECK 3: Registry marks mapped feature '${MAPPED_FEATURE_NAME}' cross-user negative test as PARTIAL. Full human-realistic UI proof is still missing. Blocking audit owner: scripts/check_audit_registry.sh --strict (use --release for release gating)."
        record_warning "$FILE" "$CHECK3_PARTIAL_DESC"
      fi
      ;;
    known_skip|unmappable|ambiguous|registry_missing)
      if [ "$STAGED_ONLY" = true ]; then
        emit_mapping_info "$FILE" "CHECK 3"
      fi
      ;;
  esac
done

# ============================================================
# CHECK 4: Scenario header check
# ============================================================
# Parse the first scenario block and enforce required tags for staged files.
# Non-staged runs remain advisory for legacy drift.
MISSING_HEADERS_ADVISORY=0
STATEMACHINE_CONTRACT_ADVISORY=0
for FILE in $ALL_TEST_FILES; do
  if is_pass_through_wrapper_file "$FILE"; then
    continue
  fi

  REL_PATH="${FILE#$PROJECT_ROOT/}"
  HEADER_BLOCK="$(extract_first_scenario_header_block "$FILE" || true)"

  if [ -z "$HEADER_BLOCK" ]; then
    if [ "$STAGED_ONLY" = true ]; then
      record_violation "$FILE" "1" \
        "CHECK 4: Missing scenario header block ('## Test Scenarios') for staged test file." \
        "Add a first comment block with scenario tags such as [positive], [negative], and [isolation]."
    else
      MISSING_HEADERS_ADVISORY=$((MISSING_HEADERS_ADVISORY + 1))
    fi
    continue
  fi

  if scenario_header_has_tag "$HEADER_BLOCK" "statemachine" && ! has_statemachine_contract_coverage "$FILE"; then
    if [ "$STAGED_ONLY" = true ]; then
      record_violation "$FILE" "1" \
        "CHECK 4: [statemachine] scenario requires at least 3 distinct interaction calls." \
        "Use at least three distinct interaction call types in the tagged flow (repeated identical calls do not count)."
    else
      STATEMACHINE_CONTRACT_ADVISORY=$((STATEMACHINE_CONTRACT_ADVISORY + 1))
    fi
  fi

  map_test_path_to_registry_feature "$REL_PATH"
  case "$MAP_STATUS" in
    mapped)
      MAPPED_USER_SCOPED="${REGISTRY_FEATURE_USER_SCOPED[$MAP_FEATURE_INDEX]}"
      if ! is_registry_user_scoped_yes "$MAPPED_USER_SCOPED"; then
        continue
      fi

      if ! scenario_header_has_tag "$HEADER_BLOCK" "negative"; then
        if [ "$STAGED_ONLY" = true ]; then
          record_violation "$FILE" "1" \
            "CHECK 4: Mapped user-scoped staged file is missing required scenario tag [negative]." \
            "Add [negative] to the first scenario header block."
        else
          record_warning "$FILE" "CHECK 4: User-scoped mapped file is missing [negative] in the first scenario header block."
        fi
      fi

      if ! scenario_header_has_tag "$HEADER_BLOCK" "isolation"; then
        if [ "$STAGED_ONLY" = true ]; then
          record_violation "$FILE" "1" \
            "CHECK 4: Mapped user-scoped staged file is missing required scenario tag [isolation]." \
            "Add [isolation] to the first scenario header block."
        else
          record_warning "$FILE" "CHECK 4: User-scoped mapped file is missing [isolation] in the first scenario header block."
        fi
      fi
      ;;
    known_skip|unmappable|ambiguous|registry_missing)
      if [ "$STAGED_ONLY" = true ]; then
        emit_mapping_info "$FILE" "CHECK 4"
      fi
      ;;
  esac
done

if [ "$STAGED_ONLY" = false ]; then
  if [ "$MISSING_HEADERS_ADVISORY" -gt 0 ]; then
    echo -e "${YELLOW}INFO${NC}: $MISSING_HEADERS_ADVISORY test files are missing a scenario header block."
    echo "  Staged files block on this rule. Full-repo mode is advisory for legacy drift."
    echo ""
  fi

  if [ "$STATEMACHINE_CONTRACT_ADVISORY" -gt 0 ]; then
    echo -e "${YELLOW}INFO${NC}: $STATEMACHINE_CONTRACT_ADVISORY [statemachine]-tagged files have fewer than 3 distinct interaction calls."
    echo "  Staged files block on this rule. Full-repo mode is advisory for legacy drift."
    echo ""
  fi
fi

# ============================================================
# SUMMARY
# ============================================================

echo "---"
echo -e "${BOLD}Test Standards Check Summary${NC}"
echo "  Files scanned: $(echo "$ALL_TEST_FILES" | wc -l | tr -d ' ')"
echo "  Violations:    $VIOLATIONS"
echo "  Warnings:      $WARNINGS"
echo ""

if [ $VIOLATIONS -gt 0 ]; then
  echo -e "${RED}FAILED${NC}: $VIOLATIONS violation(s) found."
  echo "Fix violations before committing. Warnings should be addressed but are not blocking."
  exit 1
else
  echo -e "${GREEN}PASSED${NC}: No violations found."
  if [ $WARNINGS -gt 0 ]; then
    echo "$WARNINGS warning(s) should be addressed when possible."
  fi
  exit 0
fi
