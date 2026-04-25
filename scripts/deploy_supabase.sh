#!/usr/bin/env bash
# deploy_supabase.sh — Orchestrate Supabase deployment for a target environment.
#
# Usage:
#   ./scripts/deploy_supabase.sh <environment> [--dry-run]
#   environment: dev | staging | prod
#
# dev is only supported with --dry-run (prints the hosted-equivalent step
# sequence without mutating anything). For live local schema changes use
# `supabase db reset` directly.
#
# Exit codes:
#   0 => deployment (or dry-run) completed successfully
#   1 => preflight failed, dev guardrail triggered, or a deploy step failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
source "${SCRIPT_DIR}/lib/deployment_common.sh"

# --- Argument parsing ---

print_usage() {
  cat <<EOF
Usage: ./scripts/${SCRIPT_NAME} <environment> [--dry-run]
  environment: dev | staging | prod

  --dry-run   Print the planned deployment steps without executing them.
              Required when environment is 'dev'.

For local development, apply schema changes with 'supabase db reset'.
EOF
}

fail_with_usage() {
  emit_result "FAIL" "$1"
  print_usage
  exit 1
}

dry_run=false
environment=""
project_ref=""
database_password=""
notification_secrets_file=""
hosted_psql_bin=""

cleanup_temp_files() {
  if [[ -n "$notification_secrets_file" && -f "$notification_secrets_file" ]]; then
    rm -f "$notification_secrets_file"
  fi
}

trap cleanup_temp_files EXIT

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      dry_run=true
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    -*)
      fail_with_usage "Unknown option: ${arg}"
      ;;
    *)
      if [[ -z "$environment" ]]; then
        environment="$arg"
      else
        fail_with_usage "Unexpected extra argument: ${arg}"
      fi
      ;;
  esac
done

if [[ -z "$environment" ]]; then
  fail_with_usage "Expected an environment argument."
fi

if ! is_supported_environment "$environment"; then
  fail_with_usage "Unsupported environment: ${environment}"
fi

# --- Dev guardrail ---
# dev is only valid for --dry-run; live local deploys use `supabase db reset`.
if [[ "$environment" == "dev" && "$dry_run" == "false" ]]; then
  emit_result "FAIL" "Live deploy is not supported for 'dev'."
  echo ""
  echo "Local schema changes:  supabase db reset"
  echo "Dry-run smoke test:    ./scripts/${SCRIPT_NAME} dev --dry-run"
  exit 1
fi

# --- Command runner (respects --dry-run) ---

# TODO: Document redact_sensitive_args.
redact_sensitive_args() {
  local skip_next=false
  local result=""
  for arg in "$@"; do
    if [[ "$skip_next" == "true" ]]; then
      result+="*** "
      skip_next=false
      continue
    fi
    if [[ "$arg" == "--password" || "$arg" == "-p" || "$arg" == "--env-file" ]]; then
      result+="${arg} "
      skip_next=true
      continue
    fi
    result+="${arg} "
  done
  printf '%s' "${result% }"
}

describe_notification_secret_keys() {
  local description=""
  local key
  for key in "${NOTIFICATION_SECRET_KEYS[@]}"; do
    if [[ -n "$description" ]]; then
      description+=", "
    fi
    description+="$key"
  done
  printf '%s' "$description"
}

# Run a deployment step, or print the redacted command when --dry-run is set.
run_step() {
  local label="$1"
  shift
  if [[ "$dry_run" == "true" ]]; then
    local display_cmd
    display_cmd="$(redact_sensitive_args "$@")"
    emit_result "DRY-RUN" "${label}: ${display_cmd}"
    return 0
  fi
  emit_result "STEP" "${label}"
  if "$@"; then
    emit_result "PASS" "${label}"
  else
    emit_result "FAIL" "${label} (exit $?)"
    exit 1
  fi
}

# TODO: Document resolve_hosted_target_context.
resolve_hosted_target_context() {
  local env_file="$1"
  local supabase_url
  supabase_url="$(read_env_value "$env_file" "SUPABASE_URL")"
  database_password="$(read_env_value "$env_file" "SUPABASE_DB_PASSWORD")"

  if [[ -z "$supabase_url" ]]; then
    emit_result "FAIL" "SUPABASE_URL is empty in ${env_file} — cannot determine hosted project."
    exit 1
  fi
  if [[ -z "$database_password" ]]; then
    emit_result "FAIL" "SUPABASE_DB_PASSWORD is empty in ${env_file} — cannot run hosted db push."
    exit 1
  fi

  project_ref="$(extract_project_ref_from_url "$supabase_url")" || true
  if [[ -z "$project_ref" ]]; then
    emit_result "FAIL" "SUPABASE_URL must be a hosted Supabase URL (*.supabase.co); got '${supabase_url}'."
    exit 1
  fi
}

# TODO: Document create_notification_secrets_file.
create_notification_secrets_file() {
  local source_env_file="$1"
  local temp_file
  local key
  local value

  temp_file="$(mktemp)"
  for key in "${NOTIFICATION_SECRET_KEYS[@]}"; do
    if [[ "$key" == "FCM_PRIVATE_KEY" ]]; then
      value="$(
        awk -v target_key="$key" '
          BEGIN {
            capture = 0
            found = 0
          }
          {
            raw_line = $0
            line = raw_line
            sub(/^[[:space:]]+/, "", line)

            if (!capture) {
              if (line ~ /^#/ || line == "") {
                next
              }
              if (line ~ /^export[[:space:]]+/) {
                sub(/^export[[:space:]]+/, "", line)
              }
              if (index(line, target_key "=") != 1) {
                next
              }

              value = substr(line, length(target_key) + 2)
              print value
              found = 1

              if (value ~ /^-----BEGIN / && value !~ /-----END [A-Z ]+-----$/) {
                capture = 1
              } else {
                exit
              }
            } else {
              print raw_line
              if (raw_line ~ /^-----END [A-Z ]+-----$/) {
                exit
              }
            }
          }
          END {
            if (!found) {
              exit 1
            }
          }
        ' "$source_env_file" 2>/dev/null || true
      )"
    else
      value="$(read_env_value "$source_env_file" "$key")"
    fi

    if [[ -z "$value" ]]; then
      rm -f "$temp_file"
      emit_result "FAIL" "${key} is empty in ${source_env_file} — cannot sync notification secrets." >&2
      exit 1
    fi

    if [[ "$key" == "FCM_PRIVATE_KEY" ]]; then
      value="${value//$'\r'/}"
      value="${value//$'\n'/\\n}"
      value="${value//\"/\\\"}"
      printf '%s="%s"\n' "$key" "$value" >> "$temp_file"
    else
      printf '%s=%s\n' "$key" "$value" >> "$temp_file"
    fi
  done

  printf '%s\n' "$temp_file"
}

# TODO: Document run_hosted_psql_step.
run_hosted_psql_step() {
  local label="$1"
  local sql="$2"
  shift 2

  if [[ "$dry_run" == "true" ]]; then
    emit_result "DRY-RUN" "$label"
    return 0
  fi

  emit_result "STEP" "$label"
  if PGPASSWORD="$database_password" "$hosted_psql_bin" --no-psqlrc \
    "host=db.${project_ref}.supabase.co port=5432 dbname=postgres user=postgres sslmode=require" \
    -v ON_ERROR_STOP=1 "$@" -c "$sql"; then
    emit_result "PASS" "$label"
  else
    emit_result "FAIL" "$label"
    exit 1
  fi
}

# TODO: Document sync_hosted_vault_secrets.
sync_hosted_vault_secrets() {
  local source_env_file="$1"
  local hosted_supabase_url=""
  local notification_webhook_secret=""
  local escaped_hosted_supabase_url=""
  local escaped_notification_webhook_secret=""
  local vault_sync_sql=""

  hosted_supabase_url="$(read_env_value "$source_env_file" "SUPABASE_URL")"
  if [[ -z "$hosted_supabase_url" ]]; then
    emit_result "FAIL" "SUPABASE_URL is empty in ${source_env_file} — cannot sync hosted Vault secrets."
    exit 1
  fi

  notification_webhook_secret="$(read_env_value "$source_env_file" "NOTIFICATION_WEBHOOK_SECRET")"
  if [[ -z "$notification_webhook_secret" ]]; then
    emit_result "FAIL" "NOTIFICATION_WEBHOOK_SECRET is empty in ${source_env_file} — cannot sync hosted Vault secrets."
    exit 1
  fi

  if [[ -z "$hosted_psql_bin" ]]; then
    hosted_psql_bin="$(resolve_psql_bin || true)"
  fi
  if [[ -z "$hosted_psql_bin" ]]; then
    emit_result "FAIL" "Hosted Vault sync requires psql. Install: brew install libpq && echo 'export PATH=\"/opt/homebrew/opt/libpq/bin:\$PATH\"' >> ~/.zshrc."
    exit 1
  fi

  escaped_hosted_supabase_url="${hosted_supabase_url//\'/\'\'}"
  escaped_notification_webhook_secret="${notification_webhook_secret//\'/\'\'}"

  vault_sync_sql=$(cat <<SQL
do \$vault_sync\$
declare
  existing_secret_id uuid;
begin
  select id
    into existing_secret_id
  from vault.decrypted_secrets
  where name = 'supabase_url'
  limit 1;

  if existing_secret_id is null then
    perform vault.create_secret(
      '${escaped_hosted_supabase_url}',
      'supabase_url',
      'Hosted Supabase project URL for notification triggers'
    );
  else
    perform vault.update_secret(
      existing_secret_id,
      '${escaped_hosted_supabase_url}',
      'supabase_url',
      'Hosted Supabase project URL for notification triggers'
    );
  end if;

  select id
    into existing_secret_id
  from vault.decrypted_secrets
  where name = 'webhook_secret'
  limit 1;

  if existing_secret_id is null then
    perform vault.create_secret(
      '${escaped_notification_webhook_secret}',
      'webhook_secret',
      'Webhook secret used by notification triggers'
    );
  else
    perform vault.update_secret(
      existing_secret_id,
      '${escaped_notification_webhook_secret}',
      'webhook_secret',
      'Webhook secret used by notification triggers'
    );
  end if;
end;
\$vault_sync\$;
SQL
)

  run_hosted_psql_step \
    "Sync hosted Vault secrets for ${project_ref}" \
    "$vault_sync_sql"
}

# TODO: Document run_database_push.
run_database_push() {
  local args=(supabase db push)
  if [[ "$is_hosted_environment" == "true" ]]; then
    args+=(--password "$database_password")
  fi

  # Keep dry-run behavior identical to other steps.
  if [[ "$dry_run" == "true" ]]; then
    run_step "Push database migrations" "${args[@]}"
    return 0
  fi

  emit_result "STEP" "Push database migrations"

  local push_output=""
  local push_status=0
  if push_output="$("${args[@]}" 2>&1)"; then
    if [[ -n "$push_output" ]]; then
      printf '%s\n' "$push_output"
    fi
    emit_result "PASS" "Push database migrations"
    return 0
  else
    push_status=$?
  fi

  if [[ "$is_hosted_environment" == "true" ]]; then
    local push_output_lower
    push_output_lower="$(printf '%s' "$push_output" | tr '[:upper:]' '[:lower:]')"
    if [[ "$push_output_lower" == *"no new migrations"* || "$push_output_lower" == *"already up to date"* ]]; then
      if [[ -n "$push_output" ]]; then
        printf '%s\n' "$push_output"
      fi
      emit_result "PASS" "Push database migrations (no-op: already up to date)"
      return 0
    fi
  fi

  emit_result "FAIL" "Push database migrations (exit ${push_status})"
  if [[ -n "$push_output" ]]; then
    printf '%s\n' "$push_output" >&2
  fi
  exit 1
}

run_function_deploy() {
  local label="$1"
  local function_name="$2"
  shift 2

  local args=(supabase functions deploy "$function_name")
  if [[ "$#" -gt 0 ]]; then
    args+=("$@")
  fi
  if [[ "$is_hosted_environment" == "true" ]]; then
    args+=(--project-ref "$project_ref")
  fi

  run_step "$label" "${args[@]}"
}

# --- Preflight ---

emit_result "INFO" "Running preflight checks for '${environment}'..."
if ! PREFLIGHT_DEPLOY_ONLY=1 "${SCRIPT_DIR}/preflight_check.sh" "$environment"; then
  emit_result "FAIL" "Preflight checks failed — aborting deployment."
  exit 1
fi
emit_result "PASS" "Preflight checks passed."

echo ""

# --- Deployment sequence ---

env_file="$(resolve_env_file_path "$environment")"
is_hosted_environment=false
if is_hosted_environment "$environment"; then
  is_hosted_environment=true
  resolve_hosted_target_context "$env_file"

  # Live hosted deploys require SUPABASE_ACCESS_TOKEN for `supabase link`.
  # Dry-run skips this check because it never calls `supabase link`.
  if [[ "$dry_run" == "false" && -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
    emit_result "FAIL" "SUPABASE_ACCESS_TOKEN is not set — required for hosted deploys."
    echo ""
    echo "  export SUPABASE_ACCESS_TOKEN=<your-token>"
    echo ""
    echo "Then rerun this script."
    exit 1
  fi

  # Link the CLI to the hosted project so db push and secrets set use the
  # managed connection path (pooler-aware) instead of a raw direct URL.
  run_step "Link project ${project_ref}" supabase link --project-ref "$project_ref" --password "$database_password"

  # Hosted Supabase blocks ALTER DATABASE SET for custom app.* parameters, so
  # notification trigger config is synced into Vault after db push instead.
fi

# Step 1: Push database migrations
run_database_push

# Step 2: Sync hosted Vault secrets (staging/prod only)
if [[ "$is_hosted_environment" == "true" ]]; then
  sync_hosted_vault_secrets "$env_file"
elif [[ "$dry_run" == "true" ]]; then
  emit_result "DRY-RUN" "Skip hosted Vault sync (not applicable for dev)"
fi

# Step 3: Deploy Edge Functions
# Note: config.toml sets verify_jwt=false for delete-my-account and send-notification
# in local dev only to avoid ES256/HS256 JWT mismatch. Hosted deploys enforce real JWT.
#
# send-notification: --no-verify-jwt because it's called by DB triggers (pg_net),
#   not by users; authenticates via x-webhook-secret header instead of JWT.
# delete-my-account: no --no-verify-jwt — it's user-authenticated so the gateway
#   must verify JWT. The function also calls auth.getUser() as defense-in-depth.
# ingest-telemetry: no --no-verify-jwt — it's user-authenticated telemetry ingest
#   and must keep JWT verification enforced at the gateway.
run_function_deploy "Deploy send-notification function" send-notification --no-verify-jwt
run_function_deploy "Deploy delete-my-account function" delete-my-account
run_function_deploy "Deploy ingest-telemetry function" ingest-telemetry

# Step 4: Set hosted secrets (staging/prod only — local dev reads env directly)
if [[ "$is_hosted_environment" == "true" ]]; then
  if [[ "$dry_run" == "true" ]]; then
    emit_result "DRY-RUN" "Set notification Edge Function secrets ($(describe_notification_secret_keys)) to project ${project_ref}"
  else
    notification_secrets_file="$(create_notification_secrets_file "$env_file")"
    run_step "Set notification Edge Function secrets for ${project_ref}" supabase secrets set --project-ref "$project_ref" --env-file "$notification_secrets_file"
  fi
else
  if [[ "$dry_run" == "true" ]]; then
    emit_result "DRY-RUN" "Skip secrets set (not applicable for dev — local Supabase reads env directly)"
  fi
fi

# Step 5: Post-deploy validation (live hosted deploys only, never for dry-run)
if [[ "$dry_run" == "false" ]]; then
  echo ""
  emit_result "INFO" "Running post-deploy validation..."
  if "${SCRIPT_DIR}/validate_deployment.sh" "$environment"; then
    emit_result "PASS" "Post-deploy validation passed."
  else
    emit_result "FAIL" "Post-deploy validation failed — deployment may need rollback."
    exit 1
  fi
else
  emit_result "DRY-RUN" "Skip post-deploy validation (dry-run mode)"
fi

echo ""
emit_result "PASS" "Deployment complete for '${environment}'."
exit 0
