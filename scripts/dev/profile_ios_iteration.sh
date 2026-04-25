#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'EOF'
usage: profile_ios_iteration.sh [ios-simulator-device-id]

Profiles the current iOS iteration path by timing:
  1. flutter build ios --config-only --debug --simulator
  2. xcodebuild with -showBuildTimingSummary

If no simulator device id is provided, the script boots or reuses the
worktree-specific simulator from ensure_worktree_ios_simulator.sh.
EOF
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
# shellcheck source=/dev/null
source "${repo_root}/scripts/lib/simulator_control.sh"
worktree_hash="$(
  REPO_ROOT="${repo_root}" python3 - <<'PY'
import hashlib
import os

print(hashlib.sha1(os.path.realpath(os.environ["REPO_ROOT"]).encode()).hexdigest()[:12])
PY
)"
tooling_root="$(cd "${repo_root}/.." && pwd)/.uff_dev_tooling/${worktree_hash}"
log_root="${tooling_root}/logs"
timestamp="$(date +%Y%m%d_%H%M%S)"
flutter_log="${log_root}/flutter_config_only_${timestamp}.log"
xcode_log="${log_root}/xcode_build_${timestamp}.log"

mkdir -p "${log_root}"

helper_owned_simulator_udid=""
helper_owned_simulator_booted_by_this_run="false"

cleanup_profile_run() {
  shutdown_simulator_if_owned "${helper_owned_simulator_udid}" "${helper_owned_simulator_booted_by_this_run}"
}

trap cleanup_profile_run EXIT

if [[ $# -gt 0 ]]; then
  device_id="${1}"
else
  simulator_metadata="$(resolve_worktree_simulator_metadata "${script_dir}/ensure_worktree_ios_simulator.sh")"
  device_id="$(simulator_metadata_field "${simulator_metadata}" "udid")"
  helper_owned_simulator_udid="${device_id}"
  helper_owned_simulator_booted_by_this_run="$(simulator_metadata_field "${simulator_metadata}" "booted_by_this_run")"
fi

cd "${repo_root}"

echo "Profiling flutter config-only step..."
/usr/bin/time -lp "${script_dir}/flutter_fast_nopub.sh" \
  build ios --config-only --no-codesign --debug --simulator --target lib/main.dart \
  >"${flutter_log}" 2>&1
tail -n 20 "${flutter_log}"

echo
echo "Profiling xcodebuild with build timing summary..."
/usr/bin/time -lp \
  xcodebuild \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination "id=${device_id}" \
    -showBuildTimingSummary \
    build \
  >"${xcode_log}" 2>&1

echo
echo "Build timing summary:"
sed -n '/Build Timing Summary/,$p' "${xcode_log}" | sed -n '1,120p'

echo
echo "Logs saved to:"
echo "  ${flutter_log}"
echo "  ${xcode_log}"
