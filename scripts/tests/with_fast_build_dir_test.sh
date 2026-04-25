#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
failures=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [[ "${expected}" != "${actual}" ]]; then
    echo "FAIL: ${description} (expected '${expected}', got '${actual}')"
    failures=$((failures + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "FAIL: ${description} (missing '${needle}')"
    failures=$((failures + 1))
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    echo "FAIL: ${description} (should not contain '${needle}')"
    failures=$((failures + 1))
  fi
}

assert_success() {
  local description="$1"
  shift
  if "$@"; then
    return 0
  fi
  echo "FAIL: ${description} (command failed)"
  failures=$((failures + 1))
}

setup_fixture() {
  local fixture_root="$1"
  mkdir -p "${fixture_root}/scripts/dev" "${fixture_root}/bin"
  cp "${REPO_ROOT}/scripts/dev/with_fast_build_dir.sh" "${fixture_root}/scripts/dev/"

  cat > "${fixture_root}/bin/flutter" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${MOCK_FLUTTER_ARGS_FILE}"
exit 0
SCRIPT
  chmod +x "${fixture_root}/bin/flutter"
}

shared_lock_dir_for_fixture() {
  local fixture_root="$1"
  FIXTURE_ROOT="${fixture_root}" python3 - <<'PY'
import hashlib
import os

fixture_root = os.path.realpath(os.environ["FIXTURE_ROOT"])
fast_build_dir = os.path.realpath(os.path.join(fixture_root, "..", ".uff_dev_build"))
lock_hash = hashlib.sha1(fast_build_dir.encode()).hexdigest()[:12]
print(os.path.join(os.path.dirname(fixture_root), ".uff_dev_tooling", f"shared_build_lock_{lock_hash}"))
PY
}

test_acquires_lock_runs_command_and_cleans_up() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_fixture "${tmpdir}"

  local marker_file="${tmpdir}/command_ran.txt"
  local flutter_args_file="${tmpdir}/flutter_args.txt"
  local lock_dir
  lock_dir="$(shared_lock_dir_for_fixture "${tmpdir}")"

  (
    cd "${tmpdir}" &&
    PATH="${tmpdir}/bin:${PATH}" MOCK_FLUTTER_ARGS_FILE="${flutter_args_file}" \
      bash "./scripts/dev/with_fast_build_dir.sh" bash -lc "printf '%s\n' yes > '${marker_file}'"
  )

  assert_eq "yes" "$(cat "${marker_file}")" \
    "with_fast_build_dir runs the wrapped command after configuring Flutter"
  assert_contains "$(cat "${flutter_args_file}")" "config --build-dir=../.uff_dev_build" \
    "with_fast_build_dir configures the shared fast build directory"
  assert_success "with_fast_build_dir removes the shared build lock after success" \
    test ! -d "${lock_dir}"

  rm -rf "${tmpdir}"
}

test_live_lock_holder_fails_fast_without_running_command() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_fixture "${tmpdir}"

  local marker_file="${tmpdir}/command_ran.txt"
  local flutter_args_file="${tmpdir}/flutter_args.txt"
  local lock_dir
  lock_dir="$(shared_lock_dir_for_fixture "${tmpdir}")"
  mkdir -p "${lock_dir}"

  sleep 30 &
  local holder_pid=$!
  printf '%s\n' "${holder_pid}" > "${lock_dir}/pid"
  printf '%s\n' "/tmp/other_worktree" > "${lock_dir}/repo_root"

  local output=""
  local exit_code=0
  output="$(
    cd "${tmpdir}" &&
    PATH="${tmpdir}/bin:${PATH}" MOCK_FLUTTER_ARGS_FILE="${flutter_args_file}" \
      bash "./scripts/dev/with_fast_build_dir.sh" bash -lc "printf '%s\n' no > '${marker_file}'" 2>&1
  )" || exit_code=$?

  kill "${holder_pid}" 2>/dev/null || true
  wait "${holder_pid}" 2>/dev/null || true

  assert_eq "73" "${exit_code}" \
    "with_fast_build_dir exits with a clear failure code when another live process owns the shared build dir"
  assert_contains "${output}" "Shared Flutter build dir" \
    "with_fast_build_dir explains why it refused to start"
  assert_contains "${output}" "${holder_pid}" \
    "with_fast_build_dir reports the blocking holder PID"
  assert_success "with_fast_build_dir does not run the wrapped command while a live lock holder exists" \
    test ! -f "${marker_file}"
  assert_not_contains "$(cat "${flutter_args_file}" 2>/dev/null || true)" "config --build-dir=../.uff_dev_build" \
    "with_fast_build_dir fails before invoking flutter config when the lock is live"

  rm -rf "${tmpdir}"
}

test_stale_lock_is_reclaimed() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_fixture "${tmpdir}"

  local marker_file="${tmpdir}/command_ran.txt"
  local flutter_args_file="${tmpdir}/flutter_args.txt"
  local lock_dir
  lock_dir="$(shared_lock_dir_for_fixture "${tmpdir}")"
  mkdir -p "${lock_dir}"
  printf '%s\n' "999999" > "${lock_dir}/pid"
  printf '%s\n' "/tmp/stale_worktree" > "${lock_dir}/repo_root"

  (
    cd "${tmpdir}" &&
    PATH="${tmpdir}/bin:${PATH}" MOCK_FLUTTER_ARGS_FILE="${flutter_args_file}" \
      bash "./scripts/dev/with_fast_build_dir.sh" bash -lc "printf '%s\n' reclaimed > '${marker_file}'"
  )

  assert_eq "reclaimed" "$(cat "${marker_file}")" \
    "with_fast_build_dir reclaims a stale shared build lock"
  assert_success "with_fast_build_dir removes the reclaimed lock after success" \
    test ! -d "${lock_dir}"

  rm -rf "${tmpdir}"
}

test_reentrant_invocation_reuses_same_lock() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_fixture "${tmpdir}"

  local flutter_args_file="${tmpdir}/flutter_args.txt"
  local outer_marker="${tmpdir}/outer.txt"
  local inner_marker="${tmpdir}/inner.txt"
  local lock_dir
  lock_dir="$(shared_lock_dir_for_fixture "${tmpdir}")"

  (
    cd "${tmpdir}" &&
    PATH="${tmpdir}/bin:${PATH}" MOCK_FLUTTER_ARGS_FILE="${flutter_args_file}" \
      bash "./scripts/dev/with_fast_build_dir.sh" bash -lc \
      "printf '%s\n' outer > '${outer_marker}' && ./scripts/dev/with_fast_build_dir.sh bash -lc \"printf '%s\n' inner > '${inner_marker}'\""
  )

  assert_eq "outer" "$(cat "${outer_marker}")" \
    "with_fast_build_dir runs the outer command in a reentrant scenario"
  assert_eq "inner" "$(cat "${inner_marker}")" \
    "with_fast_build_dir lets nested same-owner calls reuse the shared build lock"
  assert_success "with_fast_build_dir still cleans the lock after nested reuse succeeds" \
    test ! -d "${lock_dir}"

  rm -rf "${tmpdir}"
}

test_descendant_reentry_without_owner_env_reuses_same_lock() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_fixture "${tmpdir}"

  local outer_marker="${tmpdir}/outer.txt"
  local inner_marker="${tmpdir}/inner.txt"
  local flutter_args_file="${tmpdir}/flutter_args.txt"
  local lock_dir
  lock_dir="$(shared_lock_dir_for_fixture "${tmpdir}")"

  (
    cd "${tmpdir}" &&
    PATH="${tmpdir}/bin:${PATH}" MOCK_FLUTTER_ARGS_FILE="${flutter_args_file}" \
      bash "./scripts/dev/with_fast_build_dir.sh" bash -lc \
      "printf '%s\n' outer > '${outer_marker}' && env -u UFF_SHARED_BUILD_LOCK_OWNER_PID -u UFF_SHARED_BUILD_LOCK_DIR ./scripts/dev/with_fast_build_dir.sh bash -lc \"printf '%s\n' inner > '${inner_marker}'\""
  )

  assert_eq "outer" "$(cat "${outer_marker}")" \
    "with_fast_build_dir runs the outer command before descendant reentry"
  assert_eq "inner" "$(cat "${inner_marker}")" \
    "with_fast_build_dir lets same-process-tree descendants reuse the lock even when owner env vars are missing"
  assert_success "with_fast_build_dir still cleans the shared lock after descendant reentry succeeds" \
    test ! -d "${lock_dir}"

  rm -rf "${tmpdir}"
}

main() {
  test_acquires_lock_runs_command_and_cleans_up
  test_live_lock_holder_fails_fast_without_running_command
  test_stale_lock_is_reclaimed
  test_reentrant_invocation_reuses_same_lock
  test_descendant_reentry_without_owner_env_reuses_same_lock

  if [[ "${failures}" -ne 0 ]]; then
    echo "with_fast_build_dir_test: ${failures} failure(s)"
    exit 1
  fi

  echo "with_fast_build_dir_test: PASS"
}

main "$@"
