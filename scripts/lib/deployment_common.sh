#!/usr/bin/env bash
# Shared deployment/preflight helper functions.

set -euo pipefail

if [[ -x "${HOME}/.deno/bin/deno" && ":${PATH}:" != *":${HOME}/.deno/bin:"* ]]; then export PATH="${HOME}/.deno/bin:${PATH}"; fi

emit_result() {
  local status="$1"
  local message="$2"
  printf '[%s] %s\n' "$status" "$message"
}

# Read env var value from an env file without sourcing shell code.
# This avoids side effects and handles placeholders that are not shell-safe.
read_env_value() {
  local env_file="$1"
  local var_name="$2"
  awk -v key="$var_name" '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line ~ /^#/ || line == "") {
        next
      }
      if (line ~ /^export[[:space:]]+/) {
        sub(/^export[[:space:]]+/, "", line)
      }
      split(line, pieces, "=")
      current_key = pieces[1]
      gsub(/[[:space:]]+$/, "", current_key)
      if (current_key != key) {
        next
      }
      value = substr(line, index(line, "=") + 1)
      sub(/[[:space:]]+#.*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$env_file" 2>/dev/null || true
}

# Read an env value and strip surrounding whitespace.
read_env_value_trimmed() {
  local value
  value="$(read_env_value "$1" "$2")"
  printf '%s' "${value}" | tr -d '[:space:]'
}

# TODO: Document resolve_psql_bin.
resolve_psql_bin() {
  local candidate

  if [[ "${DISABLE_PSQL_AUTO_DISCOVERY:-0}" == "1" ]]; then
    return 1
  fi

  if command -v psql >/dev/null 2>&1; then
    command -v psql
    return 0
  fi

  for candidate in \
    /opt/homebrew/opt/libpq/bin/psql \
    /usr/local/opt/libpq/bin/psql; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

# Remove existing definitions of a key, then append a single replacement value.
upsert_env_key() {
  local env_file="$1"
  local var_name="$2"
  local value="$3"
  local temp_file

  temp_file="$(mktemp)"
  awk -v key="$var_name" '
    {
      line = $0
      stripped = line
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^#/ || stripped == "") {
        print line
        next
      }
      check = stripped
      if (check ~ /^export[[:space:]]+/) {
        sub(/^export[[:space:]]+/, "", check)
      }
      split(check, pieces, "=")
      current_key = pieces[1]
      gsub(/[[:space:]]+$/, "", current_key)
      if (current_key != key) {
        print line
      }
    }
  ' "$env_file" > "$temp_file"
  mv "$temp_file" "$env_file"
  printf '%s=%s\n' "$var_name" "$value" >> "$env_file"
}

# Count how many times a key appears in an env file (ignores comments/blank lines).
count_env_key_occurrences() {
  local env_file="$1"
  local var_name="$2"
  awk -v key="$var_name" '
    BEGIN {
      count = 0
    }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line ~ /^#/ || line == "") {
        next
      }
      if (line ~ /^export[[:space:]]+/) {
        sub(/^export[[:space:]]+/, "", line)
      }
      split(line, pieces, "=")
      current_key = pieces[1]
      gsub(/[[:space:]]+$/, "", current_key)
      if (current_key == key) {
        count += 1
      }
    }
    END {
      print count + 0
    }
  ' "$env_file" 2>/dev/null || printf '0\n'
}

NOTIFICATION_SECRET_KEYS=(
  "FCM_PROJECT_ID"
  "FCM_CLIENT_EMAIL"
  "FCM_PRIVATE_KEY"
  "NOTIFICATION_WEBHOOK_SECRET"
)

is_supported_environment() {
  local environment="$1"
  case "$environment" in
    dev|staging|prod)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_env_file_path() {
  local environment="$1"
  printf '.env.%s\n' "$environment"
}

is_hosted_environment() {
  local environment="$1"
  [[ "$environment" == "staging" || "$environment" == "prod" ]]
}

resolve_supabase_credential_keys() {
  local environment="$1"
  if [[ "$environment" == "dev" ]]; then
    printf 'SUPABASE_LOCAL_URL SUPABASE_LOCAL_ANON_KEY SUPABASE_LOCAL_SERVICE_ROLE_KEY\n'
    return 0
  fi

  if is_hosted_environment "$environment"; then
    printf 'SUPABASE_URL SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY\n'
    return 0
  fi

  return 1
}

# Parse a hosted Supabase URL and return its project ref.
# Returns non-zero when the URL host is not under *.supabase.co.
extract_project_ref_from_url() {
  local supabase_url="$1"
  local host
  host="${supabase_url#https://}"
  host="${host#http://}"
  host="${host%%/*}"

  if [[ "$host" != *.supabase.co ]]; then
    return 1
  fi

  printf '%s\n' "${host%%.supabase.co}"
}

# Resolve SUPABASE_SERVICE_ROLE_KEY from multiple sources with defined precedence:
#   1. SUPABASE_SERVICE_ROLE_KEY env var (if non-empty)
#   2. SUPABASE_SERVICE_ROLE_KEY in the env file
#   3. SUPABASE_uff_service_role_key in the secret source file
#   4. SUPABASE_uff_prod_project__SECRET_KEY in the secret source file
# Returns non-zero if no source provides a value.
resolve_service_role_key() {
  local env_file="$1"
  local secret_source_file="$2"
  local resolved_key

  resolved_key="${SUPABASE_SERVICE_ROLE_KEY:-}"
  if [[ -n "${resolved_key}" ]]; then
    printf '%s\n' "${resolved_key}"
    return 0
  fi

  if [[ -f "${env_file}" ]]; then
    resolved_key="$(read_env_value "${env_file}" "SUPABASE_SERVICE_ROLE_KEY")"
    if [[ -n "${resolved_key}" ]]; then
      printf '%s\n' "${resolved_key}"
      return 0
    fi
  fi

  if [[ -f "${secret_source_file}" ]]; then
    resolved_key="$(read_env_value "${secret_source_file}" "SUPABASE_uff_service_role_key")"
    if [[ -n "${resolved_key}" ]]; then
      printf '%s\n' "${resolved_key}"
      return 0
    fi

    resolved_key="$(read_env_value "${secret_source_file}" "SUPABASE_uff_prod_project__SECRET_KEY")"
    if [[ -n "${resolved_key}" ]]; then
      printf '%s\n' "${resolved_key}"
      return 0
    fi
  fi

  return 1
}

# Copy the gitignored Firebase config files from the primary checkout into the
# current repo root when the current worktree is lean and those files are
# intentionally absent. This keeps release/signoff worktrees reproducible
# without teaching each wrapper a slightly different fallback path.
materialize_shared_firebase_configs_from_primary_checkout() {
  local repo_root="$1"
  local primary_repo_root="${2:-}"
  local git_common_dir_raw=""
  local git_common_dir=""
  local firebase_config=""
  local destination_path=""
  local primary_path=""

  if [[ -z "${primary_repo_root}" ]]; then
    if ! git_common_dir_raw="$(git -C "${repo_root}" rev-parse --git-common-dir 2>/dev/null)"; then
      return 0
    fi
    git_common_dir="$(cd "${repo_root}" && cd "${git_common_dir_raw}" && pwd)"
    primary_repo_root="$(cd "${git_common_dir}/.." && pwd)"
  fi

  for firebase_config in ios/Runner/GoogleService-Info.plist android/app/google-services.json; do
    destination_path="${repo_root}/${firebase_config}"
    primary_path="${primary_repo_root}/${firebase_config}"

    if [[ -f "${destination_path}" || ! -f "${primary_path}" ]]; then
      continue
    fi

    mkdir -p "$(dirname "${destination_path}")"
    cp "${primary_path}" "${destination_path}"
  done
}

# Quote a shell string as a JSON string literal.
json_quote() {
  python3 - "$1" <<'PY'
import json
import sys

print(json.dumps(sys.argv[1]))
PY
}

# Read a whitelisted exported variable from a bootstrap file without sourcing it.
# Expected format per line: export KEY=value
read_bootstrap_export_value() {
  local export_file="$1"
  local var_name="$2"
  python3 - "$export_file" "$var_name" <<'PY'
import pathlib
import shlex
import sys

allowed = {
    "E2E_TEST_EMAIL",
    "E2E_TEST_PASSWORD",
    "SUPABASE_SERVICE_ROLE_KEY",
}

path = pathlib.Path(sys.argv[1])
target = sys.argv[2]
if target not in allowed:
    print(f"Unsupported bootstrap export key: {target}", file=sys.stderr)
    sys.exit(2)

seen = {}

for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
    line = raw_line.strip()
    if not line:
        continue
    try:
        tokens = shlex.split(line, posix=True)
    except ValueError as exc:
        print(f"Invalid bootstrap export at line {line_number}: {exc}", file=sys.stderr)
        sys.exit(1)
    if len(tokens) != 2 or tokens[0] != "export" or "=" not in tokens[1]:
        print(
            f"Invalid bootstrap export at line {line_number}: expected 'export KEY=value'",
            file=sys.stderr,
        )
        sys.exit(1)
    key, value = tokens[1].split("=", 1)
    if key not in allowed:
        print(
            f"Invalid bootstrap export at line {line_number}: unexpected key '{key}'",
            file=sys.stderr,
        )
        sys.exit(1)
    if key in seen:
        print(
            f"Invalid bootstrap export at line {line_number}: duplicate key '{key}'",
            file=sys.stderr,
        )
        sys.exit(1)
    seen[key] = value

if target not in seen:
    sys.exit(3)

print(seen[target], end="")
PY
}

# TODO: Document write_dart_define_file.
write_dart_define_file() {
  local output_file="$1"
  shift
  python3 - "$output_file" "$@" <<'PY'
import json
import pathlib
import sys

args = sys.argv[2:]
if len(args) % 2 != 0:
    raise SystemExit("write_dart_define_file expects KEY VALUE pairs")

payload = {}
for index in range(0, len(args), 2):
    payload[args[index]] = args[index + 1]

path = pathlib.Path(sys.argv[1])
path.write_text(json.dumps(payload), encoding="utf-8")
PY
  chmod 600 "${output_file}"
}

# Write a JSON signoff summary to the given output directory.
# Deliberately takes only safe, explicit parameters to prevent secret leakage.
write_signoff_summary() {
  local output_dir="$1"
  local timestamp="$2"
  local git_sha="$3"
  local env="$4"
  local device="$5"
  local tests_attempted="$6"
  local tests_passed="$7"
  local tests_failed="$8"
  local test_results="$9"
  local patrol_output_dir="${10}"
  local timestamp_json
  local git_sha_json
  local env_json
  local device_json
  local patrol_output_dir_json

  mkdir -p "${output_dir}"
  local json_file="${output_dir}/signoff_${timestamp}_${git_sha}.json"
  timestamp_json="$(json_quote "${timestamp}")"
  git_sha_json="$(json_quote "${git_sha}")"
  env_json="$(json_quote "${env}")"
  device_json="$(json_quote "${device}")"
  patrol_output_dir_json="$(json_quote "${patrol_output_dir}")"

  cat > "${json_file}" <<JSON
{
  "timestamp": ${timestamp_json},
  "git_sha": ${git_sha_json},
  "env": ${env_json},
  "device": ${device_json},
  "tests_attempted": ${tests_attempted},
  "tests_passed": ${tests_passed},
  "tests_failed": ${tests_failed},
  "results": ${test_results},
  "patrol_output_dir": ${patrol_output_dir_json}
}
JSON
}

# --- Client-server contract extraction ---
# Extract RPC and Edge Function names that the Dart client calls.
# Single source of truth for the client-server contract. Used by both
# build_testflight_release.sh (pre-build gate) and validate_deployment.sh
# (post-deploy verification).

# Print RPC function names called from Dart source, one per line.
extract_client_rpc_names() {
  local dart_source_dir="$1"
  # Handles multi-line calls like: .rpc<Type>(\n  'function_name',
  grep -rA1 '\.rpc[<(]' "${dart_source_dir}" --include='*.dart' \
    | grep -oh "'[^']*'" | tr -d "'" | sort -u 2>/dev/null || true
}

# Print Edge Function names called from Dart source, one per line.
extract_client_edge_function_names() {
  local dart_source_dir="$1"
  # Matches both .invoke('name' and _invoke('name' patterns.
  grep -roh "invoke('[^']*'" "${dart_source_dir}" --include='*.dart' \
    | grep -oh "'[^']*'" | tr -d "'" | sort -u 2>/dev/null || true
}

# Verify that every RPC function and Edge Function the client code calls
# actually exists on the hosted Supabase backend. Prevents shipping client code
# against an incompatible backend (the exact bug class from 2026-03-27).
#
# Extracts the contract from Dart source (single source of truth) and probes
# the hosted backend. A 404 means the function is not deployed. Any other
# status (401, 200, etc.) means it exists.
check_hosted_client_contract() {
  local dart_source_dir="$1"
  local supabase_url="$2"
  local anon_key="$3"
  local failures=0

  # Extract function names from Dart source via shared helpers
  # (single source of truth for the grep patterns).
  local rpc_names
  rpc_names="$(extract_client_rpc_names "${dart_source_dir}")" || true

  local edge_names
  edge_names="$(extract_client_edge_function_names "${dart_source_dir}")" || true

  if [ -z "${rpc_names}" ] && [ -z "${edge_names}" ]; then
    printf '%s\n' "  Warning: no RPC or Edge Function calls found in ${dart_source_dir}." >&2
    return 0
  fi

  # Probe each RPC function.
  # We send an empty body ({}) and check the HTTP status. A 404 normally means
  # the function doesn't exist. BUT PostgREST also returns 404 with error code
  # PGRST202 for functions that exist but require parameters — we must treat
  # that case as "exists".
  while IFS= read -r fn_name; do
    [ -z "${fn_name}" ] && continue
    local response_body http_code
    response_body="$(curl -s -w '\n%{http_code}' --max-time 10 \
      -X POST \
      "${supabase_url}/rest/v1/rpc/${fn_name}" \
      -H "apikey: ${anon_key}" \
      -H "Authorization: Bearer ${anon_key}" \
      -H "Content-Type: application/json" \
      -d '{}' 2>/dev/null)" || response_body=$'\n000'
    http_code="${response_body##*$'\n'}"
    response_body="${response_body%$'\n'*}"

    if [ "${http_code}" = "404" ] && printf '%s' "${response_body}" | grep -q 'PGRST202'; then
      # Function exists but requires parameters — this is fine.
      printf '%s\n' "  OK: RPC function '${fn_name}' exists (requires params, PGRST202)."
    elif [ "${http_code}" = "404" ]; then
      printf '%s\n' "  FAIL: RPC function '${fn_name}' not found on hosted backend (HTTP 404)." >&2
      printf '%s\n' "        Deploy the migration that creates this function before building." >&2
      failures=$((failures + 1))
    elif [ "${http_code}" = "000" ]; then
      printf '%s\n' "  FAIL: Could not reach hosted backend at ${supabase_url} (connection failed)." >&2
      failures=$((failures + 1))
    else
      printf '%s\n' "  OK: RPC function '${fn_name}' exists (HTTP ${http_code})."
    fi
  done <<< "${rpc_names}"

  # Probe each Edge Function.
  while IFS= read -r fn_name; do
    [ -z "${fn_name}" ] && continue
    local http_code
    http_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
      -X POST \
      "${supabase_url}/functions/v1/${fn_name}" \
      -H "apikey: ${anon_key}" \
      -H "Authorization: Bearer ${anon_key}" \
      -H "Content-Type: application/json" \
      -d '{}' 2>/dev/null)" || http_code="000"

    if [ "${http_code}" = "404" ]; then
      printf '%s\n' "  FAIL: Edge Function '${fn_name}' not found on hosted backend (HTTP 404)." >&2
      printf '%s\n' "        Deploy this function before building." >&2
      failures=$((failures + 1))
    elif [ "${http_code}" = "000" ]; then
      printf '%s\n' "  FAIL: Could not reach hosted backend at ${supabase_url} (connection failed)." >&2
      failures=$((failures + 1))
    else
      printf '%s\n' "  OK: Edge Function '${fn_name}' exists (HTTP ${http_code})."
    fi
  done <<< "${edge_names}"

  return "${failures}"
}

# --- Shared counters and recording helpers ---
# Used by preflight_check.sh, validate_deployment.sh, and any future scripts
# that tally pass/fail/warn results with emit_result.
pass_count=0
fail_count=0
warn_count=0

record_pass() {
  pass_count=$((pass_count + 1))
  emit_result "PASS" "$1"
}

record_fail() {
  fail_count=$((fail_count + 1))
  emit_result "FAIL" "$1"
}

record_warn() {
  warn_count=$((warn_count + 1))
  emit_result "WARN" "$1"
}

print_summary() {
  echo "Summary: ${pass_count} passed, ${fail_count} failed, ${warn_count} warned."
}
