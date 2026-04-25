#!/usr/bin/env bash
set -euo pipefail

# Run Maestro smoke tests on DeviceCloud.dev cloud simulators.
#
# Builds a debug simulator .app, zips it, provisions a throwaway test user,
# and uploads everything to DeviceCloud for parallel execution.
#
# Prerequisites:
#   - dcd CLI installed (npm install -g @devicecloud.dev/dcd)
#   - Flutter SDK available
#   - DEVICE_CLOUD_API_KEY set in env or .secret/.env.secret
#
# Usage:
#   ./scripts/dev/run_devicecloud_smoke.sh
#   ./scripts/dev/run_devicecloud_smoke.sh --skip-build          # reuse last .app
#   ./scripts/dev/run_devicecloud_smoke.sh --ios-device iphone-16-pro --ios-version 18
#   ./scripts/dev/run_devicecloud_smoke.sh --include-tags auth   # run only auth flows
#   ./scripts/dev/run_devicecloud_smoke.sh --async               # return immediately

# TODO: Document usage.
usage() {
  cat <<'EOF' >&2
usage: run_devicecloud_smoke.sh [options]

Options:
  --skip-build             Reuse the existing simulator .app (skip flutter build)
  --ios-device <device>    Target device (default: iphone-16-pro)
  --ios-version <ver>      iOS version (default: 18)
  --include-tags <t1,t2>   Run only flows with these tags
  --exclude-tags <t1,t2>   Exclude flows with these tags
  --async                  Return immediately without waiting for results
  --retry <n>              Auto-retry failed flows up to n times (free on DCD)
  --name <label>           Custom run name (default: uff-smoke-<git-sha>)
  --download-artifacts     Download artifacts for failed flows
  --email <addr>           Explicit test email for build (skips auto-provisioning)
  --password <pass>        Explicit test password for build (skips auto-provisioning)
  -h, --help               Show this help
EOF
  exit 64
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
source "${repo_root}/scripts/lib/deployment_common.sh"

# --- Defaults ---
skip_build=false
ios_device="iphone-16-pro"
ios_version="18"
include_tags=""
exclude_tags=""
async_mode=false
retry_count=""
run_name=""
download_artifacts=false
explicit_email=""
explicit_password=""
output_dir="${repo_root}/tmp/devicecloud"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)       skip_build=true; shift ;;
    --ios-device)       ios_device="${2:-}"; shift 2 ;;
    --ios-version)      ios_version="${2:-}"; shift 2 ;;
    --include-tags)     include_tags="${2:-}"; shift 2 ;;
    --exclude-tags)     exclude_tags="${2:-}"; shift 2 ;;
    --async)            async_mode=true; shift ;;
    --retry)            retry_count="${2:-}"; shift 2 ;;
    --name)             run_name="${2:-}"; shift 2 ;;
    --download-artifacts) download_artifacts=true; shift ;;
    --email)            explicit_email="${2:-}"; shift 2 ;;
    --password)         explicit_password="${2:-}"; shift 2 ;;
    -h|--help)          usage ;;
    *)                  printf 'Unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done

# --- Preflight ---

if ! command -v dcd &>/dev/null; then
  printf 'dcd CLI not found. Install it:\n' >&2
  printf '  npm install -g @devicecloud.dev/dcd\n' >&2
  exit 1
fi

maestro_dir="${repo_root}/.maestro"
if [[ ! -d "${maestro_dir}" ]]; then
  printf '.maestro/ directory not found.\n' >&2
  exit 1
fi

# --- Resolve DeviceCloud API key ---

# The dcd CLI reads the env var DEVICE_CLOUD_API_KEY (with underscores).
# The secret file stores it as DEVICECLOUD_API_KEY (no underscores).
api_key="${DEVICE_CLOUD_API_KEY:-}"
if [[ -z "${api_key}" ]]; then
  secret_file="${repo_root}/.secret/.env.secret"
  if [[ -f "${secret_file}" ]]; then
    api_key="$(read_env_value "${secret_file}" "DEVICECLOUD_API_KEY")" || true
  fi
fi

if [[ -z "${api_key}" ]]; then
  printf 'DEVICE_CLOUD_API_KEY not set and DEVICECLOUD_API_KEY not found in .secret/.env.secret.\n' >&2
  exit 1
fi

export DEVICE_CLOUD_API_KEY="${api_key}"

# --- Build simulator .app ---
# The app is built with:
#   APP_ENV=prod           — use production Supabase backend
#   SKIP_FIREBASE=true     — Firebase hangs on iOS simulator with prod config
#   E2E_REPLAY_TRACKING=true — replaces live GPS with deterministic replay data
#   E2E_AUTO_LOGIN_EMAIL/PASSWORD — auto-sign-in during bootstrap, before the
#     widget tree renders. Cleaner than UI login and avoids auth stream
#     timing edge cases.
#
# Credentials are baked into the app binary via dart-define. Maestro flows
# do NOT read credentials from environment variables — they rely on the
# app's auto-login to reach the home screen.

app_dir="${repo_root}/build/ios/iphonesimulator"
app_path="${app_dir}/Runner.app"
app_zip="${app_dir}/Runner.app.zip"

if [[ "${skip_build}" == true ]]; then
  if [[ ! -d "${app_path}" ]]; then
    printf 'No existing .app found at %s. Remove --skip-build.\n' "${app_path}" >&2
    exit 1
  fi
  printf 'Reusing existing simulator build at %s\n' "${app_path}"
else
  # Provision a throwaway test user for auto-login dart-defines.
  email="${explicit_email}"
  password="${explicit_password}"

  if [[ -z "${email}" || -z "${password}" ]]; then
    printf 'Provisioning throwaway hosted test user...\n'
    eval "$("${script_dir}/prepare_hosted_test_user.sh" --env prod)"
    email="${E2E_TEST_EMAIL}"
    password="${E2E_TEST_PASSWORD}"
    printf 'Test user: %s\n' "${email}"
  fi

  printf 'Building iOS simulator app (debug + prod env + auto-login)...\n'
  cd "${repo_root}"
  flutter build ios --debug --simulator \
    --dart-define=APP_ENV=prod \
    --dart-define=SKIP_FIREBASE=true \
    --dart-define=E2E_REPLAY_TRACKING=true \
    --dart-define=E2E_REPLAY_EMISSION_INTERVAL_MS=50 \
    --dart-define="E2E_AUTO_LOGIN_EMAIL=${email}" \
    --dart-define="E2E_AUTO_LOGIN_PASSWORD=${password}"
  printf 'Build complete.\n'
fi

# Zip the .app bundle for upload.
printf 'Zipping %s...\n' "${app_path}"
(cd "${app_dir}" && rm -f Runner.app.zip && zip -r -q Runner.app.zip Runner.app)
printf 'Created %s\n' "${app_zip}"

# --- Build dcd args ---

git_sha="$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || echo "unknown")"
if [[ -z "${run_name}" ]]; then
  run_name="uff-smoke-${git_sha}"
fi

mkdir -p "${output_dir}"

# NOTE: Do NOT use --json-file here. The dcd CLI forces exit code 0 when
# --json-file is enabled, making it impossible to detect failures via exit code.
# We use --report junit instead (preserves exit codes).
dcd_args=(
  cloud
  --app-file "${app_zip}"
  --flows "${maestro_dir}"
  --ios-device "${ios_device}"
  --ios-version "${ios_version}"
  --name "${run_name}"
  --commit-sha "${git_sha}"
  --report junit --junit-path "${output_dir}/report.xml"
)

if [[ -n "${include_tags}" ]]; then
  dcd_args+=(--include-tags "${include_tags}")
fi

if [[ -n "${exclude_tags}" ]]; then
  dcd_args+=(--exclude-tags "${exclude_tags}")
fi

if [[ "${async_mode}" == true ]]; then
  dcd_args+=(--async)
fi

if [[ -n "${retry_count}" ]]; then
  dcd_args+=(--retry "${retry_count}")
fi

if [[ "${download_artifacts}" == true ]]; then
  dcd_args+=(--download-artifacts FAILED --artifacts-path "${output_dir}/artifacts.zip")
fi

# --- Run ---

printf '\n'
printf '=== DeviceCloud Smoke Run ===\n'
printf 'Device:  %s (iOS %s)\n' "${ios_device}" "${ios_version}"
printf 'Commit:  %s\n' "${git_sha}"
printf 'Name:    %s\n' "${run_name}"
printf 'Output:  %s\n' "${output_dir}"
printf '\n'

dcd "${dcd_args[@]}"
exit_code=$?

if [[ "${exit_code}" -eq 0 ]]; then
  # Write a stamp file recording the passing commit SHA. The build script
  # (build_testflight_release.sh) checks this to gate release builds on
  # passing DeviceCloud smoke tests.
  printf '%s\n' "${git_sha}" > "${output_dir}/last_passed_sha"
  printf '\nAll DeviceCloud smoke tests passed.\n'
  printf 'JUnit:   %s/report.xml\n' "${output_dir}"
  printf 'Stamp:   %s/last_passed_sha\n' "${output_dir}"
else
  printf '\nDeviceCloud smoke tests failed (exit %d).\n' "${exit_code}" >&2
  printf 'JUnit:   %s/report.xml\n' "${output_dir}" >&2
  if [[ "${download_artifacts}" == true ]]; then
    printf 'Artifacts: %s/artifacts.zip\n' "${output_dir}" >&2
  fi
fi

exit "${exit_code}"
