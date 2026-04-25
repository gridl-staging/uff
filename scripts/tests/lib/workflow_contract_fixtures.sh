#!/usr/bin/env bash
# Shared test fixture helpers for workflow-contract registry and archetype catalog generation.
# Sourced by precommit_hook_hardening_test.sh and check_workflow_contracts_test.sh.

trim_whitespace() {
  local raw="$1"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  printf '%s' "$raw"
}

checked_na_reason() {
  local trimmed_evidence="$1"

  if [[ "$trimmed_evidence" != N/A:* ]]; then
    return 1
  fi

  trim_whitespace "${trimmed_evidence#N/A:}"
}

# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
# TODO: Document write_archetype_catalog.
write_archetype_catalog() {
  local tmpdir="$1"
  local archetype_name="$2"
  shift 2

  {
    echo "# ${archetype_name} Archetype"
    echo ""
    echo "| ID | Description | Conditional |"
    echo "| --- | --- | --- |"
    local requirement_id
    for requirement_id in "$@"; do
      echo "| ${requirement_id} | Fixture requirement ${requirement_id} | Always |"
    done
  } > "${tmpdir}/docs/feature_archetypes/${archetype_name}.md"
}

# TODO: Document build_workflow_evidence_stubs.
build_workflow_evidence_stubs() {
  local tmpdir="$1"
  local workflow_lines="$2"

  local workflow_line
  local requirement_path
  local trimmed_requirement_path
  local na_reason
  while IFS= read -r workflow_line; do
    if [[ "${workflow_line}" =~ ^-[[:space:]]\[x\][[:space:]]\`[^\`]+\`[[:space:]]-[[:space:]](.+)$ ]]; then
      requirement_path="${BASH_REMATCH[1]}"
      trimmed_requirement_path="$(trim_whitespace "${requirement_path}")"
      if [[ "${trimmed_requirement_path}" == N/A:* ]]; then
        na_reason="$(checked_na_reason "${trimmed_requirement_path}")"
        if [[ -n "${na_reason}" ]]; then
          continue
        fi
      fi
      if [[ "${trimmed_requirement_path}" != "NOT_IMPLEMENTED" ]] && [[ "${trimmed_requirement_path}" != DEFERRED:* ]]; then
        mkdir -p "${tmpdir}/$(dirname "${trimmed_requirement_path}")"
        printf '%s\n' "fixture evidence" > "${tmpdir}/${trimmed_requirement_path}"
      fi
    fi
  done <<< "${workflow_lines}"
}
