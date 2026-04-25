#!/usr/bin/env bash
# validate_deployment.sh — Post-deploy health checks for a Supabase environment.
#
# Usage:
#   ./scripts/validate_deployment.sh <environment>
#   environment: dev | staging | prod
#
# Checks:
#   1. REST API reachability
#   2. Auth health endpoint
#   3. Table existence (profiles)
#   4. Storage bucket verification (avatars, activity-photos)
#   5. Hosted trigger config (staging/prod only; Vault first, legacy app.* fallback)
#   6. Hosted Edge Function reachability (staging/prod only)
#   7. Trigger-auth probe (dev only — detects empty app.webhook_secret after db reset)
#
# Exit codes:
#   0 => all checks passed
#   1 => one or more checks failed

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

env_key_population_hint() {
  local env_file_path="$1"
  local key_name="$2"
  printf "Add '%s=<value>' to %s, then rerun validation." "$key_name" "$env_file_path"
}

require_env_value() {
  local env_file_path="$1"
  local key_name="$2"
  local key_value="$3"
  local failure_reason="$4"

  if [[ -n "$key_value" ]]; then
    return 0
  fi

  emit_result "FAIL" "${key_name} is empty in ${env_file_path} — ${failure_reason}. $(env_key_population_hint "${env_file_path}" "${key_name}")"
  exit 1
}

# --- Argument parsing ---

if [[ $# -ne 1 ]]; then
  emit_result "FAIL" "Expected exactly one environment argument. Run: ./scripts/${SCRIPT_NAME} <environment> where environment is dev | staging | prod."
  print_usage
  exit 1
fi

environment="$1"
if ! is_supported_environment "$environment"; then
  emit_result "FAIL" "Unsupported environment: ${environment}. Use one of: dev | staging | prod."
  print_usage
  exit 1
fi

# --- Credential resolution ---

env_file="$(resolve_env_file_path "$environment")"
if [[ ! -f "$env_file" ]]; then
  emit_result "FAIL" "Environment file missing: ${env_file} — $(env_file_creation_hint "${env_file}")"
  exit 1
fi

credential_keys="$(resolve_supabase_credential_keys "$environment")"
read -r url_key anon_key_name service_role_key_name <<< "$credential_keys"

supabase_url="$(read_env_value "$env_file" "$url_key")"
anon_key="$(read_env_value "$env_file" "$anon_key_name")"
service_role_key="$(read_env_value "$env_file" "$service_role_key_name")"

require_env_value "$env_file" "$url_key" "$supabase_url" "cannot run health checks"
require_env_value "$env_file" "$anon_key_name" "$anon_key" "cannot run health checks"
require_env_value \
  "$env_file" \
  "$service_role_key_name" \
  "$service_role_key" \
  "cannot run health checks"

hosted_project_ref=""
hosted_db_password=""
hosted_dashboard_sql_url=""
hosted_psql_bin=""
if is_hosted_environment "$environment"; then
  hosted_project_ref="$(extract_project_ref_from_url "$supabase_url")" || true
  if [[ -z "$hosted_project_ref" ]]; then
    emit_result "FAIL" "${url_key} must be a hosted Supabase URL (*.supabase.co); got '${supabase_url}'. Replace it with the hosted project URL from the Supabase dashboard, then rerun validation."
    exit 1
  fi

  hosted_dashboard_sql_url="https://supabase.com/dashboard/project/${hosted_project_ref}/sql/new"

  hosted_db_password="$(read_env_value "$env_file" "SUPABASE_DB_PASSWORD")"
  require_env_value \
    "$env_file" \
    "SUPABASE_DB_PASSWORD" \
    "$hosted_db_password" \
    "cannot verify hosted trigger config"
fi

# Timeout and retry settings for HTTP checks
HTTP_TIMEOUT=10
MAX_RETRIES=3
RETRY_DELAY=2

# Shared state for HTTP helpers (bash exit codes are 0-255, so HTTP status
# codes cannot be passed via return; use a global instead).
_last_http_code=""
_last_http_body=""

# HTTP helper: retry a curl request up to MAX_RETRIES times.
# Sets _last_http_code and _last_http_body. Returns 0 on any server response,
# 1 only on total connection failure after all retries.
http_request_with_retry() {
  local method="$1"
  local url="$2"
  shift 2
  local attempt=1

  while [[ $attempt -le $MAX_RETRIES ]]; do
    local tmpfile
    tmpfile="$(mktemp)"
    _last_http_code="$(curl -s -o "$tmpfile" -w '%{http_code}' \
      --max-time "$HTTP_TIMEOUT" \
      -X "$method" \
      "$@" "$url" 2>/dev/null)" || _last_http_code="000"
    _last_http_body="$(cat "$tmpfile")"
    rm -f "$tmpfile"

    # Any server response (even 4xx/5xx) means the host is reachable
    if [[ "$_last_http_code" != "000" ]]; then
      return 0
    fi

    if [[ $attempt -lt $MAX_RETRIES ]]; then
      sleep "$RETRY_DELAY"
    fi
    attempt=$((attempt + 1))
  done

  return 1
}

# TODO: Document check_http.
check_http() {
  local label="$1"
  local method="$2"
  local url="$3"
  local connection_hint="$4"
  local http_hint="$5"
  shift 5

  if ! http_request_with_retry "$method" "$url" "$@"; then
    record_fail "${label} (connection failed after ${MAX_RETRIES} retries at ${url}) — ${connection_hint}"
    return 1
  fi

  if [[ "$_last_http_code" -ge 200 && "$_last_http_code" -lt 300 ]]; then
    record_pass "$label"
    return 0
  else
    record_fail "${label} (HTTP ${_last_http_code} from ${url}) — ${http_hint}"
    return 1
  fi
}

# Wrapper: check that a URL is reachable (any server response counts as pass).
# A 401/403 still proves the server is up — only total connection failure is a fail.
check_reachable() {
  local label="$1"
  local method="$2"
  local url="$3"
  local connection_hint="$4"
  shift 4

  if ! http_request_with_retry "$method" "$url" "$@"; then
    record_fail "${label} (connection failed after ${MAX_RETRIES} retries at ${url}) — ${connection_hint}"
    return 1
  fi

  record_pass "$label"
  return 0
}

# TODO: Document check_reachable_non_404.
check_reachable_non_404() {
  local pass_label="$1"
  local missing_label="$2"
  local method="$3"
  local url="$4"
  local connection_hint="$5"
  local missing_hint="$6"
  shift 6

  if ! http_request_with_retry "$method" "$url" "$@"; then
    record_fail "${pass_label} (connection failed after ${MAX_RETRIES} retries at ${url}) — ${connection_hint}"
    return 1
  fi

  if [[ "$_last_http_code" == "404" ]]; then
    # PostgREST returns 404 with PGRST202 for functions that exist but require
    # parameters. This is NOT "missing" — the function is deployed, it just
    # needs args we don't provide in this probe.
    if printf '%s' "$_last_http_body" | grep -q 'PGRST202'; then
      record_pass "${pass_label} (requires params)"
      return 0
    fi
    record_fail "${missing_label} (HTTP 404 from ${url}) — ${missing_hint}"
    return 1
  fi

  record_pass "$pass_label"
  return 0
}

read_hosted_db_setting() {
  local setting_name="$1"
  local setting_value
  setting_value="$(PGPASSWORD="$hosted_db_password" "$hosted_psql_bin" --no-psqlrc \
    "host=db.${hosted_project_ref}.supabase.co port=5432 dbname=postgres user=postgres sslmode=require" \
    -tAc "SELECT current_setting('${setting_name}', true);" 2>/dev/null)" || return 1

  # Remove shell-level whitespace from psql tabular output.
  setting_value="$(echo "$setting_value" | tr -d '[:space:]')"
  printf '%s\n' "$setting_value"
}

read_hosted_vault_secret() {
  local secret_name="$1"
  local secret_value
  secret_value="$(PGPASSWORD="$hosted_db_password" "$hosted_psql_bin" --no-psqlrc \
    "host=db.${hosted_project_ref}.supabase.co port=5432 dbname=postgres user=postgres sslmode=require" \
    -tAc "SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = '${secret_name}' ORDER BY updated_at DESC NULLS LAST, created_at DESC LIMIT 1;" 2>/dev/null)" || return 1

  secret_value="$(echo "$secret_value" | tr -d '[:space:]')"
  printf '%s\n' "$secret_value"
}

read_hosted_config_value() {
  local vault_secret_name="$1"
  local legacy_setting_name="$2"
  local config_value=""

  if config_value="$(read_hosted_vault_secret "$vault_secret_name")"; then
    if [[ -n "$config_value" ]]; then
      printf '%s\n' "$config_value"
      return 0
    fi
  fi

  read_hosted_db_setting "$legacy_setting_name"
}

# TODO: Document check_hosted_db_setting_matches.
check_hosted_db_setting_matches() {
  local vault_secret_name="$1"
  local setting_name="$2"
  local expected_value="$3"
  local pass_message="$4"
  local actual_value

  if ! actual_value="$(read_hosted_config_value "$vault_secret_name" "$setting_name")"; then
    record_fail "Hosted trigger config: ${setting_name} query failed — retry the hosted DB connection with SUPABASE_DB_PASSWORD from ${env_file}, or inspect Vault secret '${vault_secret_name}' in the Supabase SQL editor: ${hosted_dashboard_sql_url}"
    return 1
  fi

  if [[ -z "$actual_value" ]]; then
    record_fail "Hosted trigger config: ${setting_name} is empty — create Vault secret '${vault_secret_name}' with SELECT vault.create_secret('${expected_value}', '${vault_secret_name}', 'Hosted notification trigger config'); in Supabase SQL editor: ${hosted_dashboard_sql_url}, then rerun validation."
    return 1
  fi

  if [[ "$actual_value" != "$expected_value" ]]; then
    record_fail "Hosted trigger config mismatch: ${setting_name} (expected '${expected_value}', got '${actual_value}') — update Vault secret '${vault_secret_name}' (or the legacy ${setting_name} fallback) in Supabase SQL editor: ${hosted_dashboard_sql_url}, then rerun validation."
    return 1
  fi

  record_pass "$pass_message"
  return 0
}

# TODO: Document check_hosted_db_setting_present.
check_hosted_db_setting_present() {
  local vault_secret_name="$1"
  local setting_name="$2"
  local pass_message="$3"
  local actual_value

  if ! actual_value="$(read_hosted_config_value "$vault_secret_name" "$setting_name")"; then
    record_fail "Hosted trigger config: ${setting_name} query failed — retry the hosted DB connection with SUPABASE_DB_PASSWORD from ${env_file}, or inspect Vault secret '${vault_secret_name}' in the Supabase SQL editor: ${hosted_dashboard_sql_url}"
    return 1
  fi

  if [[ -z "$actual_value" ]]; then
    record_fail "Hosted trigger config: ${setting_name} is empty — create Vault secret '${vault_secret_name}' with SELECT vault.create_secret('<value>', '${vault_secret_name}', 'Hosted notification trigger config'); in Supabase SQL editor: ${hosted_dashboard_sql_url}, then rerun validation."
    return 1
  fi

  record_pass "$pass_message"
  return 0
}

# TODO: Document check_hosted_db_settings.
check_hosted_db_settings() {
  hosted_psql_bin="$(resolve_psql_bin || true)"
  if [[ -z "$hosted_psql_bin" ]]; then
    record_fail "Hosted trigger config check requires psql (not installed). Install: brew install libpq && echo 'export PATH=\"/opt/homebrew/opt/libpq/bin:\$PATH\"' >> ~/.zshrc. Or check settings manually in the Supabase SQL editor: ${hosted_dashboard_sql_url}"
    return 1
  fi

  local status=0
  check_hosted_db_setting_matches \
    "supabase_url" \
    "app.supabase_url" \
    "$supabase_url" \
    "Hosted trigger config: supabase_url matches SUPABASE_URL" || status=1

  check_hosted_db_setting_present \
    "webhook_secret" \
    "app.webhook_secret" \
    "Hosted trigger config: webhook_secret is configured" || status=1

  return "$status"
}

# --- Health Checks ---

echo "Validating deployment for '${environment}' against ${supabase_url}..."
echo ""

# 1. REST API reachability — any server response proves the API is up.
# Hosted Supabase returns 401 on the REST root; that still means reachable.
check_reachable "REST API reachable" "GET" "${supabase_url}/rest/v1/" \
  "Verify SUPABASE_URL and retry the REST API root once the project is reachable." \
  -H "apikey: ${anon_key}" \
  -H "Authorization: Bearer ${anon_key}" || true

# 2. Auth health endpoint (GoTrue exposes /auth/v1/health on Supabase)
check_http "Auth health endpoint" "GET" "${supabase_url}/auth/v1/health" \
  "Retry the auth health endpoint after confirming the hosted project is reachable." \
  "Auth is unhealthy. Check the deployed Auth service for ${environment}, then retry validation." \
  -H "apikey: ${anon_key}" || true

# 3. Table existence: profiles (confirms migrations ran)
check_http "Table exists: profiles" "GET" \
  "${supabase_url}/rest/v1/profiles?select=id&limit=0" \
  "Retry the profiles probe after confirming the REST API is reachable." \
  "Profiles is missing or inaccessible. Confirm the deployed migrations created the profiles table and that the anon key in ${env_file} is current, then retry validation." \
  -H "apikey: ${anon_key}" \
  -H "Authorization: Bearer ${anon_key}" || true

# 4. Storage buckets: avatars and activity-photos
if check_http "Storage bucket listing" "GET" \
  "${supabase_url}/storage/v1/bucket" \
  "Retry the storage bucket listing after confirming Storage is reachable and SUPABASE_SERVICE_ROLE_KEY is current." \
  "Storage bucket listing failed. Verify Storage is enabled and SUPABASE_SERVICE_ROLE_KEY in ${env_file} is correct, then retry validation." \
  -H "apikey: ${service_role_key}" \
  -H "Authorization: Bearer ${service_role_key}"; then
  # Check for required buckets in the JSON response body
  for bucket_name in "avatars" "activity-photos"; do
    if echo "$_last_http_body" | grep -q "\"${bucket_name}\""; then
      record_pass "Storage bucket exists: ${bucket_name}"
    else
      record_fail "Storage bucket missing: ${bucket_name} — create bucket '${bucket_name}' in Supabase Storage for ${environment}, then rerun validation."
    fi
  done
fi

# 5. Hosted trigger config and Edge Function checks (staging/prod only)
if is_hosted_environment "$environment"; then
  # Use fresh psql sessions for each setting read so we never reuse stale session state.
  check_hosted_db_settings || true

  # --- Client contract: RPC and Edge Function reachability ---
  # Auto-extracted from Dart source via shared functions in deployment_common.sh.
  # Same extraction logic the build script uses. No hardcoded list to maintain.
  # A 404 means not deployed. Any other status (401, 200) means it exists.
  # Added after the 2026-03-27 incident where get_my_profile was called by the
  # client but never deployed to hosted.

  dart_source_dir="${SCRIPT_DIR}/../lib"
  if [[ ! -d "${dart_source_dir}" ]]; then
    emit_result "WARN" "Dart source dir not found at ${dart_source_dir} — skipping client contract check"
  else
    while IFS= read -r rpc_name; do
      [ -z "${rpc_name}" ] && continue
      check_reachable_non_404 \
        "RPC reachable: ${rpc_name}" \
        "RPC missing: ${rpc_name}" \
        "POST" \
        "${supabase_url}/rest/v1/rpc/${rpc_name}" \
        "Retry the RPC probe after confirming the REST API is reachable." \
        "Deploy or restore RPC '${rpc_name}' on the hosted database, then rerun validation." \
        -H "apikey: ${anon_key}" \
        -H "Authorization: Bearer ${anon_key}" \
        -H "Content-Type: application/json" \
        -d '{}' || true
    done <<< "$(extract_client_rpc_names "${dart_source_dir}")"

    while IFS= read -r edge_name; do
      [ -z "${edge_name}" ] && continue
      check_reachable_non_404 \
        "Edge Function reachable: ${edge_name}" \
        "Edge Function missing: ${edge_name}" \
        "POST" \
        "${supabase_url}/functions/v1/${edge_name}" \
        "Retry the Edge Function probe after confirming Edge Functions are deployed for ${environment}." \
        "Deploy or restore Edge Function '${edge_name}' for ${environment}, then rerun validation." \
        -H "apikey: ${anon_key}" \
        -H "Authorization: Bearer ${anon_key}" \
        -H "Content-Type: application/json" \
        -d '{}' || true
    done <<< "$(extract_client_edge_function_names "${dart_source_dir}")"
  fi

  # --- Server-triggered Edge Functions (not in client contract) ---
  # send-notification is invoked by DB webhooks, not the Dart client.
  check_reachable_non_404 \
    "Edge Function reachable: send-notification" \
    "Edge Function missing: send-notification" \
    "POST" \
    "${supabase_url}/functions/v1/send-notification" \
    "Retry the send-notification probe after confirming Edge Functions are deployed for ${environment}." \
    "Deploy or restore Edge Function 'send-notification' for ${environment}, then rerun validation." \
    -H "apikey: ${anon_key}" \
    -H "Authorization: Bearer ${anon_key}" \
    -H "Content-Type: application/json" \
    -d '{}' || true
fi

# 6. Trigger-auth probe (dev only)
# After `supabase db reset`, the local DB loses app.webhook_secret, breaking
# trigger → send-notification auth. This SQL probe detects that condition.
if [[ "$environment" == "dev" ]]; then
  # Find the Supabase DB container for local queries
  db_container=""
  db_container="$(docker ps --filter "name=supabase_db_" --format '{{.Names}}' 2>/dev/null | head -1)" || true

  if [[ -n "$db_container" ]]; then
    webhook_secret=""
    webhook_secret="$(docker exec "$db_container" psql -U postgres -d postgres -tAc \
      "SELECT current_setting('app.webhook_secret', true);" 2>/dev/null)" || true

    # Trim whitespace
    webhook_secret="$(echo "$webhook_secret" | tr -d '[:space:]')"

    if [[ -n "$webhook_secret" ]]; then
      record_pass "Trigger auth: app.webhook_secret is configured"
    else
      record_fail "Trigger auth: app.webhook_secret is empty — DB triggers cannot authenticate with send-notification. Set it manually with ALTER DATABASE postgres SET app.webhook_secret = '<secret>', open a new session so the setting takes effect, then rerun validation."
    fi
  else
    record_fail "Trigger auth: cannot find local Supabase DB container — run 'supabase start' to restore the local stack, then rerun validation."
  fi
fi

# --- Summary ---

echo ""
echo "Validation summary: ${pass_count} passed, ${fail_count} failed."
if [[ $fail_count -gt 0 ]]; then
  exit 1
fi
exit 0
