#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <flutter-subcommand> [args...]" >&2
  exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
primary_command="$1"
shift

case "${primary_command}" in
  run|test)
    "${script_dir}/flutter_fast.sh" "${primary_command}" --no-pub "$@"
    ;;
  build)
    if [ "$#" -eq 0 ]; then
      echo "usage: $0 build <platform> [args...]" >&2
      exit 64
    fi
    build_platform="$1"
    shift
    "${script_dir}/flutter_fast.sh" build "${build_platform}" --no-pub "$@"
    ;;
  *)
    echo "Unsupported command for --no-pub helper: ${primary_command}" >&2
    echo "Use flutter_fast.sh directly for this command." >&2
    exit 64
    ;;
esac
