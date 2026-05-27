#!/usr/bin/env bash
# scripts/discovery/anthos-gcp-export.sh
#
# ACMF Phase 1 self-export — Anthos clusters running on GCP (GKE).
#
# Reads cluster topology, workloads, networking, storage, identity, CRDs, plus
# GKE-specific control-plane metadata if `gcloud` is available. Writes a single
# JSON bundle that conforms to schemas/discovery-bundle.schema.json.
#
# Read-only: never issues a write/mutate command. Missing tools / permission
# denials are logged into bundle.skipped[] and execution continues.
#
# Usage: see --help.
#
# Required tools : kubectl, jq
# Optional tools : gcloud  (control-plane metadata, Workload Identity Pool,
#                          regional vs zonal cluster, release channel)
# Permissions    : cluster-reader on the GKE cluster
#                  roles/container.viewer + roles/iam.workloadIdentityPoolViewer
#                  if gcloud is used.
# Estimated time : 1-2 min for a single cluster.
#
# Air-gapped friendly: uses only customer-side endpoints. gcloud calls go to
# Google APIs; skip them in air-gapped customer environments by *not*
# exporting GCLOUD_PROJECT.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_common.sh"

PLATFORM="anthos-gcp"

print_usage() {
  cat <<EOF
Anthos-on-GCP (GKE) discovery export.

Usage: $(basename "$0") [options]

Options:
  --output FILE            Output bundle (default: ./discovery-bundle.json)
  --include-namespaces CSV
  --exclude-namespaces CSV
  --include-system         Don't drop kube-*/gke-*/gmp-* namespaces
  --kubeconfig PATH
  --context NAME
  --dry-run                Print planned commands; emit a stub bundle
  -h, --help

Optional env:
  GCLOUD_PROJECT  GCP project (enables gcloud control-plane enrichment)
  GCLOUD_REGION   GCP region or zone (passed to \`gcloud container clusters describe\`)
EOF
}

main() {
  parse_common_args "$@"

  require_cmd kubectl
  require_cmd jq

  if ! have_cmd gcloud; then
    log_warn "gcloud not found — control-plane metadata will be skipped."
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log_info "Dry-run: emitting schema-valid stub to ${OUTPUT_FILE}"
    emit_bundle_stub "$PLATFORM" "$OUTPUT_FILE"
    log_info "Planned commands:"
    core_dry_run_hint
    log_dim "  gcloud container clusters describe \$CLUSTER --format=json --project \$GCLOUD_PROJECT"
    log_dim "  gcloud container node-pools list --cluster \$CLUSTER --format=json"
    log_dim "  gcloud iam workload-identity-pools list --location=global"
    return 0
  fi

  bundle_skeleton "$PLATFORM" >"$OUTPUT_FILE"
  local bundle="$OUTPUT_FILE"

  log_info "Collecting K8s core layer…"
  core_kube_collect "$bundle" "$PLATFORM" "gcp"

  # GKE-specific enrichment
  if have_cmd gcloud && [ -n "${GCLOUD_PROJECT:-}" ]; then
    log_info "Enriching with gcloud control-plane metadata…"
    local cluster_name="$CORE_CLUSTER_NAME"
    local gke_json=""
    if [ -n "${GCLOUD_REGION:-}" ]; then
      gke_json="$(gcloud container clusters describe "$cluster_name" \
                    --project="$GCLOUD_PROJECT" --region="$GCLOUD_REGION" --format=json 2>/dev/null \
                  || gcloud container clusters describe "$cluster_name" \
                    --project="$GCLOUD_PROJECT" --zone="$GCLOUD_REGION" --format=json 2>/dev/null \
                  || echo "")"
    fi
    if [ -n "$gke_json" ]; then
      jq --argjson g "$gke_json" \
         '
         .clusters[0] = (.clusters[0] + {
           location: ($g.location // "gcp"),
           anthos: ((.clusters[0].anthos // {}) + {
             release_channel: ($g.releaseChannel.channel // "STABLE"),
             workload_identity_pool: ($g.workloadIdentityConfig.workloadPool // null)
           })
         })
         ' "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
    else
      bundle_add_skipped "$bundle" "gcloud container clusters describe $cluster_name" \
        "GCLOUD_REGION not set or describe failed"
    fi
  else
    bundle_add_skipped "$bundle" "gcloud container clusters describe" \
      "gcloud or GCLOUD_PROJECT unavailable"
  fi

  log_info "Bundle written: $bundle"
}

main "$@"
