#!/usr/bin/env bash

write_interrupting_patrol_fixture() {
  local fixture_root="$1"
  cat > "${fixture_root}/scripts/dev/patrol_fast.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "started" > "${PATROL_STARTED_MARKER}"
sleep 30
exit 0
SCRIPT
  chmod +x "${fixture_root}/scripts/dev/patrol_fast.sh"
}

wait_for_patrol_started() {
  local patrol_started_marker="$1"
  local wait_count
  for wait_count in {1..100}; do
    if [[ -f "${patrol_started_marker}" ]]; then
      break
    fi
    sleep 0.1
  done
  assert_success "fixture patrol invocation starts before forced interruption" \
    test -f "${patrol_started_marker}"
}

parse_interrupted_summary_counts() {
  local json_file="$1"
  python3 - <<'PY' "${json_file}"
import json
import sys

data = json.load(open(sys.argv[1]))
print(data["tests_attempted"])
print(data["tests_passed"])
print(data["tests_failed"])
print(len(data["results"]))
print(data["results"][0]["test"] if data["results"] else "")
PY
}

expected_interrupted_summary_counts() {
  cat <<'EOF'
1
0
1
1
e2e_test/smoke/slow_timeout_test.dart
EOF
}

# TODO: Document test_runner_interrupted_run_expected_to_write_json_summary.
test_runner_interrupted_run_expected_to_write_json_summary() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_runner_fixture "${tmpdir}"
  install_fake_git_short_sha "${tmpdir}"

  setup_e2e_fixture "${tmpdir}" "e2e_test/smoke/slow_timeout_test.dart"
  write_interrupting_patrol_fixture "${tmpdir}"

  local patrol_started_marker="${tmpdir}/patrol_started.txt"
  local output_file="${tmpdir}/runner_output.log"
  local exit_code=0
  (
    cd "${tmpdir}" &&
    PATH="${tmpdir}/bin:${PATH}" PATROL_STARTED_MARKER="${patrol_started_marker}" \
    bash "./scripts/dev/run_ios_signoff_suite.sh" --env dev --device "Fixture iPhone" > "${output_file}" 2>&1
  ) &
  local runner_pid=$!

  wait_for_patrol_started "${patrol_started_marker}"
  kill -TERM "${runner_pid}" 2>/dev/null || true
  wait "${runner_pid}" || exit_code=$?
  assert_success "runner exits non-zero when interrupted mid-run" \
    test "${exit_code}" -ne 0

  local json_file
  json_file="$(ls "${tmpdir}"/tmp/signoff/signoff_*_deadbee.json 2>/dev/null | head -n 1 || true)"
  if [[ -z "${json_file}" ]]; then
    echo "FAIL: runner writes signoff JSON artifact even when interrupted mid-run"
    failures=$((failures + 1))
    rm -rf "${tmpdir}"
    return
  fi

  assert_eq "$(expected_interrupted_summary_counts)" "$(parse_interrupted_summary_counts "${json_file}")" \
    "runner interrupted JSON summary preserves partial result counts"

  local output=""
  output="$(cat "${output_file}")"
  assert_contains "${output}" "JSON report: ${tmpdir}/tmp/signoff/signoff_" \
    "runner prints JSON report path for interrupted run"

  rm -rf "${tmpdir}"
}
