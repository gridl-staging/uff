#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

cd "${repo_root}"

printf '%s\n' "Top-level checkout size snapshot:"
du -sh .[!.]*/ */ 2>/dev/null | sort -h | sed -n '1,200p'

printf '\n%s\n' "Potential iOS build drag:"

if [ -d "data" ]; then
  printf '%s\n' "  - data/ exists. Flutter's recursive xattr sweep will traverse it before every iOS build."
fi

if [ -d ".secret" ]; then
  printf '%s\n' "  - .secret/ exists. Even if it is small, Flutter will still traverse it."
fi

if [ -d "build" ]; then
  printf '%s\n' "  - build/ exists in the repo root. Run ./scripts/dev/migrate_build_cache_out_of_repo.sh if it grows large."
fi

if [ -d ".dart_tool" ]; then
  printf '%s\n' "  - .dart_tool/ exists. This is normal, but it still adds traversal cost."
fi

printf '\n%s\n' "Recommendation:"
printf '%s\n' "  Use ./scripts/dev/flutter_fast.sh and ./scripts/dev/patrol_fast.sh from a clean mobile worktree when possible."
