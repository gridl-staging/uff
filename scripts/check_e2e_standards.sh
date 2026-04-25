#!/usr/bin/env bash
# E2E Test Standards Enforcement
#
# Scans Patrol e2e test files for patterns that bypass human-like interaction.
# Run before merging any e2e test changes. Fails with non-zero exit if violations found.
#
# Allowed in: e2e_test/fixtures.dart (and its part files), e2e_test/auth_setup.dart
# Banned in:  e2e_test/smoke/**_test.dart, e2e_test/full/**_test.dart
#
# See docs/testing_strategy.md for rationale.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
E2E_DIR="$PROJECT_ROOT/e2e_test"

if [ ! -d "$E2E_DIR" ]; then
  echo "No e2e_test/ directory found. Nothing to check."
  exit 0
fi

# Collect all test files (smoke + full), excluding fixtures and setup files
TEST_FILES=$(find "$E2E_DIR/smoke" "$E2E_DIR/full" -name '*_test.dart' 2>/dev/null || true)

if [ -z "$TEST_FILES" ]; then
  echo "No e2e test files found. Nothing to check."
  exit 0
fi

VIOLATIONS=0

# Each banned pattern: regex, human-readable description, fix suggestion
declare -a PATTERNS=(
  'ref\.read\('           'Direct provider state read'           'Verify via UI instead of reading provider state'
  'ref\.watch\('          'Direct provider state watch'          'Verify via UI instead of watching provider state'
  'container\.read\('     'Direct ProviderContainer read'        'Verify via UI instead of reading container'
  'router\.go\('          'Programmatic navigation (go)'         'Tap through UI to navigate'
  'router\.push\('        'Programmatic navigation (push)'       'Tap through UI to navigate'
  'router\.pop\('         'Programmatic navigation (pop)'        'Tap back button through UI'
  'supabase\.from\('      'Direct Supabase table query'          'Move to fixture helpers or verify via UI'
  'supabase\.rpc\('       'Direct Supabase RPC call'             'Move to fixture helpers or verify via UI'
  'supabaseClient'        'Direct Supabase client access'        'Move to fixture helpers'
  '\.insert\('            'Database insert in test body'         'Move to fixture helpers (Arrange phase)'
  '\.update\('            'Database update in test body'         'Move to fixture helpers (Arrange phase)'
  '\.delete\('            'Database delete in test body'         'Move to fixture helpers (Arrange phase)'
  '\.select\('            'Database select in test body'         'Verify via UI instead of querying database'
  'Future\.delayed\('     'Arbitrary wait (Future.delayed)'      'Use Patrol auto-waiting or waitUntilVisible()'
  'sleep\('               'Arbitrary wait (sleep)'               'Use Patrol auto-waiting or waitUntilVisible()'
  'tester\.pump\('        'Raw flutter_test API (pump)'          'Use Patrol $ syntax instead'
  'tester\.pumpAndSettle' 'Raw flutter_test API (pumpAndSettle)' 'Use Patrol $ syntax instead'
  'tester\.tap\('         'Raw flutter_test API (tap)'           'Use $(finder).tap() instead'
  'tester\.enterText\('   'Raw flutter_test API (enterText)'     'Use $(finder).enterText() instead'
  'tester\.drag\('        'Raw flutter_test API (drag)'          'Use $(finder).scrollTo() instead'
  'find\.byType\('        'Fragile type-based finder'            'Use Key or text-based finder instead'
  'find\.byWidget\('      'Direct widget reference'              'Use Key or text-based finder instead'
)

# Check each file against each pattern
for FILE in $TEST_FILES; do
  REL_PATH="${FILE#$PROJECT_ROOT/}"

  i=0
  while [ $i -lt ${#PATTERNS[@]} ]; do
    PATTERN="${PATTERNS[$i]}"
    DESC="${PATTERNS[$((i+1))]}"
    FIX="${PATTERNS[$((i+2))]}"
    i=$((i+3))

    # Search for the pattern, excluding comments (lines starting with //)
    # Use ERE mode so escaped parentheses in patterns (e.g. `\(`) are treated
    # as literal characters instead of incomplete BRE capture groups.
    MATCHES=$(grep -nE "$PATTERN" "$FILE" 2>/dev/null | grep -v '^\s*//' || true)

    if [ -n "$MATCHES" ]; then
      while IFS= read -r LINE; do
        LINE_NUM=$(echo "$LINE" | cut -d: -f1)
        LINE_CONTENT=$(echo "$LINE" | cut -d: -f2- | sed 's/^[[:space:]]*//')
        echo "VIOLATION: $REL_PATH:$LINE_NUM"
        echo "  Pattern: $DESC"
        echo "  Code:    $LINE_CONTENT"
        echo "  Fix:     $FIX"
        echo ""
        VIOLATIONS=$((VIOLATIONS + 1))
      done <<< "$MATCHES"
    fi
  done
done

echo "---"
if [ $VIOLATIONS -eq 0 ]; then
  echo "OK: All e2e test files pass standards check."
  exit 0
else
  echo "FAILED: $VIOLATIONS violation(s) found."
  echo ""
  echo "Shortcuts (API calls, data seeding, provider overrides) belong in:"
  echo "  e2e_test/fixtures.dart (and its part files: fixtures_*_support.dart, fixtures_*.dart)"
  echo "  e2e_test/auth_setup.dart"
  echo ""
  echo "Test files (smoke/, full/) must only contain human-like UI interactions."
  echo "See docs/testing_strategy.md for the full rules."
  exit 1
fi
