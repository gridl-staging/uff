#!/usr/bin/env bash
set -euo pipefail

# Run Maestro black-box smoke tests against the installed app.
#
# The app must already be built and installed on a simulator with auto-login
# credentials baked in via dart-define. Maestro flows rely on auto-login,
# not typed credentials.
#
# Prerequisites:
#   - Maestro CLI installed (brew install mobile-dev-inc/tap/maestro)
#   - App built and installed on a simulator (with E2E_AUTO_LOGIN dart-defines)
#   - For notification_smoke flow: app must be built with SKIP_FIREBASE=true
#     (Firebase hangs on iOS simulators with prod config). The flow asserts
#     notification-status-error, which is the expected bootstrap state when
#     Firebase is disabled. run_devicecloud_smoke.sh already builds with this
#     flag (line 151).
#
# Usage:
#   ./scripts/dev/run_maestro_smoke.sh
#   ./scripts/dev/run_maestro_smoke.sh --list-tests
#   ./scripts/dev/run_maestro_smoke.sh --only auth_smoke
#   ./scripts/dev/run_maestro_smoke.sh --tags smoke
#
# Env vars:
#   MAESTRO_DEVICE — target simulator UDID (auto-detected if omitted)

usage() {
  cat <<'EOF' >&2
usage: run_maestro_smoke.sh [options]

Options:
  --device <udid>        Target simulator UDID (auto-detected if omitted)
  --only <flow_name>     Run only this flow (e.g., auth_smoke)
  --tags <t1,t2>         Run only flows with these tags
  --list-tests           Print discovered flows and exit
  --output-dir <path>    Output directory for reports (default: tmp/maestro)
  -h, --help             Show this help
EOF
  exit 64
}

csv_has_tag() {
  local csv_tags="$1"
  local needle="$2"
  local tag=""

  IFS=',' read -r -a parsed_tags <<< "${csv_tags}"
  for tag in "${parsed_tags[@]}"; do
    tag="${tag//[[:space:]]/}"
    if [[ "${tag}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

notification_flow_selected() {
  if [[ -n "${only_flow}" ]]; then
    [[ "${only_flow}" == "notification_smoke" ]]
    return
  fi

  if [[ -n "${tags}" ]]; then
    csv_has_tag "${tags}" "notification" || csv_has_tag "${tags}" "smoke"
    return
  fi

  # Unfiltered runs execute every smoke flow, including notification_smoke.
  return 0
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

# Source deployment_common for env file helpers.
source "${repo_root}/scripts/lib/deployment_common.sh"

device="${MAESTRO_DEVICE:-}"
only_flow=""
tags=""
list_tests=false
output_dir="${repo_root}/tmp/maestro"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)    device="${2:-}"; shift 2 ;;
    --only)      only_flow="${2:-}"; shift 2 ;;
    --tags)      tags="${2:-}"; shift 2 ;;
    --list-tests) list_tests=true; shift ;;
    --output-dir) output_dir="${2:-}"; shift 2 ;;
    -h|--help)   usage ;;
    *)           printf 'Unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done

# --- Preflight checks ---

if ! command -v maestro &>/dev/null; then
  printf 'Maestro CLI not found. Install it:\n' >&2
  printf '  brew tap mobile-dev-inc/tap && brew install mobile-dev-inc/tap/maestro\n' >&2
  printf '  or: curl -fsSL "https://get.maestro.mobile.dev" | bash\n' >&2
  exit 1
fi

if ! command -v java &>/dev/null; then
  printf 'Java not found. Maestro requires Java 17+.\n' >&2
  printf '  brew install openjdk@17\n' >&2
  exit 1
fi

maestro_dir="${repo_root}/.maestro"
if [[ ! -d "${maestro_dir}" ]]; then
  printf '.maestro/ directory not found at %s\n' "${maestro_dir}" >&2
  exit 1
fi

# --- Discover flows ---

if [[ "${list_tests}" == true ]]; then
  printf 'Maestro smoke flows:\n'
  for f in "${maestro_dir}"/smoke/*.yaml; do
    [[ -f "$f" ]] && printf '  %s\n' "$(basename "$f" .yaml)"
  done
  exit 0
fi

# --- Build maestro args ---

maestro_args=()

if [[ -n "${device}" ]]; then
  maestro_args+=(--device "${device}")
fi

maestro_args+=(test)

if [[ -n "${tags}" ]]; then
  maestro_args+=(--include-tags "${tags}")
fi

maestro_args+=(--format JUNIT --test-output-dir "${output_dir}")

# Determine what to run.
if [[ -n "${only_flow}" ]]; then
  flow_file="${maestro_dir}/smoke/${only_flow}.yaml"
  if [[ ! -f "${flow_file}" ]]; then
    printf 'Flow not found: %s\n' "${flow_file}" >&2
    exit 1
  fi
  maestro_args+=("${flow_file}")
else
  maestro_args+=("${maestro_dir}")
fi

# --- Run ---

mkdir -p "${output_dir}"

printf 'Running Maestro smoke tests...\n'
printf 'Output: %s\n' "${output_dir}"
if [[ -n "${device}" ]]; then
  printf 'Device: %s\n' "${device}"
fi
if notification_flow_selected; then
  printf '%s\n' 'NOTE: notification_smoke expects the installed app to be built with SKIP_FIREBASE=true.'
  printf '%s\n' "      Without that build flag, the flow's notification-status-error assertion will fail."
fi
printf '\n'

maestro "${maestro_args[@]}"
exit_code=$?

if [[ "${exit_code}" -eq 0 ]]; then
  printf '\nAll Maestro smoke tests passed.\n'
else
  printf '\nMaestro smoke tests failed (exit %d).\n' "${exit_code}" >&2
fi

exit "${exit_code}"
