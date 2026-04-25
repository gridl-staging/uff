#!/usr/bin/env bash
# Deploy UFF landing page to Cloudflare Pages
# Usage: ./web/deploy.sh
#
# Prerequisites:
#   npx wrangler login   (one-time auth)
#
# This deploys the web/ directory as a Cloudflare Pages project named "uff-app".
# After first deploy, configure the custom domain uff.app in Cloudflare Pages dashboard.

set -euo pipefail

cd "$(dirname "$0")"

echo "Deploying UFF landing page to Cloudflare Pages..."
npx wrangler pages deploy . --project-name=uff-app --branch=main

echo ""
echo "Done! If this is the first deploy, go to Cloudflare Pages dashboard"
echo "and add uff.app as a custom domain for the 'uff-app' project."
