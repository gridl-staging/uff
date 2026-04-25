#!/usr/bin/env bash
set -euo pipefail

invalidate_global_patrol_snapshot() {
  local global_bin_dir="$1"

  if [[ ! -d "${global_bin_dir}" ]]; then
    return 0
  fi

  local snapshot_glob
  for snapshot_glob in "${global_bin_dir}"/main.dart-*.snapshot; do
    [[ -f "${snapshot_glob}" ]] || continue
    rm -f "${snapshot_glob}"
  done
}

# repair_patrol_cli_ios_inherited_flag_bug patches the globally activated
# patrol_cli source if it still ships the known-bad escaped OTHER_CFLAGS value.
# The broken source renders as '\$(inherited)' in Dart, which survives badly
# enough through Patrol's shell-based xcodebuild launch to land in generated
# response files as an ESC-prefixed token on this host. That breaks clang
# before any Patrol test logic runs. The fixed form must still keep Dart's
# later ${...} interpolations for FULL_ISOLATION and CLEAR_PERMISSIONS, so we
# rewrite the line into adjacent string literals instead of naively removing
# the backslash. We keep the change idempotent and delete the stale global
# snapshot so Patrol recompiles from the repaired source on the next run.
repair_patrol_cli_ios_inherited_flag_bug() {
  local pub_cache_root="${1:-${HOME}/.pub-cache}"
  local hosted_root="${pub_cache_root}/hosted/pub.dev"
  local global_bin_dir="${pub_cache_root}/global_packages/patrol_cli/bin"
  local patrol_source_file=""
  local repaired_any_file=false
  local broken_escaped_literal="'OTHER_CFLAGS=\\\$(inherited) -D FULL_ISOLATION=\${fullIsolation ? 1 : 0} -D CLEAR_PERMISSIONS=\${clearIOSPermissions ? 1 : 0}',"
  local invalid_unescaped_literal="'OTHER_CFLAGS=\$(inherited) -D FULL_ISOLATION=\${fullIsolation ? 1 : 0} -D CLEAR_PERMISSIONS=\${clearIOSPermissions ? 1 : 0}',"
  local fixed_literal="'OTHER_CFLAGS=' r'\$(inherited)' ' -D FULL_ISOLATION=\${fullIsolation ? 1 : 0} -D CLEAR_PERMISSIONS=\${clearIOSPermissions ? 1 : 0}',"

  if [[ ! -d "${hosted_root}" ]]; then
    return 0
  fi

  local source_glob
  for source_glob in "${hosted_root}"/patrol_cli-*/lib/src/crossplatform/app_options.dart; do
    [[ -f "${source_glob}" ]] || continue

    if ! grep -Fq "${broken_escaped_literal}" "${source_glob}" && ! grep -Fq "${invalid_unescaped_literal}" "${source_glob}"; then
      continue
    fi

    python3 - "${source_glob}" "${broken_escaped_literal}" "${invalid_unescaped_literal}" "${fixed_literal}" <<'PY'
import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
broken_escaped = sys.argv[2]
invalid_unescaped = sys.argv[3]
fixed = sys.argv[4]

contents = source_path.read_text()
updated = contents.replace(broken_escaped, fixed).replace(invalid_unescaped, fixed)
source_path.write_text(updated)
PY
    patrol_source_file="${source_glob}"
    repaired_any_file=true
  done

  if [[ "${repaired_any_file}" != true ]]; then
    return 0
  fi

  invalidate_global_patrol_snapshot "${global_bin_dir}"

  printf '%s\n' "Patrol CLI iOS build-flag workaround applied: ${patrol_source_file}" >&2
}

# Patrol depends on cli_completion, whose CompletionCommandRunner auto-installs
# completion files on every command. On this host that startup path prints
# shell instructions to stdout before Patrol reaches the requested subcommand,
# which then corrupts Patrol's own analytics Flutter-version probe. Disabling
# auto-install in the installed cli_completion source keeps automated wrappers
# quiet and deterministic while still letting humans install completion
# manually if they ever want it.
repair_patrol_cli_completion_autoinstall_bug() {
  local pub_cache_root="${1:-${HOME}/.pub-cache}"
  local hosted_root="${pub_cache_root}/hosted/pub.dev"
  local global_bin_dir="${pub_cache_root}/global_packages/patrol_cli/bin"
  local completion_runner_file=""
  local repaired_any_file=false
  local broken_literal="bool get enableAutoInstall => true;"
  local fixed_literal="bool get enableAutoInstall => false;"

  if [[ ! -d "${hosted_root}" ]]; then
    return 0
  fi

  local source_glob
  for source_glob in "${hosted_root}"/cli_completion-*/lib/src/command_runner/completion_command_runner.dart; do
    [[ -f "${source_glob}" ]] || continue

    if ! grep -Fq "${broken_literal}" "${source_glob}"; then
      continue
    fi

    python3 - "${source_glob}" "${broken_literal}" "${fixed_literal}" <<'PY'
import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
broken = sys.argv[2]
fixed = sys.argv[3]

contents = source_path.read_text()
source_path.write_text(contents.replace(broken, fixed))
PY
    completion_runner_file="${source_glob}"
    repaired_any_file=true
  done

  if [[ "${repaired_any_file}" != true ]]; then
    return 0
  fi

  invalidate_global_patrol_snapshot "${global_bin_dir}"

  printf '%s\n' "Patrol CLI completion auto-install workaround applied: ${completion_runner_file}" >&2
}

# Patrol's `test` command computes analytics metadata by shelling out to the
# configured Flutter command for `--version --machine`. On this host that probe
# is brittle enough to throw before any real test work begins, which makes the
# entire command unusable even though the analytics payload is non-essential.
# Replacing the probe with Patrol's built-in test FlutterVersion keeps the
# command deterministic without touching any app-facing behavior.
repair_patrol_cli_analytics_version_probe_bug() {
  local pub_cache_root="${1:-${HOME}/.pub-cache}"
  local hosted_root="${pub_cache_root}/hosted/pub.dev"
  local global_bin_dir="${pub_cache_root}/global_packages/patrol_cli/bin"
  local patrol_test_command_file=""
  local repaired_any_file=false
  local broken_literal="_analytics.sendCommand(FlutterVersion.fromCLI(flutterCommand), name)"
  local fixed_literal="_analytics.sendCommand(FlutterVersion.test(), name)"

  if [[ ! -d "${hosted_root}" ]]; then
    return 0
  fi

  local source_glob
  for source_glob in "${hosted_root}"/patrol_cli-*/lib/src/commands/test.dart; do
    [[ -f "${source_glob}" ]] || continue

    if ! grep -Fq "${broken_literal}" "${source_glob}"; then
      continue
    fi

    python3 - "${source_glob}" "${broken_literal}" "${fixed_literal}" <<'PY'
import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
broken = sys.argv[2]
fixed = sys.argv[3]

contents = source_path.read_text()
source_path.write_text(contents.replace(broken, fixed))
PY
    patrol_test_command_file="${source_glob}"
    repaired_any_file=true
  done

  if [[ "${repaired_any_file}" != true ]]; then
    return 0
  fi

  invalidate_global_patrol_snapshot "${global_bin_dir}"

  printf '%s\n' "Patrol CLI analytics version-probe workaround applied: ${patrol_test_command_file}" >&2
}
