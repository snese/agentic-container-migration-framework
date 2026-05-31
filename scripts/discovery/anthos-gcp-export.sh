#!/usr/bin/env bash
# scripts/discovery/anthos-gcp-export.sh
#
# ACMF Phase 1 self-export — Anthos clusters running on GCP (GKE).
#
# Reads cluster topology, workloads, networking, storage, identity, CRDs, plus
# GKE-specific control-plane metadata if `gcloud` is available, plus Workload
# Identity binding inventory and GKE Config Connector (KCC) presence — the
# two GCP-native abstractions that need explicit AWS translation (IRSA + ACK
# respectively).
#
# Read-only: never issues a write/mutate command. Missing tools / permission
# denials are logged into bundle.skipped[] and execution continues.
#
# Required tools : kubectl, jq
# Optional tools : gcloud  (control-plane metadata, release channel)
# Permissions    : cluster-reader on the GKE cluster
#                  roles/container.viewer if gcloud is used.
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

What this collects (in addition to the K8s core layer):
  - Anthos / GKE control-plane metadata (release channel, Workload Identity Pool)
  - Workload Identity bindings — every ServiceAccount with the
    iam.gke.io/gcp-service-account annotation, mapped 1:1 to an IRSA target
  - Config Connector (KCC) presence + managed-resource kind list
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
    log_dim "  kubectl get sa -A -o json   (filter iam.gke.io/gcp-service-account annotation)"
    log_dim "  kubectl get crd -o json     (filter cnrm.cloud.google.com → KCC)"
    log_dim "  gcloud container clusters describe \$CLUSTER --format=json --project \$GCLOUD_PROJECT"
    log_dim "  gcloud container node-pools list --cluster \$CLUSTER --format=json"
    return 0
  fi

  bundle_skeleton "$PLATFORM" >"$OUTPUT_FILE"
  local bundle="$OUTPUT_FILE"

  log_info "Collecting K8s core layer…"
  core_kube_collect "$bundle" "$PLATFORM" "gcp"

  # ---- Workload Identity bindings ----
  log_info "Collecting Workload Identity bindings…"
  local sa_json wi_array wi_count
  sa_json="$(kc get sa -A -o json 2>/dev/null || echo '{"items":[]}')"
  wi_array="$(jq -n --argjson s "$sa_json" \
    '
    [($s.items // [])[]
      | select(.metadata.annotations["iam.gke.io/gcp-service-account"] // null)
      | {
          service_account_namespace: .metadata.namespace,
          service_account_name: .metadata.name,
          gcp_service_account: .metadata.annotations["iam.gke.io/gcp-service-account"]
        }]')"
  wi_count="$(printf '%s' "$wi_array" | jq 'length')"
  jq --argjson wi "$wi_array" --argjson wi_count "$wi_count" \
     '.identity = ((.identity // {}) + {
        workload_identity_enabled: ($wi_count > 0),
        workload_identity_bindings: $wi
      })' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # ---- Config Connector (KCC) ----
  log_info "Probing Config Connector (KCC)…"
  local crd_json kcc_kinds kcc_count
  crd_json="$(kc get crd -o json 2>/dev/null || echo '{"items":[]}')"
  # KCC CRDs all live under groups ending in cnrm.cloud.google.com
  kcc_kinds="$(jq -n --argjson c "$crd_json" \
    '[($c.items // [])[]
      | select((.spec.group // "") | endswith("cnrm.cloud.google.com"))
      | (.spec.names.kind // "")] | unique')"
  kcc_count="$(printf '%s' "$kcc_kinds" | jq 'length')"
  if [ "$kcc_count" -gt 0 ]; then
    jq --argjson kinds "$kcc_kinds" --argjson n "$kcc_count" \
       '.clusters[0].anthos = ((.clusters[0].anthos // {}) + {
          config_connector: { installed: true, crd_count: $n, managed_resource_kinds: $kinds }
        })' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
  else
    jq '.clusters[0].anthos = ((.clusters[0].anthos // {}) + {
          config_connector: { installed: false, crd_count: 0, managed_resource_kinds: [] }
        })' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
  fi

  # ---- gcloud control-plane enrichment ----
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

  # ---- precise warnings (only when actionable) ----
  if [ "$wi_count" -gt 0 ]; then
    bundle_add_warning "$bundle" \
      "Anthos-on-GCP: ${wi_count} Workload Identity binding(s) — each KSA→GSA pair must be rewritten as an IRSA role on EKS (annotation eks.amazonaws.com/role-arn + IAM trust policy)."
  fi
  if [ "$kcc_count" -gt 0 ]; then
    bundle_add_warning "$bundle" \
      "Anthos-on-GCP: Config Connector (KCC) detected with ${kcc_count} managed CRD kinds — translate to AWS Controllers for Kubernetes (ACK) or Terraform/CDK; no 1:1 type mapping for every GCP resource."
  fi

  log_info "Bundle written: $bundle"
}

main "$@"
