#!/usr/bin/env bash
set -euo pipefail

current_context=""
if command -v docker >/dev/null 2>&1; then
  current_context="$(docker context show 2>/dev/null || true)"
else
  printf 'ERROR: docker CLI is not installed.\n' >&2
  printf 'This repo requires Docker Desktop as the local container engine on macOS.\n' >&2
  exit 1
fi

if [[ "${current_context}" == colima* ]]; then
  printf 'ERROR: Unsupported Docker context: %s\n' "${current_context}" >&2
  printf 'This repo supports Docker Desktop as the only local container engine on macOS.\n' >&2
  printf 'Run: docker context use desktop-linux\n' >&2
  exit 1
fi

docker_info_output="$(mktemp)"
trap 'rm -f "${docker_info_output}"' EXIT

if ! docker info >"${docker_info_output}" 2>&1; then
  printf 'ERROR: Docker Desktop is not ready.\n' >&2
  printf 'Repo-owned local Supabase workflows require docker info to succeed before they start.\n' >&2
  printf 'Start Docker Desktop, wait for the engine to finish booting, then rerun this command.\n' >&2
  printf 'Helpful checks:\n' >&2
  printf '  docker desktop start\n' >&2
  printf '  docker info\n' >&2
  printf '\n' >&2
  cat "${docker_info_output}" >&2
  exit 1
fi

if [[ -n "${current_context}" ]]; then
  printf 'Docker engine ready on context %s.\n' "${current_context}"
else
  printf 'Docker engine ready.\n'
fi
