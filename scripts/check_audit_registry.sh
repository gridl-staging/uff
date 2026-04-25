#!/usr/bin/env bash
# Audit Registry Validation
#
# Parses docs/feature_test_audit_registry.md and validates:
# - Listed test files actually exist on disk
# - Counts audit status per feature (Unaudited / Dev-audited / Cross-audited)
# - Counts incomplete cross-user negative tests (MISSING / PARTIAL)
# - Outputs a scorecard
#
# Modes:
#   (default)  Report only. Always exits 0.
#   --strict   Exit non-zero if any user-scoped feature has incomplete
#              cross-user tests (MISSING / PARTIAL).
#   --release  Exit non-zero if any feature is Unaudited or any user-scoped
#              feature has incomplete cross-user tests. (Release gate.)
#
# See docs/mobile_frontend_testing_standards.md and docs/feature_test_audit_registry.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REGISTRY="$PROJECT_ROOT/docs/feature_test_audit_registry.md"
# shellcheck source=lib/feature_registry_headings.sh
source "$SCRIPT_DIR/lib/feature_registry_headings.sh"

STRICT=false
RELEASE=false

for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=true ;;
    --release) RELEASE=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

if [ ! -f "$REGISTRY" ]; then
  echo "ERROR: Audit registry not found at $REGISTRY"
  exit 1
fi

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

join_feature_names() {
  local joined=""
  local feature_name=""

  for feature_name in "$@"; do
    if [ -n "$joined" ]; then
      joined="${joined}, "
    fi
    joined="${joined}${feature_name}"
  done

  printf '%s' "$joined"
}

# --- Parse the registry ---

TOTAL_FEATURES=0
UNAUDITED=0
DEV_AUDITED=0
CROSS_AUDITED=0
USER_SCOPED=0
INCOMPLETE_CROSS_USER=0
MISSING_CROSS_USER=0
PARTIAL_CROSS_USER=0
MISSING_TEST_FILES=0
STALE_TEST_PATHS=0
MISSING_CROSS_USER_FEATURES=()
PARTIAL_CROSS_USER_FEATURES=()

CURRENT_FEATURE=""
CURRENT_USER_SCOPED=false
IN_FEATURES=false

while IFS= read -r line; do
  # Stop feature parsing once the audit log starts.
  if [[ "$line" =~ ^##[[:space:]]Audit[[:space:]]Log ]]; then
    IN_FEATURES=false
    CURRENT_FEATURE=""
    continue
  fi

  # Detect feature headings (### Feature Name)
  if [[ "$line" =~ ^###[[:space:]]+(.*) ]]; then
    FEATURE_NAME="${BASH_REMATCH[1]}"

    # Skip documentation headings that are not real feature entries.
    if is_registry_non_feature_heading "$FEATURE_NAME"; then
      continue
    fi

    CURRENT_FEATURE="$FEATURE_NAME"
    CURRENT_USER_SCOPED=false
    TOTAL_FEATURES=$((TOTAL_FEATURES + 1))
    IN_FEATURES=true
    continue
  fi

  if [ "$IN_FEATURES" = false ]; then continue; fi
  if [ -z "$CURRENT_FEATURE" ]; then continue; fi

  # Check user-scoped data flag
  if [[ "$line" =~ "User-scoped data".*": yes" ]] || [[ "$line" =~ "User-scoped data".*":yes" ]]; then
    CURRENT_USER_SCOPED=true
    USER_SCOPED=$((USER_SCOPED + 1))
  fi

  # Check test file paths exist
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(test/|integration_test/|e2e_test/) ]]; then
    # Strip leading "- ", trailing whitespace, and parenthetical annotations like "(unit + widget)"
    TEST_PATH=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/[[:space:]]*(.*)$//' | sed 's/[[:space:]]*$//')
    FULL_PATH="$PROJECT_ROOT/$TEST_PATH"

    # Handle directory references (ending with /)
    if [[ "$TEST_PATH" == */ ]]; then
      if [ ! -d "$FULL_PATH" ]; then
        echo -e "${RED}STALE PATH${NC}: $CURRENT_FEATURE"
        echo "  Listed: $TEST_PATH"
        echo "  Directory does not exist."
        echo ""
        STALE_TEST_PATHS=$((STALE_TEST_PATHS + 1))
      fi
    else
      # Handle glob patterns (containing *)
      if [[ "$TEST_PATH" == *"*"* ]]; then
        continue  # Skip glob patterns, can't validate easily
      fi
      if [ ! -f "$FULL_PATH" ]; then
        echo -e "${RED}STALE PATH${NC}: $CURRENT_FEATURE"
        echo "  Listed: $TEST_PATH"
        echo "  File does not exist."
        echo ""
        STALE_TEST_PATHS=$((STALE_TEST_PATHS + 1))
      fi
    fi
  fi

  # Check cross-user negative test status
  if [[ "$line" =~ ^-[[:space:]]\*\*Cross-user[[:space:]]negative[[:space:]]test\*\*:[[:space:]]MISSING ]]; then
    if [ "$CURRENT_USER_SCOPED" = true ]; then
      INCOMPLETE_CROSS_USER=$((INCOMPLETE_CROSS_USER + 1))
      MISSING_CROSS_USER=$((MISSING_CROSS_USER + 1))
      MISSING_CROSS_USER_FEATURES+=("$CURRENT_FEATURE")
    fi
  elif [[ "$line" =~ ^-[[:space:]]\*\*Cross-user[[:space:]]negative[[:space:]]test\*\*:[[:space:]]PARTIAL ]]; then
    if [ "$CURRENT_USER_SCOPED" = true ]; then
      INCOMPLETE_CROSS_USER=$((INCOMPLETE_CROSS_USER + 1))
      PARTIAL_CROSS_USER=$((PARTIAL_CROSS_USER + 1))
      PARTIAL_CROSS_USER_FEATURES+=("$CURRENT_FEATURE")
    fi
  fi

  # Check audit status
  if [[ "$line" =~ "Dev-audit".*"Unaudited" ]]; then
    UNAUDITED=$((UNAUDITED + 1))
  elif [[ "$line" =~ "Dev-audit".*(20[0-9][0-9]-) ]]; then
    # Has a date, so it's been audited
    DEV_AUDITED=$((DEV_AUDITED + 1))
  fi

  if [[ "$line" =~ "Cross-audit".*(20[0-9][0-9]-) ]]; then
    CROSS_AUDITED=$((CROSS_AUDITED + 1))
  fi

done < "$REGISTRY"

# ============================================================
# SCORECARD
# ============================================================

echo ""
echo -e "${BOLD}Feature Test Audit Registry Scorecard${NC}"
echo "========================================"
echo ""
echo "  Total features:          $TOTAL_FEATURES"
echo "  User-scoped features:    $USER_SCOPED"
echo ""
echo -e "  ${BOLD}Audit Status${NC}"
echo "  ----------------------------------------"

if [ $UNAUDITED -gt 0 ]; then
  echo -e "  Unaudited:               ${RED}$UNAUDITED${NC}"
else
  echo -e "  Unaudited:               ${GREEN}0${NC}"
fi

echo "  Dev-audited:             $DEV_AUDITED"
echo "  Cross-audited:           $CROSS_AUDITED"
echo ""
echo -e "  ${BOLD}Cross-User Isolation${NC}"
echo "  ----------------------------------------"

if [ $INCOMPLETE_CROSS_USER -gt 0 ]; then
  echo -e "  Incomplete cross-user proof: ${RED}$INCOMPLETE_CROSS_USER${NC} / $USER_SCOPED user-scoped features"
else
  echo -e "  Incomplete cross-user proof: ${GREEN}0${NC} / $USER_SCOPED user-scoped features"
fi

if [ $MISSING_CROSS_USER -gt 0 ]; then
  echo -e "  MISSING statuses:         ${RED}$MISSING_CROSS_USER${NC}"
  # Print exact registry owners so strict/release failures are actionable.
  echo "  MISSING features:        $(join_feature_names "${MISSING_CROSS_USER_FEATURES[@]}")"
else
  echo -e "  MISSING statuses:         ${GREEN}0${NC}"
fi

if [ $PARTIAL_CROSS_USER -gt 0 ]; then
  echo -e "  PARTIAL statuses:         ${RED}$PARTIAL_CROSS_USER${NC}"
  # PARTIAL is still a real blocker at the registry gate, so name the features directly.
  echo "  PARTIAL features:        $(join_feature_names "${PARTIAL_CROSS_USER_FEATURES[@]}")"
else
  echo -e "  PARTIAL statuses:         ${GREEN}0${NC}"
fi

if [ $STALE_TEST_PATHS -gt 0 ]; then
  echo ""
  echo -e "  ${RED}Stale test paths:          $STALE_TEST_PATHS${NC} (listed files/dirs that don't exist)"
fi

echo ""
echo "========================================"

# --- Exit code logic ---

EXIT_CODE=0

if [ "$STRICT" = true ] && [ $INCOMPLETE_CROSS_USER -gt 0 ]; then
  echo -e "${RED}STRICT MODE${NC}: $INCOMPLETE_CROSS_USER user-scoped features have incomplete cross-user proof (MISSING/PARTIAL)."
  EXIT_CODE=1
fi

if [ "$RELEASE" = true ] && [ $UNAUDITED -gt 0 ]; then
  echo -e "${RED}RELEASE MODE${NC}: $UNAUDITED features are Unaudited. All features must be at least Dev-audited for release."
  EXIT_CODE=1
fi

if [ "$RELEASE" = true ] && [ $INCOMPLETE_CROSS_USER -gt 0 ]; then
  echo -e "${RED}RELEASE MODE${NC}: $INCOMPLETE_CROSS_USER user-scoped features have incomplete cross-user proof (MISSING/PARTIAL)."
  EXIT_CODE=1
fi

if [ $STALE_TEST_PATHS -gt 0 ]; then
  echo -e "${YELLOW}WARNING${NC}: $STALE_TEST_PATHS test paths in the registry point to files/directories that don't exist. Update the registry."
  # Stale paths are a warning, not a blocker (files may have been moved)
fi

if [ $EXIT_CODE -eq 0 ]; then
  echo -e "${GREEN}Registry check passed.${NC}"
fi

exit $EXIT_CODE
