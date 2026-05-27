#!/usr/bin/env bash
# scripts/discovery/rancher-export.sh
#
# ACMF Phase 1 self-export — Rancher-managed Kubernetes (Rancher 2.x: RKE,
# RKE2, K3s, or imported clusters).
#
# Reads the K8s core layer plus Rancher Fleet, Cattle agent metadata, and
# Longhorn (if installed) — the three things that almost always show up on
# Rancher engagements.
#
# Read-only.
#
# Required tools : kubectl, jq
# Optional tools : rancher  (Rancher CLI; only useful if you have a
#                            Rancher token. Not strictly required.)
#                  helm     (for chart-version probing)
# Permissions    : cluster-reader on the downstream cluster.
# Estimated time : 1-2 min.
#
# 🚧 v0.7-rc — RKE2/K3s on-the-fly upgrade history is not collected; that
#   data lives on the Rancher management cluster, not the downstream cluster
#   we're typically pointed at.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_common.sh"

PLATFORM="rancher"

print_usage() {
  cat <<EOF
Rancher (RKE/RKE2/K3s/imported) discovery export.

Usage: $(basename "$0") [options]

Options:
  --output FILE
  --include-namespaces CSV
  --exclude-namespaces CSV
  --include-system         Don't skip cattle-*/fleet-* namespaces
  --kubeconfig PATH
  --context NAME
  --dry-run
  -h, --help

🚧 v0.7-rc — Rancher fleet/cluster CRDs only collected if cattle-system is
   present in the active context.
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
    log_dim "  kubectl -n cattle-system get settings.management.cattle.io -o json"
    log_dim "  kubectl get clusters.fleet.cattle.io -A -o json"
    log_dim "  kubectl get bundles.fleet.cattle.io -A -o json"
    log_dim "  kubectl -n longhorn-system get volume,backup -o json   (if Longhorn)"
    return 0
  fi

  bundle_skeleton "$PLATFORM" >"$OUTPUT_FILE"
  local bundle="$OUTPUT_FILE"

  log_info "Collecting K8s core layer…"
  core_kube_collect "$bundle" "$PLATFORM" "rancher"

  # Rancher distribution detection: K3s vs RKE2 vs RKE vs imported
  local distro="unknown"
  if kc get nodes -o json 2>/dev/null | jq -e '.items[].status.nodeInfo.kubeletVersion | test("k3s")' >/dev/null 2>&1; then
    distro="k3s"
  elif kc get nodes -o json 2>/dev/null | jq -e '.items[].status.nodeInfo.kubeletVersion | test("rke2")' >/dev/null 2>&1; then
    distro="rke2"
  elif kc get ns cattle-system >/dev/null 2>&1; then
    distro="rancher-managed"
  else
    distro="vanilla-or-imported"
  fi
  jq --arg d "$distro" '.clusters[0].rancher = { distribution: $d }' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # Fleet (GitOps for Rancher)
  if kc get crd clusters.fleet.cattle.io >/dev/null 2>&1; then
    log_info "Collecting Fleet inventory…"
    local fleet_clusters fleet_bundles
    fleet_clusters="$(kc get clusters.fleet.cattle.io -A -o json 2>/dev/null || echo '{"items":[]}')"
    fleet_bundles="$(kc get bundles.fleet.cattle.io -A -o json 2>/dev/null  || echo '{"items":[]}')"
    jq --argjson fc "$fleet_clusters" --argjson fb "$fleet_bundles" \
       '.clusters[0].rancher = ((.clusters[0].rancher // {}) + {
          fleet_clusters_total: (($fc.items // []) | length),
          fleet_bundles_total: (($fb.items // []) | length)
        })' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
  else
    bundle_add_skipped "$bundle" "kubectl get clusters.fleet.cattle.io" \
      "Fleet CRDs not present (downstream cluster without Fleet agent)"
  fi

  # Longhorn (Rancher's CSI of choice)
  if kc get ns longhorn-system >/dev/null 2>&1; then
    log_info "Probing Longhorn…"
    local lh_volumes
    lh_volumes="$(kc -n longhorn-system get volumes.longhorn.io -o json 2>/dev/null || echo '{"items":[]}')"
    jq --argjson lh "$lh_volumes" \
       '.storage = ((.storage // {}) + {
          longhorn_volumes_total: (($lh.items // []) | length),
          longhorn_present: true
        })' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
  fi

  bundle_add_warning "$bundle" \
    "🚧 v0.7-rc: Rancher upgrade history and management-cluster Fleet bundles must be collected separately from the management cluster."

  log_info "Bundle written: $bundle"
}

main "$@"
