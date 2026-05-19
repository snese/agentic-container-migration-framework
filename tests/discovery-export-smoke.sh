#!/usr/bin/env bash
# tests/discovery-export-smoke.sh
#
# Smoke test: run each source-export script in --dry-run mode and validate
# the resulting discovery bundle against schemas/discovery-bundle.schema.json.
#
# Invoked from CI (.github/workflows/ci.yml). Exits 0 on success, non-zero
# on the first script that produces an invalid bundle.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT/scripts/discovery"
SCHEMA="$ROOT/schemas/discovery-bundle.schema.json"
TEST_TMPDIR="$(mktemp -d -t acmf-smoke-XXXXXX)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Canonical list of source-adapter export scripts. Both the shipped GKE
# Enterprise on VMware adapter and the four stub adapters (gke, aks,
# openshift, rancher) must produce a schema-valid bundle in --dry-run.
SCRIPTS=(
  "gke-enterprise-vmware-export.sh"
  "gke-export.sh"
  "aks-export.sh"
  "openshift-export.sh"
  "rancher-export.sh"
)

failures=0
for s in "${SCRIPTS[@]}"; do
  out="$TEST_TMPDIR/${s%.sh}.json"
  echo "::group::dry-run $s"
  if ! bash "$SCRIPTS_DIR/$s" --dry-run --output "$out"; then
    echo "::error::$s --dry-run failed"
    failures=$((failures + 1))
    echo "::endgroup::"
    continue
  fi
  if ! npx --yes -p ajv-cli@5 -p ajv-formats@2 ajv validate \
        -s "$SCHEMA" -d "$out" -c ajv-formats >/dev/null 2>&1; then
    echo "::error::$s produced an invalid bundle"
    npx --yes -p ajv-cli@5 -p ajv-formats@2 ajv validate \
      -s "$SCHEMA" -d "$out" -c ajv-formats || true
    failures=$((failures + 1))
  else
    echo "OK  $s -> $(basename "$out")"
  fi
  echo "::endgroup::"
done

if (( failures > 0 )); then
  echo "::error::$failures script(s) failed smoke validation"
  exit 1
fi

echo "All discovery-export smoke tests passed."
