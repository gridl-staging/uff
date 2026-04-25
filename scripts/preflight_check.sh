#!/usr/bin/env bash
# preflight_check.sh — Read-only deployment readiness checks.
#
# Usage:
#   ./scripts/preflight_check.sh <environment>
#   environment: dev | staging | prod
#
# Exit codes:
#   0 => all fail-level checks passed
#   1 => one or more fail-level checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
source "${SCRIPT_DIR}/lib/deployment_common.sh"

print_usage() {
  cat <<EOF
Usage: ./scripts/${SCRIPT_NAME} <environment>
  environment: dev | staging | prod
EOF
}

env_file_creation_hint() {
  local env_file_path="$1"
  printf 'Create it with: cp .env.example %s, then set the required keys.' "$env_file_path"
}

check_command_available() {
  local command_name="$1"
  local install_hint="${2:-}"
  if command -v "$command_name" >/dev/null 2>&1 || [[ "$command_name" == "deno" && -x "${HOME}/.deno/bin/deno" ]]; then
    record_pass "Tool available: ${command_name}"
  else
    local msg="Tool missing from PATH: ${command_name}"
    if [[ -n "$install_hint" ]]; then
      msg+=". Install with: ${install_hint}"
    fi
    record_fail "$msg"
  fi
}

check_file_exists() {
  local file_path="$1"
  local label="$2"
  local remediation="${3:-}"
  if [[ -f "$file_path" ]]; then
    record_pass "${label}: ${file_path}"
  else
    local msg="${label} missing: ${file_path}"
    if [[ -n "$remediation" ]]; then
      msg+=" — ${remediation}"
    fi
    record_fail "$msg"
  fi
}

check_dir_has_files() {
  local dir_path="$1"
  local label="$2"
  local remediation="${3:-}"
  if [[ -d "$dir_path" ]] && [[ -n "$(ls -A "$dir_path" 2>/dev/null)" ]]; then
    record_pass "${label}: found files in ${dir_path}"
  else
    local msg="${label} missing or empty: ${dir_path}"
    if [[ -n "$remediation" ]]; then
      msg+=" — ${remediation}"
    fi
    record_fail "$msg"
  fi
}

# TODO: Document check_env_var.
check_env_var() {
  local env_file="$1"
  local var_name="$2"
  local missing_result="$3"
  local missing_suffix="${4:-}"
  local key_count
  local value
  key_count="$(count_env_key_occurrences "$env_file" "$var_name")"

  if [[ "$key_count" -gt 1 ]]; then
    record_fail "${env_file}: ${var_name} is defined multiple times (${key_count} entries). Remove duplicate ${var_name} lines so the key is defined exactly once."
    return
  fi

  value="$(read_env_value "$env_file" "$var_name")"
  if [[ -n "$value" ]]; then
    record_pass "${env_file}: ${var_name} is set"
    return
  fi

  local message="${env_file}: ${var_name} is missing or empty"
  if [[ -n "$missing_suffix" ]]; then
    message+=" (${missing_suffix})"
  fi
  message+=" — add '${var_name}=<value>' to ${env_file}."

  if [[ "$missing_result" == "warn" ]]; then
    record_warn "$message"
    return
  fi

  record_fail "$message"
}

if [[ $# -ne 1 ]]; then
  record_fail "Expected exactly one environment argument. Run: ./scripts/${SCRIPT_NAME} <environment> where environment is dev | staging | prod."
  print_usage
  print_summary
  exit 1
fi

environment="$1"
if ! is_supported_environment "$environment"; then
  record_fail "Unsupported environment: ${environment}. Use one of: dev | staging | prod."
  print_usage
  print_summary
  exit 1
fi

env_file="$(resolve_env_file_path "$environment")"
if [[ -f "$env_file" ]]; then
  record_pass "Environment file present: ${env_file}"
else
  record_fail "Environment file missing: ${env_file} — $(env_file_creation_hint "${env_file}")"
fi

check_command_available "supabase" "brew install supabase/tap/supabase"
check_command_available "deno" "curl -fsSL https://deno.land/install.sh | sh"

check_file_exists "supabase/config.toml" "Supabase config" "Run 'supabase init' in the repo root to create supabase/config.toml."
check_dir_has_files "supabase/migrations" "Supabase migrations directory" "Create a migration with 'supabase migration new <name>' and commit the generated SQL file under supabase/migrations/."
check_file_exists "supabase/functions/send-notification/index.ts" "Edge function entrypoint" "Create it with 'supabase functions new send-notification' (or restore the file), then commit supabase/functions/send-notification/index.ts."
check_file_exists "supabase/functions/delete-my-account/index.ts" "Edge function entrypoint" "Create it with 'supabase functions new delete-my-account' (or restore the file), then commit supabase/functions/delete-my-account/index.ts."
check_file_exists "supabase/functions/ingest-telemetry/index.ts" "Edge function entrypoint" "Create it with 'supabase functions new ingest-telemetry' (or restore the file), then commit supabase/functions/ingest-telemetry/index.ts."
# Firebase configs are build-time deps owned by build_testflight_release.sh (lines 342-346),
# not deploy-time deps. Skip when called from deploy context (PREFLIGHT_DEPLOY_ONLY=1).
if [[ "${PREFLIGHT_DEPLOY_ONLY:-}" != "1" ]]; then
  check_file_exists "android/app/google-services.json" "Firebase Android config" "Download Android Firebase config for this app from Firebase Console and save it at android/app/google-services.json."
  check_file_exists "ios/Runner/GoogleService-Info.plist" "Firebase iOS config" "Download iOS Firebase config for this app from Firebase Console and save it at ios/Runner/GoogleService-Info.plist."
fi

if [[ -f "$env_file" ]]; then
  # Use environment-specific credential keys (dev uses SUPABASE_LOCAL_* keys)
  credential_keys="$(resolve_supabase_credential_keys "$environment")"
  read -r url_key anon_key_name service_role_key_name <<< "$credential_keys"
  required_keys=("$url_key" "$anon_key_name")

  if is_hosted_environment "$environment"; then
    required_keys+=("$service_role_key_name" "SUPABASE_DB_PASSWORD")
  fi

  for key in "${required_keys[@]}"; do
    check_env_var "$env_file" "$key" "fail"
  done

  notification_missing_result="fail"
  notification_missing_suffix="required for ${environment}"
  if [[ "$environment" == "dev" ]]; then
    notification_missing_result="warn"
    notification_missing_suffix="warn-only for dev"
  fi

  for key in "${NOTIFICATION_SECRET_KEYS[@]}"; do
    check_env_var "$env_file" "$key" "$notification_missing_result" "$notification_missing_suffix"
  done
else
  record_fail "Skipped env-var checks because ${env_file} is missing. $(env_file_creation_hint "${env_file}")"
fi

print_summary
if [[ $fail_count -gt 0 ]]; then
  exit 1
fi
exit 0
