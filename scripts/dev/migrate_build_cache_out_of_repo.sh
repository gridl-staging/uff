#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
legacy_build_dir="${repo_root}/build"
external_build_dir="$(cd "${repo_root}/.." && pwd)/.uff_dev_build"

if [ ! -e "${legacy_build_dir}" ]; then
  echo "No repo-local build/ directory found. Nothing to migrate."
  exit 0
fi

mkdir -p "$(dirname "${external_build_dir}")"

if [ ! -e "${external_build_dir}" ]; then
  mv "${legacy_build_dir}" "${external_build_dir}"
  echo "Moved ${legacy_build_dir} -> ${external_build_dir}"
  exit 0
fi

archive_dir="${external_build_dir}_legacy_$(date +%Y%m%d_%H%M%S)"
mv "${legacy_build_dir}" "${archive_dir}"
echo "External build cache already exists."
echo "Moved ${legacy_build_dir} -> ${archive_dir}"
