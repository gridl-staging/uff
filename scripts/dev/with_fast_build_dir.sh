#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
fast_build_dir_rel="../.uff_dev_build"
fast_build_dir_abs="$(cd "${repo_root}/.." && pwd)/.uff_dev_build"

# Flutter only exposes build-dir through `flutter config`, which is otherwise
# machine-global. Isolating XDG config per worktree keeps parallel worktrees and
# unrelated Flutter projects from stomping each other's settings.
worktree_hash="$(
  REPO_ROOT="${repo_root}" python3 - <<'PY'
import hashlib
import os

print(hashlib.sha1(os.path.realpath(os.environ["REPO_ROOT"]).encode()).hexdigest()[:12])
PY
)"
tooling_root="$(cd "${repo_root}/.." && pwd)/.uff_dev_tooling/${worktree_hash}"
flutter_config_root="${tooling_root}/xdg"
shared_build_lock_hash="$(
  FAST_BUILD_DIR="${fast_build_dir_abs}" python3 - <<'PY'
import hashlib
import os

print(hashlib.sha1(os.path.realpath(os.environ["FAST_BUILD_DIR"]).encode()).hexdigest()[:12])
PY
)"
shared_build_lock_dir="$(cd "${repo_root}/.." && pwd)/.uff_dev_tooling/shared_build_lock_${shared_build_lock_hash}"
shared_build_lock_pid_file="${shared_build_lock_dir}/pid"
shared_build_lock_repo_file="${shared_build_lock_dir}/repo_root"
shared_build_lock_owner_pid="${UFF_SHARED_BUILD_LOCK_OWNER_PID:-}"
shared_build_lock_owner_dir="${UFF_SHARED_BUILD_LOCK_DIR:-}"
lock_acquired=false

cleanup_shared_build_lock() {
  if [[ "${lock_acquired}" != true ]]; then
    return 0
  fi

  rm -f "${shared_build_lock_pid_file}" "${shared_build_lock_repo_file}"
  rmdir "${shared_build_lock_dir}" 2>/dev/null || true
}

current_process_descends_from_pid() {
  local candidate_pid="$1"
  local ancestor_pid="$2"
  local parent_pid=""

  while [[ -n "${candidate_pid}" && "${candidate_pid}" != "0" ]]; do
    if [[ "${candidate_pid}" == "${ancestor_pid}" ]]; then
      return 0
    fi
    parent_pid="$(ps -o ppid= -p "${candidate_pid}" 2>/dev/null | tr -d '[:space:]')"
    if [[ -z "${parent_pid}" || "${parent_pid}" == "${candidate_pid}" ]]; then
      break
    fi
    candidate_pid="${parent_pid}"
  done

  return 1
}

acquire_shared_build_lock() {
  local holder_pid=""
  local holder_repo=""

  # Patrol delegates back into the repo-owned Flutter wrapper while a top-level
  # patrol_fast/with_fast_build_dir invocation is still active. Those nested
  # calls must reuse the same shared-build lock instead of tripping the
  # cross-worktree protection that guards genuinely concurrent runners.
  if [[ "${shared_build_lock_owner_dir}" == "${shared_build_lock_dir}" &&
        -n "${shared_build_lock_owner_pid}" &&
        -f "${shared_build_lock_pid_file}" ]]; then
    holder_pid="$(tr -d '[:space:]' < "${shared_build_lock_pid_file}")"
    if [[ "${holder_pid}" == "${shared_build_lock_owner_pid}" ]]; then
      return 0
    fi
  fi

  if mkdir "${shared_build_lock_dir}" 2>/dev/null; then
    printf '%s\n' "$$" > "${shared_build_lock_pid_file}"
    printf '%s\n' "${repo_root}" > "${shared_build_lock_repo_file}"
    lock_acquired=true
    return 0
  fi

  if [[ -f "${shared_build_lock_pid_file}" ]]; then
    holder_pid="$(tr -d '[:space:]' < "${shared_build_lock_pid_file}")"
  fi
  if [[ -f "${shared_build_lock_repo_file}" ]]; then
    holder_repo="$(tr -d '\n' < "${shared_build_lock_repo_file}")"
  fi

  # The fast build dir is shared across sibling worktrees on purpose for speed,
  # so we fail fast when another live process already owns it. Reusing that
  # directory concurrently can make Patrol execute a bundle generated for a
  # different test file or worktree, which produces misleading "passes."
  if [[ -n "${holder_pid}" ]] && kill -0 "${holder_pid}" 2>/dev/null; then
    # Patrol can invoke the repo-owned flutter wrapper from a nested child
    # process without preserving the owner env vars. In that case the current
    # shell is still a descendant of the original lock holder, so it is safe to
    # reuse the shared build dir instead of treating the parent runner as a
    # concurrent cross-worktree conflict.
    if [[ "${holder_repo}" == "${repo_root}" ]] &&
       current_process_descends_from_pid "$$" "${holder_pid}"; then
      return 0
    fi
    printf '%s\n' \
      "Shared Flutter build dir ${fast_build_dir_abs} is already in use by PID ${holder_pid}${holder_repo:+ (${holder_repo})}. Stop the other runner before starting another." >&2
    exit 73
  fi

  rm -f "${shared_build_lock_pid_file}" "${shared_build_lock_repo_file}"
  rmdir "${shared_build_lock_dir}" 2>/dev/null || true

  if ! mkdir "${shared_build_lock_dir}" 2>/dev/null; then
    printf '%s\n' \
      "Unable to acquire shared Flutter build lock for ${fast_build_dir_abs}." >&2
    exit 73
  fi

  printf '%s\n' "$$" > "${shared_build_lock_pid_file}"
  printf '%s\n' "${repo_root}" > "${shared_build_lock_repo_file}"
  lock_acquired=true
}

cd "${repo_root}"
mkdir -p "${flutter_config_root}"
trap cleanup_shared_build_lock EXIT
acquire_shared_build_lock
export UFF_SHARED_BUILD_LOCK_OWNER_PID="${shared_build_lock_owner_pid:-$$}"
export UFF_SHARED_BUILD_LOCK_DIR="${shared_build_lock_dir}"
export XDG_CONFIG_HOME="${flutter_config_root}"
# Prevent actool/ibtool deadlock on the shared IBCLIServer pipe registry.
# Orphaned actool processes from prior builds leave the registry lock poisoned;
# this flag tells actool to skip the shared registry and spawn a fresh server.
export IBCLIServerNeverDequeue=1
flutter config --build-dir="${fast_build_dir_rel}" >/dev/null
"$@"
