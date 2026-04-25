#!/usr/bin/env bash
set -euo pipefail

# Source shared deployment helpers (includes contract extraction functions).
_build_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_build_script_dir}/../lib/deployment_common.sh"

# TODO: Document usage.
usage() {
  cat <<'EOF' >&2
usage: ./scripts/dev/build_testflight_release.sh [--build-number <n>] [--upload] [--secret-file <path>] [--allow-heavy-checkout] [--skip-contract-check] [--skip-smoke-check]

Build the iOS/TestFlight release from the repo root using the only supported
repo-owned path:
  - lean mobile git worktree
  - external Flutter build dir
  - fresh generated Flutter build cache
  - shared App Store Connect secrets from the primary repo checkout
  - shared local Firebase config copied from the primary repo checkout when needed

Options:
  --build-number <n>       Optional App Store Connect build number.
                           If omitted, this script auto-increments .build_number.
  --upload                 Upload the generated IPA to TestFlight after build.
  --secret-file <path>     Explicit .env.secret file to source before build/upload.
  --allow-heavy-checkout   Escape hatch for operators. Bypasses lean-checkout guard.
  --skip-contract-check    Skip the hosted backend contract check. Requires justification.
  --skip-smoke-check       Skip the DeviceCloud smoke test gate. Requires justification.
EOF
  exit 64
}

read_build_number_value() {
  local build_number_file="$1"
  tr -d '[:space:]' < "${build_number_file}"
}

is_positive_integer() {
  local value="$1"
  [[ "${value}" =~ ^[0-9]+$ ]] && [ "${value}" -gt 0 ]
}

# TODO: Document resolve_public_runtime_token.
resolve_public_runtime_token() {
  local env_file="$1"
  local key="$2"
  local fallback_key="${3:-}"
  local value

  value="$(read_env_value_trimmed "${env_file}" "${key}")"

  if [ -z "${value}" ] && [ -n "${secret_file}" ] && [ -f "${secret_file}" ]; then
    value="$(read_env_value_trimmed "${secret_file}" "${key}")"
  fi

  if [ -z "${value}" ] && [ -n "${fallback_key}" ] && [ -f "${secret_file}" ]; then
    value="$(read_env_value_trimmed "${secret_file}" "${fallback_key}")"
  fi

  if [ -z "${value}" ]; then
    return 1
  fi

  case "${value}" in
    \<*)
      printf '%s\n' "${key} still has a placeholder value." >&2
      return 1
      ;;
    sk.*)
      printf '%s\n' "${key} must be a public token, not a secret-scoped token." >&2
      return 1
      ;;
    pk.*)
      printf '%s\n' "${value}"
      return 0
      ;;
    *)
      printf '%s\n' "${key} must start with pk. for TestFlight/runtime map builds." >&2
      return 1
      ;;
  esac
}

# TODO: Document resolve_secret_value.
resolve_secret_value() {
  local key="$1"
  local fallback_key="${2:-}"
  local value="${!key:-}"

  if [ -n "${value}" ]; then
    printf '%s\n' "${value}"
    return 0
  fi

  if [ -n "${secret_file}" ] && [ -f "${secret_file}" ]; then
    value="$(read_env_value "${secret_file}" "${key}")"
    if [ -n "${value}" ]; then
      printf '%s\n' "${value}"
      return 0
    fi

    if [ -n "${fallback_key}" ]; then
      value="$(read_env_value "${secret_file}" "${fallback_key}")"
      if [ -n "${value}" ]; then
        printf '%s\n' "${value}"
        return 0
      fi
    fi
  fi
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
build_number_file="${repo_root}/.build_number"

build_number=""
effective_build_number=""
secret_file=""
secret_file_hint=""
upload_after_build=0
allow_heavy_checkout=0
skip_contract_check=0
skip_smoke_check=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --build-number)
      [ "$#" -ge 2 ] || usage
      build_number="$2"
      shift 2
      ;;
    --secret-file)
      [ "$#" -ge 2 ] || usage
      secret_file="$2"
      shift 2
      ;;
    --upload)
      upload_after_build=1
      shift
      ;;
    --allow-heavy-checkout)
      allow_heavy_checkout=1
      shift
      ;;
    --skip-contract-check)
      skip_contract_check=1
      shift
      ;;
    --skip-smoke-check)
      skip_smoke_check=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage
      ;;
  esac
done

if [ ! -f "${build_number_file}" ]; then
  printf '%s\n' "Missing required tracked build counter: ${build_number_file}" >&2
  exit 1
fi

stored_build_number="$(read_build_number_value "${build_number_file}")"

if ! is_positive_integer "${stored_build_number}"; then
  printf '%s\n' "Invalid build counter in ${build_number_file}: '${stored_build_number}'" >&2
  printf '%s\n' "Expected a positive integer." >&2
  exit 1
fi

if [ -n "${build_number}" ]; then
  if ! is_positive_integer "${build_number}"; then
    printf '%s\n' "Invalid --build-number '${build_number}'. Expected a positive integer." >&2
    exit 1
  fi

  if [ "$((10#${build_number}))" -le "$((10#${stored_build_number}))" ]; then
    printf '%s\n' "--build-number must be greater than the tracked .build_number value (${stored_build_number})." >&2
    exit 1
  fi

  effective_build_number="${build_number}"
else
  effective_build_number="$((10#${stored_build_number} + 1))"
fi

git_common_dir_raw="$(git -C "${repo_root}" rev-parse --git-common-dir)"
git_common_dir="$(cd "${repo_root}" && cd "${git_common_dir_raw}" && pwd)"
primary_repo_root="$(cd "${git_common_dir}/.." && pwd)"

if [ -z "${secret_file}" ]; then
  if [ -f "${repo_root}/.secret/.env.secret" ]; then
    secret_file="${repo_root}/.secret/.env.secret"
  elif [ -f "${primary_repo_root}/.secret/.env.secret" ]; then
    secret_file="${primary_repo_root}/.secret/.env.secret"
  fi
fi

if [ -n "${secret_file}" ] && [ ! -f "${secret_file}" ]; then
  printf '%s\n' "Unable to locate .env.secret at ${secret_file}." >&2
  exit 1
fi

if [ -n "${secret_file}" ]; then
  secret_file_hint="${secret_file}"
else
  secret_file_hint="${primary_repo_root}/.secret/.env.secret"
fi

heavy_checkout_reasons=()
for dir in data .secret build; do
  if [ -d "${repo_root}/${dir}" ]; then
    heavy_checkout_reasons+=("${dir}/ exists in the checkout root")
  fi
done

if [ "${allow_heavy_checkout}" -ne 1 ] && [ "${#heavy_checkout_reasons[@]}" -gt 0 ]; then
  printf '%s\n' "Refusing to build TestFlight release from a heavyweight checkout." >&2
  printf '%s\n' "Flutter recursively runs xattr over the repo root before iOS builds, and this repo treats a lean mobile worktree as mandatory for release builds." >&2
  printf '%s\n' "Problems found:" >&2
  for reason in "${heavy_checkout_reasons[@]}"; do
    printf '  - %s\n' "${reason}" >&2
  done
  printf '%s\n' "Use a clean mobile worktree and re-run this script there, or pass --allow-heavy-checkout if you are intentionally bypassing the guard." >&2
  exit 2
fi

cd "${repo_root}"

mapbox_public_token="$(
  resolve_public_runtime_token \
    "${repo_root}/.env.prod" \
    "MAPBOX_ACCESS_TOKEN" \
    "MAPBOX_DEFAULT_PUBLIC_TOKEN"
)" || true

if [ -z "${mapbox_public_token}" ]; then
  printf '%s\n' "Refusing to build a production/TestFlight release with a broken map configuration." >&2
  printf '%s\n' "Set MAPBOX_ACCESS_TOKEN in .env.prod, or add MAPBOX_DEFAULT_PUBLIC_TOKEN to ${secret_file_hint} before building again." >&2
  exit 1
fi

upsert_env_key "${repo_root}/.env.prod" "MAPBOX_ACCESS_TOKEN" "${mapbox_public_token}"

# --- Hosted backend contract check ---
# Verify that every RPC/Edge Function the client calls exists on the hosted
# backend. This prevents shipping a build that calls server features that
# haven't been deployed yet (the 2026-03-27 white-screen bug).
contract_check_result="passed"
smoke_check_result="passed"
smoke_stamp_sha_value=""

if [ "${skip_contract_check}" -eq 1 ]; then
  contract_check_result="skipped"
  cat >&2 <<'WARN'
========================================================================
WARNING: Hosted backend contract check skipped (--skip-contract-check).

The contract check exists because builds 11 and 12 shipped with a white
screen due to a missing backend migration (2026-03-27 incident). Skipping
this check means the build may call RPC or Edge Functions that do not
exist on the hosted backend.

Document the justification for skipping in the session log.
========================================================================
WARN
else
  prod_env_file="${repo_root}/.env.prod"
  contract_supabase_url="$(read_env_value_trimmed "${prod_env_file}" "SUPABASE_URL")"
  contract_anon_key="$(read_env_value_trimmed "${prod_env_file}" "SUPABASE_ANON_KEY")"

  if [ -z "${contract_supabase_url}" ] || [ -z "${contract_anon_key}" ]; then
    printf '%s\n' "Cannot run hosted contract check: SUPABASE_URL or SUPABASE_ANON_KEY missing from ${prod_env_file}." >&2
    exit 1
  fi

  # Use primary repo root for Dart source (worktree may not have full lib/).
  # Fall back to current repo root if primary doesn't have lib/.
  contract_source_dir="${primary_repo_root}/lib"
  if [ ! -d "${contract_source_dir}" ]; then
    contract_source_dir="${repo_root}/lib"
  fi

  printf '%s\n' "Checking hosted backend contract against ${contract_supabase_url}..."
  if ! check_hosted_client_contract "${contract_source_dir}" "${contract_supabase_url}" "${contract_anon_key}"; then
    printf '%s\n' "" >&2
    printf '%s\n' "Refusing to build: client code calls backend features that are not deployed." >&2
    printf '%s\n' "Deploy pending migrations/functions first, then re-run this build." >&2
    printf '%s\n' "If you understand the risk, pass --skip-contract-check to bypass." >&2
    exit 1
  fi
  printf '%s\n' "Hosted backend contract check passed."
fi

# --- DeviceCloud smoke test gate ---
# Verify that Maestro smoke tests have passed on DeviceCloud for the current
# commit. The build script does not RUN the tests (they require a debug
# simulator build from the primary checkout). It checks for a stamp file
# written by scripts/dev/run_devicecloud_smoke.sh on success.
if [ "${skip_smoke_check}" -eq 1 ]; then
  smoke_check_result="skipped"
  cat >&2 <<'WARN'
========================================================================
WARNING: DeviceCloud smoke test gate skipped (--skip-smoke-check).

Smoke tests verify core app flows on a real simulator via DeviceCloud.
Skipping this gate means the build has not been validated against the
current codebase.

Document the justification for skipping in the session log.
========================================================================
WARN
else
  smoke_stamp="${primary_repo_root}/tmp/devicecloud/last_passed_sha"
  current_sha="$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || echo "")"

  if [ ! -f "${smoke_stamp}" ]; then
    printf '%s\n' "Refusing to build: no DeviceCloud smoke test results found." >&2
    printf '%s\n' "Run scripts/dev/run_devicecloud_smoke.sh from the primary checkout first." >&2
    printf '%s\n' "If you understand the risk, pass --skip-smoke-check to bypass." >&2
    exit 1
  fi

  # Verify the stamp is from the current commit.
  stamp_sha="$(tr -d '[:space:]' < "${smoke_stamp}")"
  if [ -n "${current_sha}" ] && [ -n "${stamp_sha}" ] && [ "${stamp_sha}" != "${current_sha}" ]; then
    printf '%s\n' "DeviceCloud smoke tests last passed at commit ${stamp_sha}, but HEAD is ${current_sha}." >&2
    printf '%s\n' "Re-run scripts/dev/run_devicecloud_smoke.sh to test the current code." >&2
    printf '%s\n' "If you understand the risk, pass --skip-smoke-check to bypass." >&2
    exit 1
  fi

  smoke_stamp_sha_value="${stamp_sha}"
  printf '%s\n' "DeviceCloud smoke test gate passed (commit ${stamp_sha})."
fi

materialize_shared_firebase_configs_from_primary_checkout "${repo_root}" "${primary_repo_root}"

# Repo-local build output is the biggest avoidable xattr tax. Move it out of the
# checkout before invoking Flutter so the recursive Finder-info scrub stays off
# generated artifacts.
if [ -d "${repo_root}/build" ]; then
  "${script_dir}/migrate_build_cache_out_of_repo.sh"
fi

# This directory is generated state only. Large stale contents materially slow
# Flutter's repo-root xattr sweep before Xcode even starts.
if [ -d "${repo_root}/.dart_tool/flutter_build" ]; then
  rm -rf "${repo_root}/.dart_tool/flutter_build"
fi

if [ "${upload_after_build}" -eq 1 ]; then
  asc_key_path="$(resolve_secret_value "ASC_KEY_PATH" "app_store_connect_uff_mar23_KEY_PATH" || true)"
  asc_key_id="$(resolve_secret_value "ASC_KEY_ID" "app_store_connect_uff_mar23_KEY_ID" || true)"
  asc_issuer_id="$(resolve_secret_value "ASC_ISSUER_ID" "app_store_connect_uff_mar23_ISSUER_ID" || true)"

  if [ -z "${asc_key_path}" ] || [ -z "${asc_key_id}" ] || [ -z "${asc_issuer_id}" ]; then
    printf '%s\n' "Upload requested, but App Store Connect credentials were not resolved from env or ${secret_file_hint}." >&2
    exit 1
  fi

  export ASC_KEY_PATH="${asc_key_path}"
  export ASC_KEY_ID="${asc_key_id}"
  export ASC_ISSUER_ID="${asc_issuer_id}"
fi

"${script_dir}/with_fast_build_dir.sh" flutter build ipa \
  --release \
  --dart-define=APP_ENV=prod \
  --build-number="${effective_build_number}" \
  --export-options-plist=ios/ExportOptions.plist

if [ "${upload_after_build}" -eq 1 ]; then
  (
    cd ios
    fastlane upload_testflight
  )
fi

# Persist the canonical build counter only after this invocation reaches its
# terminal success point: post-build when no upload is requested, or post-upload
# when --upload is enabled.
printf '%s\n' "${effective_build_number}" > "${build_number_file}"

# Write build metadata for post-hoc release auditing.
metadata_dir="${repo_root}/tmp/build"
mkdir -p "${metadata_dir}"
metadata_sha="$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || echo "unknown")"
metadata_timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Format smoke_stamp_sha as JSON (null or quoted string).
if [ -n "${smoke_stamp_sha_value}" ]; then
  smoke_sha_json="\"${smoke_stamp_sha_value}\""
else
  smoke_sha_json="null"
fi

cat > "${metadata_dir}/build_${effective_build_number}_metadata.json" <<METADATA
{
  "build_number": ${effective_build_number},
  "git_sha": "${metadata_sha}",
  "timestamp": "${metadata_timestamp}",
  "contract_check": "${contract_check_result}",
  "smoke_check": "${smoke_check_result}",
  "smoke_stamp_sha": ${smoke_sha_json}
}
METADATA
