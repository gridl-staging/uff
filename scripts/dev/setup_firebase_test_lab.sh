#!/usr/bin/env bash
# One-shot setup for Firebase Test Lab on uff-prod.
#
# Creates a dedicated least-privilege service account for Test Lab,
# enables the two required Google APIs, and writes the SA key to .secret/.
# Idempotent: safe to re-run; each step no-ops if already done.
#
# Prerequisite: run `gcloud auth login` once (browser flow) as a human
# account with Owner/Editor on the uff-prod GCP project. Service accounts
# cannot grant themselves IAM roles, so this step cannot be automated.

set -euo pipefail

# Add gcloud to PATH if it's on a Homebrew-standard location but not yet
# exported. Tries Apple Silicon first, then Intel. If gcloud is already on
# PATH (system install, custom location), leave things alone.
if ! command -v gcloud >/dev/null 2>&1; then
  for CANDIDATE in \
    /opt/homebrew/share/google-cloud-sdk/bin \
    /usr/local/share/google-cloud-sdk/bin; do
    if [[ -x "$CANDIDATE/gcloud" ]]; then
      export PATH="$CANDIDATE:$PATH"
      break
    fi
  done
fi
if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud not found on PATH. Install via: brew install --cask gcloud-cli"
  exit 1
fi

PROJECT_ID="uff-prod"
SA_NAME="uff-test-lab"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Derive the repo root from this script's location instead of hardcoding
# a per-machine absolute path. This script lives at <repo>/scripts/dev/ so
# two dirnames up gives the repo root. Using `cd && pwd` rather than the
# raw BASH_SOURCE path so we emit an absolute, normalised path that works
# regardless of how the script was invoked (relative path, PATH lookup).
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
KEY_PATH="$REPO_ROOT/.secret/firebase_service_account_uff_test_lab.json"

# roles/cloudtestservice.testAdmin is the narrowest role that covers both
# running Test Lab matrices and reading their Tool Results. Verified
# empirically on 2026-04-24 by listing iOS device models with this role
# as the only project-level binding on the SA. Broader roles like
# firebase.qualityAdmin also work but grant Crashlytics / App Distribution
# / Performance Monitoring access that Test Lab does not need.
SA_ROLE="roles/cloudtestservice.testAdmin"

# Capture the human account at entry so we can restore it at exit. Without
# this the script leaves gcloud authenticated as the SA because step 6
# activates the key to verify access.
HUMAN_ACCOUNT=""

# Restore human gcloud account on any exit path (success or failure) so
# subsequent shell commands do not silently run as the Test Lab SA.
restore_account() {
  if [[ -n "$HUMAN_ACCOUNT" ]]; then
    gcloud config set account "$HUMAN_ACCOUNT" >/dev/null 2>&1 || true
  fi
}
trap restore_account EXIT

echo "=== 1/6 Verify human auth (service account cannot grant IAM) ==="
HUMAN_ACCOUNT=$(gcloud config get-value account 2>/dev/null || true)
# Reject three failure modes up front: (1) no credential at all (gcloud
# prints "(unset)" in that case), (2) empty string from fresh install,
# (3) a service account credential. Only a real human Google Workspace /
# gmail account can grant project-level IAM roles.
if [[ -z "$HUMAN_ACCOUNT" || "$HUMAN_ACCOUNT" == "(unset)" ]]; then
  echo "ERROR: no active gcloud account."
  echo "Run: gcloud auth login   (opens browser, pick your Google account)"
  exit 1
fi
if [[ "$HUMAN_ACCOUNT" == *"gserviceaccount.com" ]]; then
  echo "ERROR: gcloud active account is a service account ($HUMAN_ACCOUNT)."
  echo "Service accounts cannot grant themselves IAM roles."
  echo "Run: gcloud auth login   (opens browser, pick your Google account)"
  exit 1
fi
echo "Active account: $HUMAN_ACCOUNT"
gcloud config set project "$PROJECT_ID"

echo ""
echo "=== 2/6 Enable Test Lab + Tool Results APIs ==="
# testing.googleapis.com drives matrix execution.
# toolresults.googleapis.com stores logs, videos, screenshots per run.
gcloud services enable \
  testing.googleapis.com \
  toolresults.googleapis.com \
  --project="$PROJECT_ID"

echo ""
echo "=== 3/6 Create dedicated Test Lab service account (if missing) ==="
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
  echo "Service account $SA_EMAIL already exists - skipping create."
else
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="Uff Firebase Test Lab" \
    --project="$PROJECT_ID"
fi

echo ""
echo "=== 4/6 Grant Test Lab role (idempotent) ==="
# --condition=None pins this as an unconditional binding. Required when
# the project's IAM policy contains any conditional binding (Google then
# forces every add/remove to declare condition state explicitly).
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="$SA_ROLE" \
  --condition=None \
  --quiet >/dev/null

echo ""
echo "=== 5/6 Generate key file (if missing) ==="
if [[ -f "$KEY_PATH" ]]; then
  echo "Key file already exists at $KEY_PATH - skipping create."
  echo "Delete it first if you want a fresh key."
else
  gcloud iam service-accounts keys create "$KEY_PATH" \
    --iam-account="$SA_EMAIL"
fi
# Always enforce 0600 on the key file; gcloud defaults to 0644 which is
# world-readable on a multi-user Mac and a real audit finding on shared hosts.
chmod 600 "$KEY_PATH"

echo ""
echo "=== 6/6 Verify: list iOS device models as the new SA ==="
# Auth flip is intentional here - proves the SA key itself can reach Test
# Lab, not just that the human account is over-permissioned. trap above
# restores the human account on exit.
gcloud auth activate-service-account --key-file="$KEY_PATH" --quiet

# Assert on machine-readable stdout only. Two reasons to keep stderr out
# of the capture: (a) gcloud prints warnings and auth prompts to stderr
# which would pollute MODEL_IDS and confuse the line count, (b) the
# --format="value(id)" contract only applies to stdout.
# The pretty --format=table uses Unicode box-drawing chars which differ
# across gcloud versions and would make grep assertions brittle.
MODEL_IDS=$(gcloud firebase test ios models list \
  --project="$PROJECT_ID" \
  --format="value(id)" 2>/dev/null)
# grep -c . counts non-empty lines. `|| true` absorbs grep's exit 1 on a
# fully empty capture so `set -e` does not abort before we print a
# helpful error.
MODEL_COUNT=$(echo "$MODEL_IDS" | grep -c . || true)
if [[ "$MODEL_COUNT" -lt 1 ]]; then
  echo "ERROR: Test Lab returned zero iOS device models."
  echo "Possible causes: API enablement propagation (wait 60s, retry),"
  echo "project restrictions, or missing role on $SA_EMAIL."
  exit 1
fi
echo "Test Lab reachable. $MODEL_COUNT iOS device models available, e.g.:"
echo "$MODEL_IDS" | head -3 | sed 's/^/  - /'

echo ""
echo "=== DONE ==="
echo "Test Lab SA email:    $SA_EMAIL"
echo "Test Lab key file:    $KEY_PATH"
echo "(gcloud account restored to $HUMAN_ACCOUNT on exit via trap)"
