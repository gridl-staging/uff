#!/usr/bin/env bash
# Build and deploy the Uff legal site (uff.app/privacy and uff.app/terms) to
# Cloudflare Pages.
#
# Source of truth: docs/privacy_policy.md and docs/terms_of_service.md.
# Build output:    tmp/legal_site/ (gitignored).
# Pages project:   uff-site (Cloudflare account gridl/uff).
# Custom domains:  uff.app (apex) and www.uff.app (proxied CNAME to
#                  uff-site.pages.dev).
#
# Run from the repo root. Requires:
#   - Python 3 with the `markdown` package installed (pip3 install --user markdown)
#   - `npx` (the script installs wrangler on demand)
#   - .secret/.env.secret containing CLOUDFLARE_PAGES_DEPLOY_TOKEN_uff
#
# Re-run this script after any edit to docs/privacy_policy.md or
# docs/terms_of_service.md. It is idempotent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

SECRET_FILE=".secret/.env.secret"
if [[ ! -f "${SECRET_FILE}" ]]; then
  echo "ERROR: ${SECRET_FILE} missing; cannot load Cloudflare deploy token." >&2
  exit 1
fi

# Only load the one variable we need, without polluting the shell with the
# rest of .env.secret.
DEPLOY_TOKEN="$(grep -E '^CLOUDFLARE_PAGES_DEPLOY_TOKEN_uff=' "${SECRET_FILE}" | head -1 | cut -d= -f2-)"
if [[ -z "${DEPLOY_TOKEN}" ]]; then
  echo "ERROR: CLOUDFLARE_PAGES_DEPLOY_TOKEN_uff not found in ${SECRET_FILE}." >&2
  exit 1
fi

echo "[1/3] Rendering legal markdown -> HTML into tmp/legal_site/"
python3 scripts/dev/build_legal_site.py

echo "[2/3] Deploying to Cloudflare Pages project uff-site"
CLOUDFLARE_API_TOKEN="${DEPLOY_TOKEN}" \
  npx --yes wrangler pages deploy tmp/legal_site \
    --project-name uff-site \
    --branch main \
    --commit-dirty=true

echo "[3/3] Verifying live URLs"
for path in "/" "/privacy" "/terms"; do
  status="$(curl -s -o /dev/null -w '%{http_code}' -L "https://uff.app${path}")"
  if [[ "${status}" != "200" ]]; then
    echo "WARN: https://uff.app${path} returned HTTP ${status} (expected 200)" >&2
  else
    echo "ok   https://uff.app${path} -> 200"
  fi
done

echo
echo "Deploy complete. App Store Connect privacy URL: https://uff.app/privacy"
