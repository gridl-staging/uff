<!-- [scrai:start] -->
## dev

| File | Summary |
| --- | --- |
| build_legal_site.py | Stub summary for build_legal_site.py. |
| build_testflight_release.sh | Stub summary for /Users/stuart/parallel_development/uff_dev/mar25_pm_3_runtime_observability_and_test_hardening/uff_dev/scripts/dev/build_testflight_release.sh. |
| capture_app_store_screenshots.sh | Stub summary for capture_app_store_screenshots.sh. |
| deploy_legal_site.sh | Build and deploy the Uff legal site (uff.app/privacy and uff.app/terms) to
Cloudflare Pages.

Source of truth: docs/privacy_policy.md and docs/terms_of_service.md.
Build output:    tmp/legal_site/ (gitignored).
Pages project:   uff-site (Cloudflare account gridl/uff).
Custom domains:  uff.app (apex) and www.uff.app (proxied CNAME to
                 uff-site.pages.dev).

Run from the repo root. |
| release_readiness_check.sh | release_readiness_check.sh — Read-only release readiness summary.

Answers "is this repo ready for a release build?" without building anything.
Consolidates checks from build_testflight_release.sh, preflight_check.sh,
and validate_deployment.sh into a single pass/fail/warn report.

Usage:
  ./scripts/dev/release_readiness_check.sh

Exit codes:
  0 => all fail-level checks passed (warn findings do not block)
  1 => one or more fail-level checks failed. |
| run_devicecloud_smoke.sh | Stub summary for run_devicecloud_smoke.sh. |
| run_ios_signoff_suite.sh | Stub summary for run_ios_signoff_suite.sh. |
| setup_firebase_test_lab.sh | One-shot setup for Firebase Test Lab on uff-prod.

Creates a dedicated least-privilege service account for Test Lab,
enables the two required Google APIs, and writes the SA key to .secret/.
Idempotent: safe to re-run; each step no-ops if already done.

Prerequisite: run `gcloud auth login` once (browser flow) as a human
account with Owner/Editor on the uff-prod GCP project. |
<!-- [scrai:end] -->
