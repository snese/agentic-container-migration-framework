#!/usr/bin/env bash
# scripts/discovery/simulate-discovery.sh
#
# Produce a fake but schema-valid discovery-bundle.json for a given source
# platform, by combining a static fixture with on-the-fly randomization
# (timestamps, random replicas, randomized cluster names).
#
# Usage:
#   ./simulate-discovery.sh <platform> [--size small|realistic] [--output FILE]
#
# Available platforms (must match adapters/source/<name>/fixtures/):
#   anthos-vmware, anthos-gcp, anthos-baremetal, openshift, rancher, vanilla-k8s
#
# Use this for:
#   - Dogfooding / smoke-testing Phase 2 / Phase 3 prompts before customer arrives
#   - CI: validate-bundle.sh round-trip against simulated input
#   - Demos / training material
#
# Required: jq.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

print_usage() {
  cat <<EOF
Simulate an ACMF discovery bundle from a fixture.

Usage:
  $(basename "$0") <platform> [--size small|realistic] [--output FILE]

Platforms: anthos-vmware anthos-gcp anthos-baremetal openshift rancher vanilla-k8s
Sizes:     small (default) | realistic

Examples:
  $(basename "$0") anthos-vmware
  $(basename "$0") openshift --size realistic --output /tmp/openshift-sim.json
EOF
}

PLATFORM="${1:-}"
case "$PLATFORM" in
  -h|--help|"") print_usage; [ -z "$PLATFORM" ] && exit 2 || exit 0 ;;
esac
shift || true

SIZE="small"
OUTPUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --size)    SIZE="${2:?}"; shift 2 ;;
    --size=*)  SIZE="${1#*=}"; shift ;;
    --output)  OUTPUT="${2:?}"; shift 2 ;;
    --output=*)OUTPUT="${1#*=}"; shift ;;
    -h|--help) print_usage; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

case "$SIZE" in small|realistic) ;; *) echo "size must be 'small' or 'realistic'" >&2; exit 2 ;; esac

case "$PLATFORM" in
  anthos-vmware|anthos-gcp|anthos-baremetal|openshift|rancher|vanilla-k8s) ;;
  *) echo "Unknown platform: $PLATFORM" >&2; print_usage; exit 2 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "jq required" >&2; exit 2
fi

FIXTURE="${REPO_ROOT}/adapters/source/${PLATFORM}/fixtures/${PLATFORM}-${SIZE}.json"
if [ ! -f "$FIXTURE" ]; then
  echo "Fixture not found: $FIXTURE" >&2
  exit 2
fi

[ -z "$OUTPUT" ] && OUTPUT="./discovery-bundle-${PLATFORM}-${SIZE}.json"

now_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
# Lightweight randomization: nudge replica counts ±1, jitter cluster name suffix.
suffix="$(printf '%04x' $((RANDOM & 0xffff)))"

jq \
  --arg ts "$now_iso" \
  --arg suffix "$suffix" \
  '
  # Stamp generated_at and add a "simulated" warning so consumers can tell.
  .generated_at = $ts
  | .generated_by = "self-export-script"
  | .warnings = ((.warnings // []) + ["simulated bundle — produced by simulate-discovery.sh, NOT a live cluster"])
  | (.clusters // []) |= map(.name = (.name + "-" + $suffix))
  | (.scope.clusters // []) |= map(. + "-" + $suffix)
  | (.workloads // []) |= map(.cluster = (.cluster + "-" + $suffix))
  | (.workloads // []) |= map(
      .replicas.desired = ((.replicas.desired // 1) + (($suffix | explode | add) % 2))
    )
  ' "$FIXTURE" >"$OUTPUT"

echo "Simulated bundle written: $OUTPUT"
echo "Validate with: scripts/discovery/validate-bundle.sh $OUTPUT"
