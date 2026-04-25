#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

failures=0

# Live hosted deploy tests need SUPABASE_ACCESS_TOKEN present by default.
# Tests that verify the missing-token path unset it explicitly in subshells.
export SUPABASE_ACCESS_TOKEN=test-access-token

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

assert_file_exists() {
  local file_path="$1"
  local description="$2"
  if [[ ! -f "$file_path" ]]; then
    echo "FAIL: ${description} (missing ${file_path})"
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

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${description} (expected exit ${expected}, got ${actual})"
    failures=$((failures + 1))
  fi
}

read_file_or_empty() {
  if [[ -f "$1" ]]; then cat "$1"; fi
}

# Create a standard .env.staging with all required deployment vars.
# Optional $2 overrides the DB password (default: test-db-password).
create_staging_env_file() {
  local temp_dir="$1"
  local db_password="${2:-test-db-password}"
  cat > "${temp_dir}/.env.staging" <<EOF
SUPABASE_URL=https://staging-ref.supabase.co
SUPABASE_ANON_KEY=test-anon-key
SUPABASE_SERVICE_ROLE_KEY=test-service-role
SUPABASE_DB_PASSWORD=${db_password}
FCM_PROJECT_ID=test-fcm-project
FCM_CLIENT_EMAIL=test-fcm@example.com
FCM_PRIVATE_KEY=test-private-key
NOTIFICATION_WEBHOOK_SECRET=test-webhook-secret
EOF
}

create_hosted_psql_stub() {
  local temp_dir="$1"
  cat > "${temp_dir}/bin/psql" <<'EOF'
#!/usr/bin/env bash
query=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -tAc)
      query="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "$query" == *"app.supabase_url"* ]]; then
  printf '%s\n' "${PSQL_APP_SUPABASE_URL:-}"
  exit 0
fi

if [[ "$query" == *"app.webhook_secret"* ]]; then
  printf '%s\n' "${PSQL_APP_WEBHOOK_SECRET:-}"
  exit 0
fi

exit 1
EOF
  chmod +x "${temp_dir}/bin/psql"
}

setup_script_fixture() {
  local temp_dir="$1"
  mkdir -p "${temp_dir}/scripts/lib" "${temp_dir}/bin"
  cp "${REPO_ROOT}/scripts/deploy_supabase.sh" "${temp_dir}/scripts/"
  cp "${REPO_ROOT}/scripts/validate_deployment.sh" "${temp_dir}/scripts/"
  cp "${REPO_ROOT}/scripts/lib/deployment_common.sh" "${temp_dir}/scripts/lib/"
}

# Desired contract: deploy dry-run should succeed without Firebase app config
# files in a lean worktree. Firebase configs are build-time dependencies owned
# by scripts/dev/build_testflight_release.sh (lines 342-346), not deploy-time.
assert_prod_deploy_dry_run_allows_missing_firebase_configs_in_lean_worktree() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"
  cp "${REPO_ROOT}/scripts/preflight_check.sh" "${temp_dir}/scripts/"
  create_prod_env_file "$temp_dir"

  mkdir -p \
    "${temp_dir}/supabase/migrations" \
    "${temp_dir}/supabase/functions/send-notification" \
    "${temp_dir}/supabase/functions/delete-my-account" \
    "${temp_dir}/supabase/functions/ingest-telemetry"
  cat > "${temp_dir}/supabase/config.toml" <<'EOF'
# fixture config
EOF
  cat > "${temp_dir}/supabase/migrations/20260323000000_fixture.sql" <<'EOF'
-- fixture migration
EOF
  cat > "${temp_dir}/supabase/functions/send-notification/index.ts" <<'EOF'
// fixture entrypoint
EOF
  cat > "${temp_dir}/supabase/functions/delete-my-account/index.ts" <<'EOF'
// fixture entrypoint
EOF
  cat > "${temp_dir}/supabase/functions/ingest-telemetry/index.ts" <<'EOF'
// fixture entrypoint
EOF
  cat > "${temp_dir}/bin/supabase" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${temp_dir}/bin/deno" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/bin/supabase" "${temp_dir}/bin/deno"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh prod --dry-run 2>&1
  )" || status=$?

  assert_exit_code 0 "$status" "prod deploy dry-run succeeds without Firebase configs in lean worktree"
  assert_not_contains "$output" "Firebase Android config missing" "prod deploy dry-run does not reject missing Firebase Android config"
  assert_not_contains "$output" "Firebase iOS config missing" "prod deploy dry-run does not reject missing Firebase iOS config"

  rm -rf "$temp_dir"
}

assert_preflight_rejects_duplicate_deploy_keys() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"
  cp "${REPO_ROOT}/scripts/preflight_check.sh" "${temp_dir}/scripts/"

  mkdir -p \
    "${temp_dir}/supabase/migrations" \
    "${temp_dir}/supabase/functions/send-notification" \
    "${temp_dir}/supabase/functions/delete-my-account" \
    "${temp_dir}/supabase/functions/ingest-telemetry" \
    "${temp_dir}/android/app" \
    "${temp_dir}/ios/Runner"
  cat > "${temp_dir}/supabase/config.toml" <<'EOF'
# fixture config
EOF
  cat > "${temp_dir}/supabase/migrations/20260323000000_fixture.sql" <<'EOF'
-- fixture migration
EOF
  cat > "${temp_dir}/supabase/functions/send-notification/index.ts" <<'EOF'
// fixture entrypoint
EOF
  cat > "${temp_dir}/supabase/functions/delete-my-account/index.ts" <<'EOF'
// fixture entrypoint
EOF
  cat > "${temp_dir}/supabase/functions/ingest-telemetry/index.ts" <<'EOF'
// fixture entrypoint
EOF
  cat > "${temp_dir}/android/app/google-services.json" <<'EOF'
{}
EOF
  cat > "${temp_dir}/ios/Runner/GoogleService-Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict></dict></plist>
EOF
  cat > "${temp_dir}/.env.staging" <<'EOF'
SUPABASE_URL=https://staging-ref.supabase.co
SUPABASE_ANON_KEY=test-anon-key
SUPABASE_SERVICE_ROLE_KEY=old-service-role
SUPABASE_SERVICE_ROLE_KEY=new-service-role
SUPABASE_DB_PASSWORD=test-db-password
FCM_PROJECT_ID=test-fcm-project
FCM_CLIENT_EMAIL=test-fcm@example.com
FCM_PRIVATE_KEY=test-private-key
NOTIFICATION_WEBHOOK_SECRET=test-webhook-secret
EOF
  cat > "${temp_dir}/bin/supabase" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${temp_dir}/bin/deno" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/bin/supabase" "${temp_dir}/bin/deno"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/preflight_check.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "preflight staging fails when deploy-read keys are duplicated"
  assert_contains "$output" ".env.staging: SUPABASE_SERVICE_ROLE_KEY is defined multiple times" "preflight reports duplicate deploy-read key definitions"

  rm -rf "$temp_dir"
}

setup_successful_deploy_fixture() {
  local temp_dir="$1"
  setup_script_fixture "$temp_dir"

  cat > "${temp_dir}/scripts/preflight_check.sh" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/preflight-called"
exit 0
EOF
  cat > "${temp_dir}/scripts/validate_deployment.sh" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/validate-called"
exit 0
EOF
  cat > "${temp_dir}/bin/supabase" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${temp_dir}/supabase-commands.log"
if [[ "\$1" == "secrets" && "\$2" == "set" ]]; then
  while [[ \$# -gt 0 ]]; do
    if [[ "\$1" == "--env-file" ]]; then
      cp "\$2" "${temp_dir}/captured-secrets.env"
      printf '%s' "\$2" > "${temp_dir}/captured-secrets-path"
      break
    fi
    shift
  done
fi
exit 0
EOF
  cat > "${temp_dir}/bin/psql" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${temp_dir}/psql-commands.log"
query=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -c|-tAc)
      query="\$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s\n' "\$query" >> "${temp_dir}/psql-queries.log"
touch "${temp_dir}/vault-sync-called"
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/scripts/validate_deployment.sh" "${temp_dir}/bin/supabase" "${temp_dir}/bin/psql"
}

assert_deploy_dry_run_executes_preflight() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"

  cat > "${temp_dir}/scripts/preflight_check.sh" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/preflight-called"
exit 1
EOF
  cat > "${temp_dir}/scripts/validate_deployment.sh" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/validate-called"
exit 0
EOF
  cat > "${temp_dir}/bin/supabase" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/supabase-called"
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/scripts/validate_deployment.sh" "${temp_dir}/bin/supabase"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh dev --dry-run
  )" || status=$?

  assert_exit_code 1 "$status" "deploy dry-run fails when preflight fails"
  assert_contains "$output" "Preflight checks failed" "deploy dry-run surfaces the preflight failure"
  assert_file_exists "${temp_dir}/preflight-called" "deploy dry-run invokes preflight"
  assert_file_missing "${temp_dir}/validate-called" "deploy dry-run does not invoke validation after preflight failure"
  assert_file_missing "${temp_dir}/supabase-called" "deploy dry-run does not invoke deployment commands after preflight failure"

  rm -rf "$temp_dir"
}

assert_validate_requires_service_role_key() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"

  cat > "${temp_dir}/.env.dev" <<'EOF'
SUPABASE_LOCAL_URL=http://127.0.0.1:54321
SUPABASE_LOCAL_ANON_KEY=test-anon-key
EOF
  cat > "${temp_dir}/bin/curl" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/curl-called"
exit 0
EOF
  cat > "${temp_dir}/bin/docker" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/docker-called"
exit 0
EOF
  chmod +x "${temp_dir}/bin/curl" "${temp_dir}/bin/docker"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/validate_deployment.sh dev
  )" || status=$?

  assert_exit_code 1 "$status" "validate fails when the service-role key is missing"
  assert_contains "$output" "SUPABASE_LOCAL_SERVICE_ROLE_KEY is empty" "validate reports the missing service-role key"
  assert_contains "$output" "Add 'SUPABASE_LOCAL_SERVICE_ROLE_KEY=<value>' to .env.dev" "validate tells operators how to restore the missing service-role key"
  assert_file_missing "${temp_dir}/curl-called" "validate aborts before HTTP checks when the service-role key is missing"
  assert_file_missing "${temp_dir}/docker-called" "validate aborts before trigger-auth checks when the service-role key is missing"

  rm -rf "$temp_dir"
}

assert_validate_reports_manual_trigger_auth_fix() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"

  cat > "${temp_dir}/.env.dev" <<'EOF'
SUPABASE_LOCAL_URL=http://127.0.0.1:54321
SUPABASE_LOCAL_ANON_KEY=test-anon-key
SUPABASE_LOCAL_SERVICE_ROLE_KEY=test-service-role
EOF
  cat > "${temp_dir}/bin/curl" <<EOF
#!/usr/bin/env bash
output_file=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o)
      output_file="\$2"
      shift 2
      ;;
    -w|-H|--max-time)
      shift 2
      ;;
    -s)
      shift
      ;;
    http*)
      shift
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s' '[{"name":"avatars"},{"name":"activity-photos"}]' > "\$output_file"
printf '200'
EOF
  cat > "${temp_dir}/bin/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "ps" ]]; then
  printf '%s\n' 'supabase_db_test'
  exit 0
fi
if [[ "$1" == "exec" ]]; then
  printf '\n'
  exit 0
fi
exit 1
EOF
  chmod +x "${temp_dir}/bin/curl" "${temp_dir}/bin/docker"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/validate_deployment.sh dev
  )" || status=$?

  assert_exit_code 1 "$status" "validate fails when app.webhook_secret is empty"
  assert_contains "$output" "ALTER DATABASE postgres SET app.webhook_secret" "validate points operators to the manual trigger-auth fix"
  assert_not_contains "$output" "run seed" "validate does not suggest seed for trigger-auth remediation"

  rm -rf "$temp_dir"
}

assert_validate_missing_local_db_container_includes_supabase_start() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"

  cat > "${temp_dir}/.env.dev" <<'EOF'
SUPABASE_LOCAL_URL=http://127.0.0.1:54321
SUPABASE_LOCAL_ANON_KEY=test-anon-key
SUPABASE_LOCAL_SERVICE_ROLE_KEY=test-service-role
EOF
  cat > "${temp_dir}/bin/curl" <<EOF
#!/usr/bin/env bash
output_file=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o)
      output_file="\$2"
      shift 2
      ;;
    -w|-H|--max-time)
      shift 2
      ;;
    -s)
      shift
      ;;
    http*)
      shift
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s' '[{"name":"avatars"},{"name":"activity-photos"}]' > "\$output_file"
printf '200'
EOF
  cat > "${temp_dir}/bin/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "ps" ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${temp_dir}/bin/curl" "${temp_dir}/bin/docker"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/validate_deployment.sh dev
  )" || status=$?

  assert_exit_code 1 "$status" "validate fails when the local Supabase DB container is missing"
  assert_contains "$output" "supabase start" "validate tells operators to restore the local stack with supabase start"

  rm -rf "$temp_dir"
}

assert_validate_accepts_hosted_rest_root_401() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"

  create_staging_env_file "$temp_dir"
  create_hosted_psql_stub "$temp_dir"
  cat > "${temp_dir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
method="GET"
output_file=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -X)
      method="$2"
      shift 2
      ;;
    -o)
      output_file="$2"
      shift 2
      ;;
    -w|-H|--max-time|-d)
      shift 2
      ;;
    -s)
      shift
      ;;
    http*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "$url" == "https://staging-ref.supabase.co/rest/v1/" ]]; then
  : > "$output_file"
  printf '401'
  exit 0
fi

if [[ "$url" == "https://staging-ref.supabase.co/storage/v1/bucket" ]]; then
  printf '%s' '[{"name":"avatars"},{"name":"activity-photos"}]' > "$output_file"
  printf '200'
  exit 0
fi

if [[ "$method" == "POST" && "$url" == "https://staging-ref.supabase.co/functions/v1/send-notification" ]]; then
  : > "$output_file"
  printf '401'
  exit 0
fi

if [[ "$method" == "POST" && "$url" == "https://staging-ref.supabase.co/functions/v1/delete-my-account" ]]; then
  : > "$output_file"
  printf '401'
  exit 0
fi

if [[ "$method" == "POST" && "$url" == "https://staging-ref.supabase.co/functions/v1/ingest-telemetry" ]]; then
  : > "$output_file"
  printf '401'
  exit 0
fi

: > "$output_file"
printf '200'
EOF
  cat > "${temp_dir}/bin/docker" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/docker-called"
exit 0
EOF
  chmod +x "${temp_dir}/bin/curl" "${temp_dir}/bin/docker"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_APP_SUPABASE_URL="https://staging-ref.supabase.co" \
    PSQL_APP_WEBHOOK_SECRET="test-webhook-secret" \
    PATH="${temp_dir}/bin:${PATH}" ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 0 "$status" "hosted validation accepts REST root 401 as reachable"
  assert_contains "$output" "[PASS] REST API reachable" "validate records REST root 401 as reachable"
  assert_contains "$output" "[PASS] Hosted trigger config: supabase_url matches SUPABASE_URL" "hosted validation confirms app.supabase_url"
  assert_contains "$output" "[PASS] Hosted trigger config: webhook_secret is configured" "hosted validation confirms app.webhook_secret"
  assert_contains "$output" "Validation summary: 9 passed, 0 failed." "hosted validation still passes all non-dev checks"
  assert_file_missing "${temp_dir}/docker-called" "hosted validation still skips docker trigger-auth checks"

  rm -rf "$temp_dir"
}

assert_deploy_selects_staging_hosted_target() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_successful_deploy_fixture "$temp_dir"

  create_staging_env_file "$temp_dir"
  echo "MAPBOX_ACCESS_TOKEN=do-not-upload" >> "${temp_dir}/.env.staging"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging
  )" || status=$?

  local commands
  commands="$(read_file_or_empty "${temp_dir}/supabase-commands.log")"

  assert_exit_code 0 "$status" "staging deploy succeeds with mocked Supabase commands"
  assert_file_exists "${temp_dir}/preflight-called" "staging deploy invokes preflight"
  assert_file_exists "${temp_dir}/validate-called" "staging deploy invokes validation"
  assert_file_exists "${temp_dir}/supabase-commands.log" "staging deploy emits Supabase command log"
  assert_contains "$commands" "link --project-ref staging-ref --password test-db-password" "link targets the staging project ref with password"
  assert_contains "$commands" "db push --password test-db-password" "db push uses linked project with staging database password"
  assert_contains "$commands" "functions deploy send-notification --no-verify-jwt --project-ref staging-ref" "send-notification deploy targets staging project ref"
  assert_contains "$commands" "functions deploy delete-my-account --project-ref staging-ref" "delete-my-account deploy targets staging project ref"
  assert_contains "$commands" "functions deploy ingest-telemetry --project-ref staging-ref" "ingest-telemetry deploy targets staging project ref"
  assert_contains "$commands" "secrets set --project-ref staging-ref --env-file" "secrets sync targets staging project ref"
  assert_contains "$output" "Deployment complete for 'staging'" "staging deploy reports completion"

  rm -rf "$temp_dir"
}

assert_deploy_syncs_notification_secrets_only() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_successful_deploy_fixture "$temp_dir"

  create_staging_env_file "$temp_dir"
  cat >> "${temp_dir}/.env.staging" <<'EOF'
MAPBOX_ACCESS_TOKEN=do-not-upload
GOOGLE_WEB_CLIENT_ID=do-not-upload
EOF

  local status=0
  (
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging >/dev/null
  ) || status=$?

  local captured_secrets
  captured_secrets="$(read_file_or_empty "${temp_dir}/captured-secrets.env")"

  assert_exit_code 0 "$status" "staging deploy for secrets scope succeeds with mocked Supabase commands"
  assert_file_exists "${temp_dir}/captured-secrets.env" "staging deploy writes a scoped secrets env file for sync"
  assert_contains "$captured_secrets" "FCM_PROJECT_ID=test-fcm-project" "secrets upload includes FCM_PROJECT_ID"
  assert_contains "$captured_secrets" "FCM_CLIENT_EMAIL=test-fcm@example.com" "secrets upload includes FCM_CLIENT_EMAIL"
  assert_contains "$captured_secrets" 'FCM_PRIVATE_KEY="test-private-key"' "secrets upload includes FCM_PRIVATE_KEY"
  assert_contains "$captured_secrets" "NOTIFICATION_WEBHOOK_SECRET=test-webhook-secret" "secrets upload includes NOTIFICATION_WEBHOOK_SECRET"
  assert_not_contains "$captured_secrets" "SUPABASE_URL=" "secrets upload excludes SUPABASE_URL"
  assert_not_contains "$captured_secrets" "SUPABASE_ANON_KEY=" "secrets upload excludes SUPABASE_ANON_KEY"
  assert_not_contains "$captured_secrets" "SUPABASE_SERVICE_ROLE_KEY=" "secrets upload excludes SUPABASE_SERVICE_ROLE_KEY"
  assert_not_contains "$captured_secrets" "SUPABASE_DB_PASSWORD=" "secrets upload excludes SUPABASE_DB_PASSWORD"
  assert_not_contains "$captured_secrets" "MAPBOX_ACCESS_TOKEN=" "secrets upload excludes unrelated app env vars"
  assert_not_contains "$captured_secrets" "GOOGLE_WEB_CLIENT_ID=" "secrets upload excludes unrelated OAuth env vars"

  rm -rf "$temp_dir"
}

assert_deploy_escapes_multiline_fcm_private_key_for_secret_sync() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_successful_deploy_fixture "$temp_dir"

  create_staging_env_file "$temp_dir"
  cat > "${temp_dir}/.env.staging" <<'EOF'
SUPABASE_URL=https://staging-ref.supabase.co
SUPABASE_ANON_KEY=test-anon-key
SUPABASE_SERVICE_ROLE_KEY=test-service-role
SUPABASE_DB_PASSWORD=test-db-password
FCM_PROJECT_ID=test-fcm-project
FCM_CLIENT_EMAIL=test-fcm@example.com
FCM_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----
line-one
line-two
-----END PRIVATE KEY-----
NOTIFICATION_WEBHOOK_SECRET=test-webhook-secret
EOF

  local status=0
  (
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging >/dev/null
  ) || status=$?

  local captured_secrets
  captured_secrets="$(read_file_or_empty "${temp_dir}/captured-secrets.env")"

  assert_exit_code 0 "$status" "staging deploy supports multiline FCM private keys during secrets sync"
  assert_contains "$captured_secrets" 'FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nline-one\nline-two\n-----END PRIVATE KEY-----"' "multiline FCM private key is newline-escaped in the generated secrets env file"

  rm -rf "$temp_dir"
}

assert_deploy_syncs_hosted_vault_secrets_before_validation() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"

  cat > "${temp_dir}/scripts/preflight_check.sh" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/preflight-called"
exit 0
EOF
  cat > "${temp_dir}/scripts/validate_deployment.sh" <<EOF
#!/usr/bin/env bash
if [[ ! -f "${temp_dir}/vault-sync-called" ]]; then
  echo "vault sync missing before validation"
  exit 1
fi
touch "${temp_dir}/validate-called"
exit 0
EOF
  cat > "${temp_dir}/bin/supabase" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${temp_dir}/supabase-commands.log"
if [[ "\$1" == "secrets" && "\$2" == "set" ]]; then
  while [[ \$# -gt 0 ]]; do
    if [[ "\$1" == "--env-file" ]]; then
      cp "\$2" "${temp_dir}/captured-secrets.env"
      printf '%s' "\$2" > "${temp_dir}/captured-secrets-path"
      break
    fi
    shift
  done
fi
exit 0
EOF
  cat > "${temp_dir}/bin/psql" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${temp_dir}/psql-commands.log"
query=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -c|-tAc)
      query="\$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s\n' "\$query" >> "${temp_dir}/psql-queries.log"
touch "${temp_dir}/vault-sync-called"
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/scripts/validate_deployment.sh" "${temp_dir}/bin/supabase" "${temp_dir}/bin/psql"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging
  )" || status=$?

  local psql_queries
  psql_queries="$(read_file_or_empty "${temp_dir}/psql-queries.log")"

  assert_exit_code 0 "$status" "staging deploy syncs Vault secrets before validation"
  assert_file_exists "${temp_dir}/vault-sync-called" "staging deploy invokes hosted Vault sync"
  assert_file_exists "${temp_dir}/validate-called" "staging deploy still runs validation after Vault sync"
  assert_contains "$psql_queries" "supabase_url" "Vault sync provisions the hosted supabase_url secret"
  assert_contains "$psql_queries" "webhook_secret" "Vault sync provisions the hosted webhook_secret secret"
  assert_contains "$psql_queries" "vault.create_secret" "Vault sync can create missing hosted secrets"
  assert_contains "$psql_queries" "vault.update_secret" "Vault sync can update existing hosted secrets"
  assert_contains "$output" "Deployment complete for 'staging'" "staging deploy reports completion after Vault sync"

  rm -rf "$temp_dir"
}

assert_staging_dry_run_redacts_password() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"

  cat > "${temp_dir}/scripts/preflight_check.sh" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  cat > "${temp_dir}/bin/supabase" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/bin/supabase"

  create_staging_env_file "$temp_dir" "s3cret-pa55word"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging --dry-run
  )" || status=$?

  assert_exit_code 0 "$status" "staging dry-run exits zero"
  assert_not_contains "$output" "s3cret-pa55word" "staging dry-run must not leak the database password"
  assert_contains "$output" "--password" "staging dry-run shows --password flag (redacted)"
  assert_contains "$output" "***" "staging dry-run shows redaction marker for password value"

  rm -rf "$temp_dir"
}

assert_delete_my_account_deployed_with_jwt_verification() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_successful_deploy_fixture "$temp_dir"

  create_staging_env_file "$temp_dir"

  local status=0
  local output
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging
  )" || status=$?

  local commands
  commands="$(read_file_or_empty "${temp_dir}/supabase-commands.log")"

  assert_exit_code 0 "$status" "staging deploy succeeds for JWT verification test"
  # send-notification is trigger-called, so it should still have --no-verify-jwt
  assert_contains "$commands" "functions deploy send-notification --no-verify-jwt" "send-notification keeps --no-verify-jwt (trigger-called)"
  # delete-my-account is user-authenticated — gateway should verify JWT
  assert_contains "$commands" "functions deploy delete-my-account --project-ref staging-ref" "delete-my-account deploys with project-ref"
  assert_not_contains "$commands" "delete-my-account --no-verify-jwt" "delete-my-account must NOT use --no-verify-jwt (user-authenticated)"
  # ingest-telemetry is user-authenticated — gateway should verify JWT
  assert_contains "$commands" "functions deploy ingest-telemetry --project-ref staging-ref" "ingest-telemetry deploys with project-ref"
  assert_not_contains "$commands" "ingest-telemetry --no-verify-jwt" "ingest-telemetry must NOT use --no-verify-jwt (user-authenticated)"

  rm -rf "$temp_dir"
}

# Create a standard .env.prod with all required deployment vars.
create_prod_env_file() {
  local temp_dir="$1"
  local db_password="${2:-prod-db-password}"
  cat > "${temp_dir}/.env.prod" <<EOF
SUPABASE_URL=https://prod-ref.supabase.co
SUPABASE_ANON_KEY=prod-anon-key
SUPABASE_SERVICE_ROLE_KEY=prod-service-role
SUPABASE_DB_PASSWORD=${db_password}
FCM_PROJECT_ID=prod-fcm-project
FCM_CLIENT_EMAIL=prod-fcm@example.com
FCM_PRIVATE_KEY=prod-private-key
NOTIFICATION_WEBHOOK_SECRET=prod-webhook-secret
EOF
}

assert_dev_live_deploy_blocked() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"

  cat > "${temp_dir}/scripts/preflight_check.sh" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/preflight-called"
exit 0
EOF
  cat > "${temp_dir}/bin/supabase" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/supabase-called"
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/bin/supabase"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh dev
  )" || status=$?

  assert_exit_code 1 "$status" "dev live deploy is rejected"
  assert_contains "$output" "Live deploy is not supported for 'dev'" "dev live deploy error message"
  assert_file_missing "${temp_dir}/preflight-called" "dev live deploy does not reach preflight"
  assert_file_missing "${temp_dir}/supabase-called" "dev live deploy does not invoke supabase"

  rm -rf "$temp_dir"
}

assert_deploy_rejects_non_hosted_url() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"

  cat > "${temp_dir}/scripts/preflight_check.sh" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  cat > "${temp_dir}/bin/supabase" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/bin/supabase"

  # Use a non-supabase.co URL to trigger the extract_project_ref_from_url failure
  cat > "${temp_dir}/.env.staging" <<EOF
SUPABASE_URL=https://my-custom-server.example.com
SUPABASE_ANON_KEY=test-anon-key
SUPABASE_SERVICE_ROLE_KEY=test-service-role
SUPABASE_DB_PASSWORD=test-db-password
FCM_PROJECT_ID=test-fcm-project
FCM_CLIENT_EMAIL=test-fcm@example.com
FCM_PRIVATE_KEY=test-private-key
NOTIFICATION_WEBHOOK_SECRET=test-webhook-secret
EOF

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "deploy rejects non-hosted URL"
  assert_contains "$output" "must be a hosted Supabase URL" "deploy error explains the URL must be *.supabase.co"

  rm -rf "$temp_dir"
}

assert_deploy_rejects_empty_db_password() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"

  cat > "${temp_dir}/scripts/preflight_check.sh" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  cat > "${temp_dir}/bin/supabase" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/bin/supabase"

  cat > "${temp_dir}/.env.staging" <<EOF
SUPABASE_URL=https://staging-ref.supabase.co
SUPABASE_ANON_KEY=test-anon-key
SUPABASE_SERVICE_ROLE_KEY=test-service-role
SUPABASE_DB_PASSWORD=
FCM_PROJECT_ID=test-fcm-project
FCM_CLIENT_EMAIL=test-fcm@example.com
FCM_PRIVATE_KEY=test-private-key
NOTIFICATION_WEBHOOK_SECRET=test-webhook-secret
EOF

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging
  )" || status=$?

  assert_exit_code 1 "$status" "deploy rejects empty SUPABASE_DB_PASSWORD"
  assert_contains "$output" "SUPABASE_DB_PASSWORD is empty" "deploy error reports missing DB password"

  rm -rf "$temp_dir"
}

assert_deploy_fails_on_missing_notification_secret() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_successful_deploy_fixture "$temp_dir"

  # Write env file with FCM_PRIVATE_KEY missing entirely
  cat > "${temp_dir}/.env.staging" <<EOF
SUPABASE_URL=https://staging-ref.supabase.co
SUPABASE_ANON_KEY=test-anon-key
SUPABASE_SERVICE_ROLE_KEY=test-service-role
SUPABASE_DB_PASSWORD=test-db-password
FCM_PROJECT_ID=test-fcm-project
FCM_CLIENT_EMAIL=test-fcm@example.com
NOTIFICATION_WEBHOOK_SECRET=test-webhook-secret
EOF

  local output
  local status=0
  # Capture both stdout and stderr since the error goes to stderr
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging 2>&1
  )" || status=$?

  assert_exit_code 1 "$status" "deploy fails when FCM_PRIVATE_KEY is missing"
  assert_contains "$output" "FCM_PRIVATE_KEY is empty" "deploy error reports the missing notification secret"

  rm -rf "$temp_dir"
}

assert_prod_deploy_targets_prod_project_ref() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_successful_deploy_fixture "$temp_dir"

  create_prod_env_file "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh prod
  )" || status=$?

  local commands
  commands="$(read_file_or_empty "${temp_dir}/supabase-commands.log")"

  assert_exit_code 0 "$status" "prod deploy succeeds with mocked Supabase commands"
  assert_file_exists "${temp_dir}/preflight-called" "prod deploy invokes preflight"
  assert_file_exists "${temp_dir}/validate-called" "prod deploy invokes validation"
  assert_contains "$commands" "link --project-ref prod-ref --password prod-db-password" "link targets the prod project ref with password"
  assert_contains "$commands" "db push --password prod-db-password" "db push uses linked project with prod database password"
  assert_contains "$commands" "functions deploy send-notification --no-verify-jwt --project-ref prod-ref" "send-notification deploy targets prod project ref"
  assert_contains "$commands" "functions deploy delete-my-account --project-ref prod-ref" "delete-my-account deploy targets prod project ref"
  assert_contains "$commands" "functions deploy ingest-telemetry --project-ref prod-ref" "ingest-telemetry deploy targets prod project ref"
  assert_contains "$commands" "secrets set --project-ref prod-ref --env-file" "secrets sync targets prod project ref"
  assert_contains "$output" "Deployment complete for 'prod'" "prod deploy reports completion"

  rm -rf "$temp_dir"
}

setup_preflight_fixture() {
  local temp_dir="$1"
  setup_script_fixture "$temp_dir"
  cp "${REPO_ROOT}/scripts/preflight_check.sh" "${temp_dir}/scripts/"

  mkdir -p \
    "${temp_dir}/supabase/migrations" \
    "${temp_dir}/supabase/functions/send-notification" \
    "${temp_dir}/supabase/functions/delete-my-account" \
    "${temp_dir}/supabase/functions/ingest-telemetry" \
    "${temp_dir}/android/app" \
    "${temp_dir}/ios/Runner"
  cat > "${temp_dir}/supabase/config.toml" <<'EOF'
# fixture config
EOF
  cat > "${temp_dir}/supabase/migrations/20260323000000_fixture.sql" <<'EOF'
-- fixture migration
EOF
  cat > "${temp_dir}/supabase/functions/send-notification/index.ts" <<'EOF'
// fixture entrypoint
EOF
  cat > "${temp_dir}/supabase/functions/delete-my-account/index.ts" <<'EOF'
// fixture entrypoint
EOF
  cat > "${temp_dir}/supabase/functions/ingest-telemetry/index.ts" <<'EOF'
// fixture entrypoint
EOF
  cat > "${temp_dir}/android/app/google-services.json" <<'EOF'
{}
EOF
  cat > "${temp_dir}/ios/Runner/GoogleService-Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict></dict></plist>
EOF
  cat > "${temp_dir}/.env.dev" <<'EOF'
SUPABASE_LOCAL_URL=http://127.0.0.1:54321
SUPABASE_LOCAL_ANON_KEY=test-anon-key
SUPABASE_LOCAL_SERVICE_ROLE_KEY=test-service-role
FCM_PROJECT_ID=test-fcm-project
FCM_CLIENT_EMAIL=test-fcm@example.com
FCM_PRIVATE_KEY=test-private-key
NOTIFICATION_WEBHOOK_SECRET=test-webhook-secret
EOF
  cat > "${temp_dir}/bin/supabase" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${temp_dir}/bin/deno" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/bin/supabase" "${temp_dir}/bin/deno"
}

assert_preflight_missing_supabase_includes_install() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_preflight_fixture "$temp_dir"
  rm -f "${temp_dir}/bin/supabase"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:/usr/bin:/bin" ./scripts/preflight_check.sh dev
  )" || status=$?

  assert_exit_code 1 "$status" "preflight fails when supabase CLI is missing"
  assert_contains "$output" "brew install supabase" "missing supabase message includes install command"

  rm -rf "$temp_dir"
}

assert_preflight_missing_deno_includes_install() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_preflight_fixture "$temp_dir"
  rm -f "${temp_dir}/bin/deno"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    HOME="${temp_dir}" PATH="${temp_dir}/bin:/usr/bin:/bin" ./scripts/preflight_check.sh dev
  )" || status=$?

  assert_exit_code 1 "$status" "preflight fails when deno is missing"
  assert_contains "$output" "curl -fsSL https://deno.land/install.sh" "missing deno message includes install command"

  rm -rf "$temp_dir"
}

assert_preflight_missing_supabase_files_include_actions() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_preflight_fixture "$temp_dir"
  rm -f "${temp_dir}/supabase/config.toml"
  rm -rf "${temp_dir}/supabase/migrations"
  rm -f "${temp_dir}/supabase/functions/send-notification/index.ts"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/preflight_check.sh dev
  )" || status=$?

  assert_exit_code 1 "$status" "preflight fails when supabase files are missing"
  assert_contains "$output" "supabase init" "missing config.toml message includes supabase init"
  assert_contains "$output" "supabase migration" "missing migrations message includes migration guidance"
  assert_contains "$output" "index.ts" "missing edge function message includes file path"

  rm -rf "$temp_dir"
}

assert_preflight_unsupported_env_lists_valid_values() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_preflight_fixture "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/preflight_check.sh invalid
  )" || status=$?

  assert_exit_code 1 "$status" "preflight fails on unsupported environment"
  assert_contains "$output" "dev | staging | prod" "unsupported environment message lists valid values"

  rm -rf "$temp_dir"
}

assert_preflight_missing_env_file_includes_creation_hint() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_preflight_fixture "$temp_dir"
  rm -f "${temp_dir}/.env.dev"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/preflight_check.sh dev
  )" || status=$?

  assert_exit_code 1 "$status" "preflight fails when env file is missing"
  assert_contains "$output" "cp .env.example" "missing env file message includes creation hint"

  rm -rf "$temp_dir"
}

assert_preflight_skipped_env_checks_includes_creation_hint() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_preflight_fixture "$temp_dir"
  rm -f "${temp_dir}/.env.dev"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/preflight_check.sh dev
  )" || status=$?

  assert_exit_code 1 "$status" "preflight fails when env file is missing (skipped checks path)"
  assert_contains "$output" "Skipped env-var checks" "skipped env checks message appears"
  assert_contains "$output" ".env.dev" "skipped env checks names the missing file"

  rm -rf "$temp_dir"
}

assert_preflight_duplicate_env_key_includes_fix_action() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_preflight_fixture "$temp_dir"
  cat > "${temp_dir}/.env.dev" <<'EOF'
SUPABASE_LOCAL_URL=http://127.0.0.1:54321
SUPABASE_LOCAL_URL=http://127.0.0.1:54321
SUPABASE_LOCAL_ANON_KEY=test-anon-key
SUPABASE_LOCAL_SERVICE_ROLE_KEY=test-service-role
FCM_PROJECT_ID=test-fcm-project
FCM_CLIENT_EMAIL=test-fcm@example.com
FCM_PRIVATE_KEY=test-private-key
NOTIFICATION_WEBHOOK_SECRET=test-webhook-secret
EOF

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/preflight_check.sh dev
  )" || status=$?

  assert_exit_code 1 "$status" "preflight fails on duplicate env key"
  assert_contains "$output" "defined multiple times" "duplicate key message appears"
  assert_contains "$output" "Remove duplicate" "duplicate key message includes fix action"

  rm -rf "$temp_dir"
}

assert_preflight_missing_arg_lists_valid_envs() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_preflight_fixture "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/preflight_check.sh
  )" || status=$?

  assert_exit_code 1 "$status" "preflight fails with no arguments"
  assert_contains "$output" "dev | staging | prod" "missing arg message lists valid environments"

  rm -rf "$temp_dir"
}

assert_validate_skips_trigger_auth_for_hosted() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"

  create_staging_env_file "$temp_dir"
  create_hosted_psql_stub "$temp_dir"

  cat > "${temp_dir}/bin/curl" <<EOF
#!/usr/bin/env bash
method="GET"
output_file=""
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
      shift
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s' '[{"name":"avatars"},{"name":"activity-photos"}]' > "\$output_file"
printf '200'
EOF
  cat > "${temp_dir}/bin/docker" <<EOF
#!/usr/bin/env bash
# If docker is called at all for staging, record it — this should NOT happen.
touch "${temp_dir}/docker-called"
exit 0
EOF
  chmod +x "${temp_dir}/bin/curl" "${temp_dir}/bin/docker"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PSQL_APP_SUPABASE_URL="https://staging-ref.supabase.co" \
    PSQL_APP_WEBHOOK_SECRET="test-webhook-secret" \
    PATH="${temp_dir}/bin:${PATH}" ./scripts/validate_deployment.sh staging
  )" || status=$?

  assert_exit_code 0 "$status" "staging validation passes (all HTTP checks succeed)"
  assert_file_missing "${temp_dir}/docker-called" "staging validation does not invoke docker (trigger-auth probe is dev-only)"
  assert_not_contains "$output" "Trigger auth:" "staging validation output omits trigger-auth references"

  rm -rf "$temp_dir"
}

assert_staging_deploy_fails_without_access_token() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_successful_deploy_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    unset SUPABASE_ACCESS_TOKEN &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging 2>&1
  )" || status=$?

  assert_exit_code 1 "$status" "staging deploy fails without SUPABASE_ACCESS_TOKEN"
  assert_contains "$output" "SUPABASE_ACCESS_TOKEN" "staging deploy error names the missing token"
  assert_contains "$output" "export SUPABASE_ACCESS_TOKEN" "staging deploy error includes remediation"
  assert_file_missing "${temp_dir}/supabase-commands.log" "staging deploy does not invoke supabase commands without token"

  rm -rf "$temp_dir"
}

assert_prod_deploy_fails_without_access_token() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_successful_deploy_fixture "$temp_dir"
  create_prod_env_file "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    unset SUPABASE_ACCESS_TOKEN &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh prod 2>&1
  )" || status=$?

  assert_exit_code 1 "$status" "prod deploy fails without SUPABASE_ACCESS_TOKEN"
  assert_contains "$output" "SUPABASE_ACCESS_TOKEN" "prod deploy error names the missing token"
  assert_contains "$output" "export SUPABASE_ACCESS_TOKEN" "prod deploy error includes remediation"

  rm -rf "$temp_dir"
}

assert_hosted_dry_run_skips_access_token_check() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"

  cat > "${temp_dir}/scripts/preflight_check.sh" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  cat > "${temp_dir}/bin/supabase" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/bin/supabase"
  create_staging_env_file "$temp_dir"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    unset SUPABASE_ACCESS_TOKEN &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging --dry-run 2>&1
  )" || status=$?

  assert_exit_code 0 "$status" "staging dry-run succeeds without SUPABASE_ACCESS_TOKEN"
  assert_not_contains "$output" "SUPABASE_ACCESS_TOKEN" "staging dry-run does not mention access token"

  rm -rf "$temp_dir"
}

assert_hosted_noop_db_push_continues_deploy() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_successful_deploy_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"

  cat > "${temp_dir}/bin/supabase" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${temp_dir}/supabase-commands.log"
if [[ "\$1" == "db" && "\$2" == "push" ]]; then
  echo "No new migrations found."
  echo "Remote database is already up to date."
  exit 1
fi
if [[ "\$1" == "secrets" && "\$2" == "set" ]]; then
  while [[ \$# -gt 0 ]]; do
    if [[ "\$1" == "--env-file" ]]; then
      cp "\$2" "${temp_dir}/captured-secrets.env"
      printf '%s' "\$2" > "${temp_dir}/captured-secrets-path"
      break
    fi
    shift
  done
fi
exit 0
EOF
  chmod +x "${temp_dir}/bin/supabase"

  local output
  local status=0
  output="$(
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging 2>&1
  )" || status=$?

  local commands
  commands="$(read_file_or_empty "${temp_dir}/supabase-commands.log")"

  assert_exit_code 0 "$status" "staging deploy treats hosted db push no-op as success"
  assert_contains "$commands" "db push --password test-db-password" "staging deploy still runs db push during no-op path"
  assert_contains "$commands" "functions deploy send-notification --no-verify-jwt --project-ref staging-ref" "staging deploy still runs function deploys after db push no-op"
  assert_file_exists "${temp_dir}/validate-called" "staging deploy still runs post-deploy validation after db push no-op"
  assert_contains "$output" "Deployment complete for 'staging'" "staging deploy still reports completion after db push no-op"

  rm -rf "$temp_dir"
}

assert_temp_secrets_file_cleaned_after_success() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_successful_deploy_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"

  local status=0
  (
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging >/dev/null 2>&1
  ) || status=$?

  assert_exit_code 0 "$status" "staging deploy succeeds for temp-file cleanup test"
  assert_file_exists "${temp_dir}/captured-secrets-path" "supabase stub recorded the secrets file path"

  local secrets_path
  secrets_path="$(cat "${temp_dir}/captured-secrets-path")"
  assert_file_missing "$secrets_path" "temp secrets file is cleaned up after successful deploy"

  rm -rf "$temp_dir"
}

assert_temp_secrets_file_cleaned_after_hosted_failure() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"

  cat > "${temp_dir}/scripts/preflight_check.sh" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  cat > "${temp_dir}/scripts/validate_deployment.sh" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  # Supabase stub: succeed for link and db push, record secrets path, then FAIL
  cat > "${temp_dir}/bin/supabase" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${temp_dir}/supabase-commands.log"
if [[ "\$1" == "secrets" && "\$2" == "set" ]]; then
  while [[ \$# -gt 0 ]]; do
    if [[ "\$1" == "--env-file" ]]; then
      printf '%s' "\$2" > "${temp_dir}/captured-secrets-path"
      exit 1
    fi
    shift
  done
fi
exit 0
EOF
  cat > "${temp_dir}/bin/psql" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/vault-sync-called"
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/scripts/validate_deployment.sh" "${temp_dir}/bin/supabase" "${temp_dir}/bin/psql"

  local status=0
  (
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging >/dev/null 2>&1
  ) || status=$?

  assert_exit_code 1 "$status" "staging deploy fails when secrets set fails"
  assert_file_exists "${temp_dir}/captured-secrets-path" "supabase stub recorded the secrets file path on failure"

  local secrets_path
  secrets_path="$(cat "${temp_dir}/captured-secrets-path")"
  assert_file_missing "$secrets_path" "temp secrets file is cleaned up after hosted failure"

  rm -rf "$temp_dir"
}

assert_temp_secrets_file_cleaned_on_signal() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  setup_script_fixture "$temp_dir"
  create_staging_env_file "$temp_dir"

  cat > "${temp_dir}/scripts/preflight_check.sh" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  cat > "${temp_dir}/scripts/validate_deployment.sh" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  # Supabase stub: succeed for all commands except secrets set,
  # where it records the path then signals the deploy script to terminate.
  cat > "${temp_dir}/bin/supabase" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${temp_dir}/supabase-commands.log"
if [[ "\$1" == "secrets" && "\$2" == "set" ]]; then
  while [[ \$# -gt 0 ]]; do
    if [[ "\$1" == "--env-file" ]]; then
      printf '%s' "\$2" > "${temp_dir}/captured-secrets-path"
      # Signal the parent deploy script (PPID) to terminate
      kill -TERM \$PPID
      sleep 1
      exit 0
    fi
    shift
  done
fi
exit 0
EOF
  cat > "${temp_dir}/bin/psql" <<EOF
#!/usr/bin/env bash
touch "${temp_dir}/vault-sync-called"
exit 0
EOF
  chmod +x "${temp_dir}/scripts/preflight_check.sh" "${temp_dir}/scripts/validate_deployment.sh" "${temp_dir}/bin/supabase" "${temp_dir}/bin/psql"

  # Run in background so we can wait for it
  (
    cd "$temp_dir" &&
    PATH="${temp_dir}/bin:${PATH}" ./scripts/deploy_supabase.sh staging >/dev/null 2>&1
  ) &
  local deploy_pid=$!
  wait "$deploy_pid" 2>/dev/null || true

  # Give the EXIT trap a moment to fire
  sleep 0.1

  if [[ -f "${temp_dir}/captured-secrets-path" ]]; then
    local secrets_path
    secrets_path="$(cat "${temp_dir}/captured-secrets-path")"
    assert_file_missing "$secrets_path" "temp secrets file is cleaned up after signal-driven exit"
  fi
  # If captured-secrets-path doesn't exist, the signal arrived before secrets set — nothing to verify

  rm -rf "$temp_dir"
}

main() {
  assert_prod_deploy_dry_run_allows_missing_firebase_configs_in_lean_worktree
  assert_preflight_rejects_duplicate_deploy_keys
  assert_deploy_dry_run_executes_preflight
  assert_validate_requires_service_role_key
  assert_validate_reports_manual_trigger_auth_fix
  assert_validate_accepts_hosted_rest_root_401
  assert_deploy_selects_staging_hosted_target
  assert_deploy_syncs_notification_secrets_only
  assert_deploy_escapes_multiline_fcm_private_key_for_secret_sync
  assert_deploy_syncs_hosted_vault_secrets_before_validation
  assert_staging_dry_run_redacts_password
  assert_delete_my_account_deployed_with_jwt_verification
  assert_dev_live_deploy_blocked
  assert_deploy_rejects_non_hosted_url
  assert_deploy_rejects_empty_db_password
  assert_deploy_fails_on_missing_notification_secret
  assert_prod_deploy_targets_prod_project_ref
  assert_validate_skips_trigger_auth_for_hosted
  assert_validate_missing_local_db_container_includes_supabase_start
  assert_preflight_missing_supabase_includes_install
  assert_preflight_missing_deno_includes_install
  assert_preflight_missing_supabase_files_include_actions
  assert_preflight_unsupported_env_lists_valid_values
  assert_preflight_missing_env_file_includes_creation_hint
  assert_preflight_skipped_env_checks_includes_creation_hint
  assert_preflight_duplicate_env_key_includes_fix_action
  assert_preflight_missing_arg_lists_valid_envs
  assert_staging_deploy_fails_without_access_token
  assert_prod_deploy_fails_without_access_token
  assert_hosted_dry_run_skips_access_token_check
  assert_hosted_noop_db_push_continues_deploy
  assert_temp_secrets_file_cleaned_after_success
  assert_temp_secrets_file_cleaned_after_hosted_failure
  assert_temp_secrets_file_cleaned_on_signal

  if [[ "$failures" -ne 0 ]]; then
    echo "${failures} assertion(s) failed"
    exit 1
  fi

  echo "deployment_stage3_test: PASS"
}

main "$@"
