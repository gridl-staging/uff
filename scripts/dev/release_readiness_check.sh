#!/usr/bin/env bash
# release_readiness_check.sh — Read-only release readiness summary.
#
# Answers "is this repo ready for a release build?" without building anything.
# Consolidates checks from build_testflight_release.sh, preflight_check.sh,
# and validate_deployment.sh into a single pass/fail/warn report.
#
# Usage:
#   ./scripts/dev/release_readiness_check.sh
#
# Exit codes:
#   0 => all fail-level checks passed (warn findings do not block)
#   1 => one or more fail-level checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/deployment_common.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Resolve primary checkout root (handles worktree case).
git_common_dir_raw="$(git -C "${REPO_ROOT}" rev-parse --git-common-dir)"
git_common_dir="$(cd "${REPO_ROOT}" && cd "${git_common_dir_raw}" && pwd)"
primary_repo_root="$(cd "${git_common_dir}/.." && pwd)"

# --- Check: .build_number ---
check_build_number() {
  local build_number_file="${REPO_ROOT}/.build_number"

  if [[ ! -f "${build_number_file}" ]]; then
    record_fail ".build_number file missing"
    return
  fi

  local value
  value="$(tr -d '[:space:]' < "${build_number_file}")"

  if [[ ! "${value}" =~ ^[0-9]+$ ]] || [[ "${value}" -le 0 ]]; then
    record_fail ".build_number has invalid value '${value}' (expected positive integer)"
    return
  fi

  record_pass ".build_number is valid (${value})"
}

# --- Check: .env.prod required keys ---
check_env_prod() {
  local env_file="${REPO_ROOT}/.env.prod"

  if [[ ! -f "${env_file}" ]]; then
    record_fail ".env.prod file missing"
    return
  fi

  record_pass ".env.prod file present"

  local required_keys=("SUPABASE_URL" "SUPABASE_ANON_KEY")
  for key in "${required_keys[@]}"; do
    local val
    val="$(read_env_value "${env_file}" "${key}")"
    if [[ -z "${val}" ]]; then
      record_fail ".env.prod: ${key} is missing or empty"
    else
      record_pass ".env.prod: ${key} is set"
    fi
  done
}

# --- Check: Mapbox token ---
# Inline check: reads from .env.prod and falls back to .secret/.env.secret.
# Validates pk.* prefix. Does not use resolve_public_runtime_token (which
# depends on a global $secret_file set by the build script's arg parser).
check_mapbox_token() {
  local env_file="${REPO_ROOT}/.env.prod"
  local token=""

  if [[ -f "${env_file}" ]]; then
    token="$(read_env_value_trimmed "${env_file}" "MAPBOX_ACCESS_TOKEN")"
  fi

  # Fallback: check .secret/.env.secret in current repo, then primary checkout.
  if [[ -z "${token}" ]]; then
    local secret_file=""
    if [[ -f "${REPO_ROOT}/.secret/.env.secret" ]]; then
      secret_file="${REPO_ROOT}/.secret/.env.secret"
    elif [[ -f "${primary_repo_root}/.secret/.env.secret" ]]; then
      secret_file="${primary_repo_root}/.secret/.env.secret"
    fi

    if [[ -n "${secret_file}" ]]; then
      token="$(read_env_value_trimmed "${secret_file}" "MAPBOX_ACCESS_TOKEN")"
      if [[ -z "${token}" ]]; then
        token="$(read_env_value_trimmed "${secret_file}" "MAPBOX_DEFAULT_PUBLIC_TOKEN")"
      fi
    fi
  fi

  if [[ -z "${token}" ]]; then
    record_fail "MAPBOX_ACCESS_TOKEN not found in .env.prod or .secret/.env.secret"
    return
  fi

  case "${token}" in
    \<*)
      record_fail "MAPBOX_ACCESS_TOKEN is a placeholder value"
      ;;
    sk.*)
      record_fail "MAPBOX_ACCESS_TOKEN is a secret-scoped token (sk.*), must be public (pk.*)"
      ;;
    pk.*)
      record_pass "MAPBOX_ACCESS_TOKEN is a valid public token (pk.*)"
      ;;
    *)
      record_fail "MAPBOX_ACCESS_TOKEN must start with pk.* for runtime map builds"
      ;;
  esac
}

# --- Check: DeviceCloud smoke stamp ---
check_smoke_stamp() {
  local smoke_stamp="${primary_repo_root}/tmp/devicecloud/last_passed_sha"
  local current_sha
  current_sha="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo "")"

  if [[ ! -f "${smoke_stamp}" ]]; then
    record_warn "DeviceCloud smoke stamp missing (run scripts/dev/run_devicecloud_smoke.sh)"
    return
  fi

  local stamp_sha
  stamp_sha="$(tr -d '[:space:]' < "${smoke_stamp}")"

  if [[ -n "${current_sha}" ]] && [[ -n "${stamp_sha}" ]] && [[ "${stamp_sha}" != "${current_sha}" ]]; then
    record_warn "DeviceCloud smoke stamp is stale (stamp: ${stamp_sha}, HEAD: ${current_sha})"
    return
  fi

  record_pass "DeviceCloud smoke stamp matches HEAD (${stamp_sha})"
}

# --- Check: Firebase configs ---
check_firebase_configs() {
  local ios_config="${REPO_ROOT}/ios/Runner/GoogleService-Info.plist"
  local android_config="${REPO_ROOT}/android/app/google-services.json"

  if [[ -f "${ios_config}" ]]; then
    record_pass "Firebase iOS config: GoogleService-Info.plist"
  else
    record_fail "Firebase iOS config missing: ios/Runner/GoogleService-Info.plist"
  fi

  if [[ -f "${android_config}" ]]; then
    record_pass "Firebase Android config: google-services.json"
  else
    record_fail "Firebase Android config missing: android/app/google-services.json"
  fi
}

# --- Check: checkout weight ---
check_checkout_weight() {
  local heavy_dirs=("data" ".secret" "build")
  local found_heavy=0

  for dir in "${heavy_dirs[@]}"; do
    if [[ -d "${REPO_ROOT}/${dir}" ]]; then
      record_warn "heavyweight checkout: ${dir}/ exists (use a lean worktree for release builds)"
      found_heavy=1
    fi
  done

  if [[ "${found_heavy}" -eq 0 ]]; then
    record_pass "Checkout is lean (no heavy dirs found)"
  fi
}

# --- Run all checks ---
check_build_number
check_env_prod
check_mapbox_token
check_smoke_stamp
check_firebase_configs
check_checkout_weight

print_summary
if [[ "${fail_count}" -gt 0 ]]; then
  exit 1
fi
exit 0
