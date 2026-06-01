#!/usr/bin/env bash
# tests/discovery-export-smoke.sh
#
# Smoke test:
#   1. Run each source-export script in --dry-run mode and validate the
#      resulting discovery bundle against schemas/discovery-bundle.schema.json.
#   2. Validate every fixture under adapters/source/*/fixtures/ against the
#      same schema.
#
# Invoked from CI (.github/workflows/ci.yml). Exits 0 on success, non-zero
# on the first failure.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT/scripts/discovery"
SCHEMA="$ROOT/schemas/discovery-bundle.schema.json"
TEST_TMPDIR="$(mktemp -d -t acmf-smoke-XXXXXX)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Canonical list of source-adapter export scripts. Both the shipped
# gke-enterprise-vmware adapter and the per-source adapters
# (gke / aks / openshift / rancher / vanilla-k8s / gke-enterprise-gcp /
# gke-enterprise-baremetal) must produce a schema-valid bundle in --dry-run.
SCRIPTS=(
  "gke-enterprise-vmware-export.sh"
  "gke-export.sh"
  "aks-export.sh"
  "openshift-export.sh"
  "rancher-export.sh"
  "vanilla-k8s-export.sh"
  "gke-enterprise-gcp-export.sh"
  "gke-enterprise-baremetal-export.sh"
)

failures=0

echo "::group::dry-run validation (per platform script)"
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
echo "::endgroup::"

echo "::group::fixture validation (adapters/source/*/fixtures/*.json)"
shopt -s nullglob
fixtures_validated=0
for fx in "$ROOT"/adapters/source/*/fixtures/*.json; do
  if ! npx --yes -p ajv-cli@5 -p ajv-formats@2 ajv validate \
        -s "$SCHEMA" -d "$fx" -c ajv-formats >/dev/null 2>&1; then
    echo "::error::Fixture $fx is invalid"
    npx --yes -p ajv-cli@5 -p ajv-formats@2 ajv validate \
      -s "$SCHEMA" -d "$fx" -c ajv-formats || true
    failures=$((failures + 1))
  else
    echo "OK  ${fx#"$ROOT/"}"
    fixtures_validated=$((fixtures_validated + 1))
  fi
done
shopt -u nullglob
echo "Validated $fixtures_validated fixture(s)."
echo "::endgroup::"

if (( failures > 0 )); then
  echo "::error::$failures script/fixture failure(s) in smoke validation"
  exit 1
fi

echo "All discovery-export smoke tests passed."
