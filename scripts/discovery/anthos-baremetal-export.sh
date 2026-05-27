#!/usr/bin/env bash
# scripts/discovery/anthos-baremetal-export.sh
#
# ACMF Phase 1 self-export — Anthos clusters on bare-metal.
#
# Reads K8s + Anthos-on-bare-metal control-plane metadata. No hypervisor /
# vCenter layer (bare-metal). No gcloud probe of the underlying hardware —
# bare-metal customers may be air-gapped.
#
# Read-only.
#
# Usage: see --help.
#
# Required tools : kubectl, jq
# Optional tools : bmctl   (Anthos bare-metal admin CLI; only needed if you
#                          want fleet/admin-cluster metadata. Often not
#                          available from a user-cluster context.)
# Permissions    : cluster-reader on the user cluster.
# Estimated time : 1-2 min.
#
# 🚧 v0.7-rc — Bare-metal-specific BMA hardware inventory (DPU/GPU
#   passthrough, BMC-level inventory) is OUT of scope; needs SME review.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_common.sh"

PLATFORM="anthos-baremetal"

print_usage() {
  cat <<EOF
Anthos-on-bare-metal discovery export.

Usage: $(basename "$0") [options]

Options:
  --output FILE
  --include-namespaces CSV
  --exclude-namespaces CSV
  --include-system
  --kubeconfig PATH
  --context NAME
  --dry-run
  -h, --help

🚧 v0.7-rc — hardware-layer inventory (BMC, DPU, GPU passthrough) is a stub.
EOF
}

main() {
  parse_common_args "$@"

  require_cmd kubectl
  require_cmd jq

  if [ "$DRY_RUN" = "1" ]; then
    log_info "Dry-run: emitting schema-valid stub to ${OUTPUT_FILE}"
    emit_bundle_stub "$PLATFORM" "$OUTPUT_FILE"
    log_info "Planned commands:"
    core_dry_run_hint
    log_dim "  kubectl get cluster.baremetal.cluster.gke.io -A -o json   (if CRD installed)"
    log_dim "  kubectl get nodepool.baremetal.cluster.gke.io -A -o json"
    return 0
  fi

  bundle_skeleton "$PLATFORM" >"$OUTPUT_FILE"
  local bundle="$OUTPUT_FILE"

  log_info "Collecting K8s core layer…"
  core_kube_collect "$bundle" "$PLATFORM" "on-prem-baremetal"

  # Anthos-on-bare-metal CRDs (best-effort).
  log_info "Probing bare-metal Anthos CRDs…"
  if kc get crd cluster.baremetal.cluster.gke.io >/dev/null 2>&1; then
    local bm_clusters
    bm_clusters="$(kc get cluster.baremetal.cluster.gke.io -A -o json 2>/dev/null || echo '{"items":[]}')"
    jq --argjson bm "$bm_clusters" \
       '.clusters[0].anthos = ((.clusters[0].anthos // {}) + {
          baremetal_cluster_count: (($bm.items // []) | length),
          baremetal_cluster_names: [(($bm.items // [])[].metadata.name)]
        })' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
  else
    bundle_add_skipped "$bundle" "kubectl get cluster.baremetal.cluster.gke.io" \
      "Anthos bare-metal CRDs not present (likely a user cluster, not admin)"
  fi

  bundle_add_warning "$bundle" \
    "🚧 v0.7-rc: bare-metal hardware inventory (BMC, DPU, GPU passthrough) not collected; SME review required for hardware-bound workloads."

  log_info "Bundle written: $bundle"
}

main "$@"
