#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for JSON parsing." >&2
  exit 1
fi

if [[ -z "${SUPABASE_URL:-}" ]]; then
  echo "ERROR: SUPABASE_URL is required." >&2
  exit 1
fi

API_KEY="${SUPABASE_SERVICE_ROLE_KEY:-}"
if [[ -z "$API_KEY" ]]; then
  echo "ERROR: set SUPABASE_SERVICE_ROLE_KEY." >&2
  exit 1
fi

BASE_URL="${SUPABASE_URL%/}"
FUNCTION_URL="${BASE_URL}/functions/v1/discover-clubs"

CITIES=(
  "Portland|OR"
  "Austin|TX"
  "New York|NY"
  "Chicago|IL"
  "Denver|CO"
)

for entry in "${CITIES[@]}"; do
  IFS='|' read -r city state_region <<<"$entry"
  encoded_city="$(printf '%s' "$city" | jq -sRr @uri)"
  encoded_state="$(printf '%s' "$state_region" | jq -sRr @uri)"

  response_file="$(mktemp)"
  http_status="$(curl -sS -o "$response_file" -w '%{http_code}' -X POST \
    -H "apikey: ${API_KEY}" \
    -H "Authorization: Bearer ${API_KEY}" \
    "${FUNCTION_URL}?city=${encoded_city}&stateRegion=${encoded_state}")"
  response="$(cat "$response_file")"
  rm -f "$response_file"

  if ! printf '%s' "$response" | jq -e . >/dev/null; then
    echo "ERROR: ${city}, ${state_region} returned invalid JSON." >&2
    exit 1
  fi

  top_level_error="$(printf '%s' "$response" | jq -r '.error // empty')"
  if [[ ! "$http_status" =~ ^2 ]] || [[ -n "$top_level_error" ]]; then
    echo "ERROR: ${city}, ${state_region} discovery failed (HTTP ${http_status}): ${top_level_error:-unexpected response}" >&2
    exit 1
  fi

  inserted_total="$(printf '%s' "$response" | jq -r '(.results // []) | map(.inserted // 0) | add // 0')"
  updated_total="$(printf '%s' "$response" | jq -r '(.results // []) | map(.updated // 0) | add // 0')"
  error_total="$(printf '%s' "$response" | jq -r '(.results // []) | map((.errors // []) | length) | add // 0')"

  printf '%s, %s: inserted=%s updated=%s errors=%s\n' \
    "$city" "$state_region" "$inserted_total" "$updated_total" "$error_total"
done
