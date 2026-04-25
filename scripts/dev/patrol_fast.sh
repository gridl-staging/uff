#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/../lib/patrol_cli_workarounds.sh"

# Patrol currently launches xcodebuild through a shell, so we repair the known
# broken escaped OTHER_CFLAGS literal in the globally activated patrol_cli
# source before every run. Keeping the workaround here centralizes the release
# fix in the single repo-owned Patrol entrypoint instead of scattering local
# machine instructions across docs and handoffs.
repair_patrol_cli_ios_inherited_flag_bug
repair_patrol_cli_analytics_version_probe_bug
# Patrol already exposes a built-in escape hatch for completion auto-install.
# Using the official env flag is simpler and safer than patching another
# dependency package in pub-cache, and it keeps automated signoff runs quiet.
export PATROL_NO_COMPLETION=1
export PATROL_FLUTTER_COMMAND="${script_dir}/flutter_fast.sh"
"${script_dir}/with_fast_build_dir.sh" patrol "$@"
