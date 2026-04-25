#!/usr/bin/env bash
# Shared helpers for parsing feature_test_audit_registry.md headings.

is_registry_non_feature_heading() {
  local heading="$1"
  case "$heading" in
    "Feature Name"|"Why This Exists"|"Audit Levels"|"What An Audit Checks"|"Registry Format"|"Rules")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}
