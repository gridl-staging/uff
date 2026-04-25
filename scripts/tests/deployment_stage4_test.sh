#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

failures=0

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

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${description} (expected exit ${expected}, got ${actual})"
    failures=$((failures + 1))
  fi
}

assert_file_missing() {
  local file_path="$1"
  local description="$2"
  if [[ -f "$file_path" ]]; then
    echo "FAIL: ${description} (${file_path} exists unexpectedly)"
    failures=$((failures + 1))
  fi
}

setup_validate_fixture() {
  local temp_dir="$1"
  mkdir -p "${temp_dir}/scripts/lib" "${temp_dir}/bin" "${temp_dir}/lib"
  cp "${REPO_ROOT}/scripts/validate_deployment.sh" "${temp_dir}/scripts/"
  cp "${REPO_ROOT}/scripts/lib/deployment_common.sh" "${temp_dir}/scripts/lib/"
  # Mock Dart file so extract_client_edge_function_names finds delete-my-account
  cat > "${temp_dir}/lib/mock_edge_functions.dart" <<'DART'
// Mock client code for testing edge function extraction
final result = await client.functions.invoke('delete-my-account');
DART
}

create_staging_env_file() {
  local temp_dir="$1"
  cat > "${temp_dir}/.env.staging" <<'EOF'
SUPABASE_URL=https://staging-ref.supabase.co
SUPABASE_ANON_KEY=test-anon-key
SUPABASE_SERVICE_ROLE_KEY=test-service-role
SUPABASE_DB_PASSWORD=test-db-password
NOTIFICATION_WEBHOOK_SECRET=test-webhook-secret
EOF
}

create_curl_stub() {
  local temp_dir="$1"
  local send_notification_code="$2"
  local delete_account_code="$3"
  local bucket_payload="${4:-[{\"name\":\"avatars\"},{\"name\":\"activity-photos\"}]}"
  cat > "${temp_dir}/bin/curl" <<EOF
#!/usr/bin/env bash
method="GET"
output_file=""
url=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -X)
      method="\$2"
      shift 2
      ;;
    -o)
      output_file="\$2"
      shift 2
      ;;
    -w|-H|--max-time|-d)
      shift 2
      ;;
    -s)
      shift
      ;;
    http*)
      url="\$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

printf '%s %s\n' "\$method" "\$url" >> "${temp_dir}/curl-requests.log"

if [[ "\$url" == "https://staging-ref.supabase.co/storage/v1/bucket" ]]; then
  printf '%s' '${bucket_payload}' > "\$output_file"
  printf '200'
  exit 0
fi

if [[ "\$url" == "https://staging-ref.supabase.co/functions/v1/send-notification" ]]; then
  : > "\$output_file"
  printf '%s' '${send_notification_code}'
  exit 0
fi

if [[ "\$url" == "https://staging-ref.supabase.co/functions/v1/delete-my-account" ]]; then
  : > "\$output_file"
  printf '%s' '${delete_account_code}'
  exit 0
fi

: > "\$output_file"
printf '200'
EOF
  chmod +x "${temp_dir}/bin/curl"
}

create_connection_failure_stubs() {
  local temp_dir="$1"
  cat > "${temp_dir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  cat > "${temp_dir}/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${temp_dir}/bin/curl" "${temp_dir}/bin/sleep"
}

create_psql_stub() {
  local temp_dir="$1"
  cat > "${temp_dir}/bin/psql" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${temp_dir}/psql-commands.log"
query=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -tAc)
      query="\$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "\$query" == *"app.supabase_url"* ]]; then
  if [[ "\${PSQL_FAIL_APP_SUPABASE_URL:-0}" == "1" ]]; then
    exit 1
  fi
  printf '%s\n' "\${PSQL_APP_SUPABASE_URL:-}"
  exit 0
fi

if [[ "\$query" == *"app.webhook_secret"* ]]; then
  if [[ "\${PSQL_FAIL_APP_WEBHOOK_SECRET:-0}" == "1" ]]; then
    exit 1
  fi
  printf '%s\n' "\${PSQL_APP_WEBHOOK_SECRET:-}"
  exit 0
fi

if [[ "\$query" == *"vault.decrypted_secrets"* && "\$query" == *"name = 'supabase_url'"* ]]; then
  if [[ "\${PSQL_FAIL_VAULT_SUPABASE_URL:-0}" == "1" ]]; then
    exit 1
  fi
  printf '%s\n' "\${PSQL_VAULT_SUPABASE_URL:-}"
  exit 0
fi

if [[ "\$query" == *"vault.decrypted_secrets"* && "\$query" == *"name = 'webhook_secret'"* ]]; then
  if [[ "\${PSQL_FAIL_VAULT_WEBHOOK_SECRET:-0}" == "1" ]]; then
    exit 1
  fi
  printf '%s\n' "\${PSQL_VAULT_WEBHOOK_SECRET:-}"
  exit 0
fi

exit 1
EOF
  chmod +x "${temp_dir}/bin/psql"
}

create_docker_stub() {
  local temp_dir="$1"
  cat > "${temp_dir}/bin/docker" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/docker-called"
exit 0
EOF
  chmod +x "${temp_dir}/bin/docker"
}

assert_hosted_validation_checks_db_settings_and_function_probes() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"
  create_curl_stub "$temp_dir" "401" "500"
  create_psql_stub "$temp_dir"
  create_docker_stub "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_APP_SUPABASE_URL="https://staging-ref.supabase.co" \
    PSQL_APP_WEBHOOK_SECRET="non-empty-secret" \
    PATH="${temp_dir}/bin:${PATH}" \
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  local request_log
  request_log="$(cat "${temp_dir}/curl-requests.log" 2>/dev/null || true)"

  assert_exit_code 0 "$status" "staging validation passes when hosted DB settings match and functions are non-404"
  assert_contains "$output" "DB setting: app.supabase_url matches SUPABASE_URL" "hosted validation checks app.supabase_url"
  assert_contains "$output" "DB setting: app.webhook_secret is configured" "hosted validation checks app.webhook_secret"
  assert_contains "$output" "Function reachable: send-notification" "hosted validation reports send-notification reachability"
  assert_contains "$output" "Function reachable: delete-my-account" "hosted validation reports delete-my-account reachability"
  assert_contains "$request_log" "POST https://staging-ref.supabase.co/functions/v1/send-notification" "hosted validation probes send-notification via POST"
  assert_contains "$request_log" "POST https://staging-ref.supabase.co/functions/v1/delete-my-account" "hosted validation probes delete-my-account via POST"
  assert_file_missing "${temp_dir}/docker-called" "hosted validation does not invoke docker trigger-auth probe"

  rm -rf "$temp_dir"
}

assert_hosted_validation_accepts_vault_secrets_when_app_settings_are_empty() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"
  create_curl_stub "$temp_dir" "401" "401"
  create_psql_stub "$temp_dir"
  create_docker_stub "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_APP_SUPABASE_URL="" \
    PSQL_APP_WEBHOOK_SECRET="" \
    PSQL_VAULT_SUPABASE_URL="https://staging-ref.supabase.co" \
    PSQL_VAULT_WEBHOOK_SECRET="vault-secret" \
    PATH="${temp_dir}/bin:${PATH}" \
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 0 "$status" "staging validation passes when Vault secrets exist and legacy app settings are empty"
  assert_contains "$output" "DB setting: app.supabase_url matches SUPABASE_URL" "Vault-backed validation still confirms supabase_url"
  assert_contains "$output" "DB setting: app.webhook_secret is configured" "Vault-backed validation still confirms webhook_secret"

  rm -rf "$temp_dir"
}

assert_hosted_validation_fails_when_app_supabase_url_empty() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"
  create_curl_stub "$temp_dir" "401" "401"
  create_psql_stub "$temp_dir"
  create_docker_stub "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_APP_SUPABASE_URL="" \
    PSQL_APP_WEBHOOK_SECRET="non-empty-secret" \
    PATH="${temp_dir}/bin:${PATH}" \
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "staging validation fails when app.supabase_url is empty"
  assert_contains "$output" "DB setting: app.supabase_url is empty" "hosted validation reports empty app.supabase_url"

  rm -rf "$temp_dir"
}

assert_hosted_validation_fails_when_app_supabase_url_mismatches() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"
  create_curl_stub "$temp_dir" "401" "401"
  create_psql_stub "$temp_dir"
  create_docker_stub "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_APP_SUPABASE_URL="https://different-project.supabase.co" \
    PSQL_APP_WEBHOOK_SECRET="non-empty-secret" \
    PATH="${temp_dir}/bin:${PATH}" \
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "staging validation fails when app.supabase_url does not match SUPABASE_URL"
  assert_contains "$output" "DB setting mismatch: app.supabase_url" "hosted validation reports app.supabase_url mismatch"
  assert_contains "$output" "different-project.supabase.co" "hosted validation includes mismatched value"

  rm -rf "$temp_dir"
}

assert_hosted_validation_fails_when_app_webhook_secret_empty() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"
  create_curl_stub "$temp_dir" "401" "401"
  create_psql_stub "$temp_dir"
  create_docker_stub "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_APP_SUPABASE_URL="https://staging-ref.supabase.co" \
    PSQL_APP_WEBHOOK_SECRET="" \
    PATH="${temp_dir}/bin:${PATH}" \
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "staging validation fails when app.webhook_secret is empty"
  assert_contains "$output" "DB setting: app.webhook_secret is empty" "hosted validation reports empty app.webhook_secret"

  rm -rf "$temp_dir"
}

assert_hosted_validation_treats_function_404_as_failure() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"
  create_curl_stub "$temp_dir" "404" "401"
  create_psql_stub "$temp_dir"
  create_docker_stub "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_APP_SUPABASE_URL="https://staging-ref.supabase.co" \
    PSQL_APP_WEBHOOK_SECRET="non-empty-secret" \
    PATH="${temp_dir}/bin:${PATH}" \
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "staging validation fails when function endpoint returns 404"
  assert_contains "$output" "Function missing: send-notification" "hosted validation treats function 404 as missing"
  assert_contains "$output" "Deploy or restore Edge Function 'send-notification'" "hosted validation tells operators how to restore the missing Edge Function"

  rm -rf "$temp_dir"
}

assert_hosted_validation_continues_after_first_db_query_failure() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"
  create_curl_stub "$temp_dir" "401" "401"
  create_psql_stub "$temp_dir"
  create_docker_stub "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_FAIL_APP_SUPABASE_URL="1" \
    PSQL_APP_WEBHOOK_SECRET="non-empty-secret" \
    PATH="${temp_dir}/bin:${PATH}" \
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "staging validation fails when the app.supabase_url query fails"
  assert_contains "$output" "DB setting: app.supabase_url query failed" "hosted validation reports the first DB query failure"
  assert_contains "$output" "DB setting: app.webhook_secret is configured" "hosted validation still evaluates the second DB setting"
  assert_contains "$output" "Function reachable: send-notification" "hosted validation still probes functions after a DB query failure"

  rm -rf "$temp_dir"
}

assert_hosted_validation_reports_psql_missing() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"
  create_curl_stub "$temp_dir" "401" "401"
  create_docker_stub "$temp_dir"
  # Deliberately NOT creating psql stub — simulates psql not installed

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    DISABLE_PSQL_AUTO_DISCOVERY=1 \
    PATH="${temp_dir}/bin:/usr/bin:/bin" \
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "staging validation fails when psql is not installed"
  assert_contains "$output" "brew install libpq" "psql-missing message includes install instructions"
  assert_contains "$output" "supabase.com/dashboard/project" "psql-missing message includes dashboard fallback URL"
  # Function probes should still run even when psql is missing
  assert_contains "$output" "Function reachable: send-notification" "function probes still run when psql is missing"

  rm -rf "$temp_dir"
}

assert_validate_missing_arg_lists_valid_envs() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    ./scripts/validate_deployment.sh
  )" || status=$?

  assert_exit_code 1 "$status" "validation fails with no environment argument"
  assert_contains "$output" "dev | staging | prod" "missing argument message lists valid environments"

  rm -rf "$temp_dir"
}

assert_validate_unsupported_env_lists_valid_values() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    ./scripts/validate_deployment.sh invalid
  )" || status=$?

  assert_exit_code 1 "$status" "validation fails on unsupported environment"
  assert_contains "$output" "Use one of: dev | staging | prod" "unsupported environment message lists valid values"

  rm -rf "$temp_dir"
}

assert_hosted_validation_missing_env_file_includes_creation_hint() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "staging validation fails when the env file is missing"
  assert_contains "$output" "cp .env.example .env.staging" "missing env file message includes creation hint"

  rm -rf "$temp_dir"
}

assert_hosted_validation_connection_failures_include_retry_hint() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"
  create_connection_failure_stubs "$temp_dir"
  create_psql_stub "$temp_dir"
  create_docker_stub "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_APP_SUPABASE_URL="https://staging-ref.supabase.co" \
    PSQL_APP_WEBHOOK_SECRET="non-empty-secret" \
    PATH="${temp_dir}/bin:/usr/bin:/bin" \
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "staging validation fails when HTTP checks cannot connect"
  assert_contains "$output" "connection failed after 3 retries at https://staging-ref.supabase.co/auth/v1/health" "connection failure names the endpoint"
  assert_contains "$output" "Retry the auth health endpoint" "connection failure tells operators what to retry"

  rm -rf "$temp_dir"
}

assert_hosted_validation_missing_bucket_includes_creation_hint() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"
  create_curl_stub "$temp_dir" "401" "401" '[{"name":"activity-photos"}]'
  create_psql_stub "$temp_dir"
  create_docker_stub "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_APP_SUPABASE_URL="https://staging-ref.supabase.co" \
    PSQL_APP_WEBHOOK_SECRET="non-empty-secret" \
    PATH="${temp_dir}/bin:${PATH}" \
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "staging validation fails when a required storage bucket is missing"
  assert_contains "$output" "Storage bucket missing: avatars" "missing bucket is reported"
  assert_contains "$output" "create bucket 'avatars'" "missing bucket message includes a creation hint"

  rm -rf "$temp_dir"
}

assert_hosted_validation_empty_supabase_url_includes_remediation() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"
  create_curl_stub "$temp_dir" "401" "401"
  create_psql_stub "$temp_dir"
  create_docker_stub "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_APP_SUPABASE_URL="" \
    PSQL_APP_WEBHOOK_SECRET="non-empty-secret" \
    PATH="${temp_dir}/bin:${PATH}" \
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "staging validation fails when app.supabase_url is empty"
  assert_contains "$output" "vault.create_secret" "empty app.supabase_url message includes Vault remediation"
  assert_contains "$output" "supabase.com/dashboard/project" "empty app.supabase_url message includes dashboard URL"

  rm -rf "$temp_dir"
}

assert_hosted_validation_empty_webhook_secret_includes_remediation() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_validate_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"
  create_curl_stub "$temp_dir" "401" "401"
  create_psql_stub "$temp_dir"
  create_docker_stub "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_APP_SUPABASE_URL="https://staging-ref.supabase.co" \
    PSQL_APP_WEBHOOK_SECRET="" \
    PATH="${temp_dir}/bin:${PATH}" \
    ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "staging validation fails when app.webhook_secret is empty"
  assert_contains "$output" "vault.create_secret" "empty app.webhook_secret message includes Vault remediation"
  assert_contains "$output" "supabase.com/dashboard/project" "empty app.webhook_secret message includes dashboard URL"

  rm -rf "$temp_dir"
}

main() {
  assert_validate_missing_arg_lists_valid_envs
  assert_validate_unsupported_env_lists_valid_values
  assert_hosted_validation_missing_env_file_includes_creation_hint
  assert_hosted_validation_checks_db_settings_and_function_probes
  assert_hosted_validation_accepts_vault_secrets_when_app_settings_are_empty
  assert_hosted_validation_fails_when_app_supabase_url_empty
  assert_hosted_validation_fails_when_app_supabase_url_mismatches
  assert_hosted_validation_fails_when_app_webhook_secret_empty
  assert_hosted_validation_connection_failures_include_retry_hint
  assert_hosted_validation_missing_bucket_includes_creation_hint
  assert_hosted_validation_treats_function_404_as_failure
  assert_hosted_validation_continues_after_first_db_query_failure
  assert_hosted_validation_reports_psql_missing
  assert_hosted_validation_empty_supabase_url_includes_remediation
  assert_hosted_validation_empty_webhook_secret_includes_remediation

  if [[ "$failures" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "deployment_stage4_test: PASS"
}

main "$@"
