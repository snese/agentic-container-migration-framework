#!/usr/bin/env bash
# scripts/discovery/rancher-export.sh
#
# ACMF Phase 1 self-export — Rancher-managed Kubernetes (Rancher 2.x: RKE,
# RKE2, K3s, or imported clusters).
#
# Reads the K8s core layer plus Rancher Fleet, Cattle agent metadata,
# Longhorn (if installed), and detects whether the active context is the
# Rancher management cluster vs a downstream cluster — the two modes have
# very different inventories.
#
# Read-only.
#
# Required tools : kubectl, jq
# Optional tools : rancher  (CLI; only useful with a Rancher token)
#                  helm     (chart-version probing)
# Permissions    : cluster-reader on the cluster.
# Estimated time : 1-2 min.

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

What this collects (in addition to the K8s core layer):
  - Distribution detection: k3s / rke2 / rke / rancher-managed / imported
  - Distribution server version (e.g. v1.29.4+rke2r1)
  - Management vs downstream cluster classification
  - Fleet inventory (clusters / bundles) when CRDs present
  - Longhorn presence + volume count

If you point this at a downstream cluster only, Fleet bundles and cluster
templates managed by the management cluster will be missing — re-run
against the management cluster's context for that picture.
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
    log_dim "  kubectl get nodes -o json   (extract kubeletVersion → distro + server_version)"
    log_dim "  kubectl get crd provisioningclusters.provisioning.cattle.io   (management-cluster signal)"
    log_dim "  kubectl -n cattle-system get settings.management.cattle.io -o json"
    log_dim "  kubectl get clusters.fleet.cattle.io -A -o json"
    log_dim "  kubectl get bundles.fleet.cattle.io -A -o json"
    log_dim "  kubectl -n longhorn-system get volumes.longhorn.io -o json   (if Longhorn)"
    return 0
  fi

  bundle_skeleton "$PLATFORM" >"$OUTPUT_FILE"
  local bundle="$OUTPUT_FILE"

  log_info "Collecting K8s core layer…"
  core_kube_collect "$bundle" "$PLATFORM" "rancher"

  # ---- Distribution + server version ----
  local nodes_json kubelet_version distro server_version
  nodes_json="$(kc get nodes -o json 2>/dev/null || echo '{"items":[]}')"
  kubelet_version="$(printf '%s' "$nodes_json" | jq -r '(.items // [])[0].status.nodeInfo.kubeletVersion // ""')"
  distro="unknown"
  server_version=""
  case "$kubelet_version" in
    *k3s*)  distro="k3s";  server_version="$kubelet_version" ;;
    *rke2*) distro="rke2"; server_version="$kubelet_version" ;;
    *)
      # Plain kubelet version — could be RKE1 (Docker), imported, or vanilla under Rancher.
      if kc get ns cattle-system >/dev/null 2>&1; then
        # Cattle agent present → managed by Rancher; check for RKE1 system stack.
        if kc -n kube-system get pods -l io.cattle.rke=true >/dev/null 2>&1 \
           || kc -n kube-system get cm full-cluster-state >/dev/null 2>&1; then
          distro="rke"
        else
          distro="rancher-managed"
        fi
        server_version="$kubelet_version"
      else
        distro="vanilla-or-imported"
        server_version="$kubelet_version"
      fi
      ;;
  esac

  # ---- Management vs downstream classification ----
  # Heuristics (any one trips it):
  #   - management cluster carries provisioning.cattle.io/v1.Cluster CRD
  #     (it manages other clusters).
  #   - It typically has many cluster-scoped resources under cattle-system
  #     including the "rancher" Deployment.
  local is_mgmt
  is_mgmt="false"
  if kc get crd clusters.provisioning.cattle.io >/dev/null 2>&1 \
     && kc -n cattle-system get deploy rancher >/dev/null 2>&1; then
    is_mgmt="true"
  fi

  jq --arg distro "$distro" --arg sv "$server_version" --argjson mgmt "$is_mgmt" \
     '.clusters[0].rancher = ((.clusters[0].rancher // {}) + {
        distribution: $distro,
        server_version: $sv,
        is_management_cluster: $mgmt
      })' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # ---- Fleet inventory ----
  local fleet_clusters_total=0
  local fleet_bundles_total=0
  if kc get crd clusters.fleet.cattle.io >/dev/null 2>&1; then
    log_info "Collecting Fleet inventory…"
    local fleet_clusters fleet_bundles
    fleet_clusters="$(kc get clusters.fleet.cattle.io -A -o json 2>/dev/null || echo '{"items":[]}')"
    fleet_bundles="$(kc get bundles.fleet.cattle.io -A -o json 2>/dev/null  || echo '{"items":[]}')"
    fleet_clusters_total="$(printf '%s' "$fleet_clusters" | jq '(.items // []) | length')"
    fleet_bundles_total="$(printf '%s' "$fleet_bundles" | jq '(.items // []) | length')"
    jq --argjson fct "$fleet_clusters_total" --argjson fbt "$fleet_bundles_total" \
       '.clusters[0].rancher = ((.clusters[0].rancher // {}) + {
          fleet_clusters_total: $fct,
          fleet_bundles_total: $fbt
        })' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
  else
    bundle_add_skipped "$bundle" "kubectl get clusters.fleet.cattle.io" \
      "Fleet CRDs not present (downstream cluster without Fleet agent, or non-Rancher cluster)"
  fi

  # If management cluster, also surface .rancher (top-level) with downstream count
  if [ "$is_mgmt" = "true" ]; then
    jq --argjson n "$fleet_clusters_total" \
       '.rancher = ((.rancher // {}) + {
          is_management_cluster: true,
          downstream_clusters_total: $n
        })' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
  fi

  # ---- Longhorn ----
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

  # ---- Precise warnings (only when actionable) ----
  if [ "$is_mgmt" = "true" ]; then
    bundle_add_warning "$bundle" \
      "Rancher: this is the management cluster — Fleet bundles and cluster templates are visible here. Re-run against each downstream cluster's kubeconfig for workload-level discovery."
  else
    if kc get ns cattle-system >/dev/null 2>&1; then
      bundle_add_warning "$bundle" \
        "Rancher: this is a downstream cluster — Fleet bundles deployed by the management cluster, cluster templates, and Rancher RBAC are NOT in this bundle. Run scripts/discovery/rancher-export.sh against the management cluster context too."
    fi
  fi
  if [ "$distro" = "rke" ]; then
    bundle_add_warning "$bundle" \
      "Rancher: RKE1 (Docker-based) is end-of-life. Recommend RKE → RKE2 in-place migration before EKS migration."
  fi

  log_info "Bundle written: $bundle"
}

main "$@"
