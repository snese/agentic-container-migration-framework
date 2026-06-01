#!/usr/bin/env bash
# rancher-export.sh
#
# ACMF Phase 1 (Assess) — Rancher (RKE/RKE2/K3s/imported) self-export.
#
# Real-cluster mode runs the shared kubectl collectors (lib/kubectl-collectors.sh)
# and layers on Rancher-specific enrichment:
#   - Distribution detection (k3s/rke2/rke/rancher-managed/vanilla-or-imported)
#     and server version, from node kubeletVersion + cattle-system probing
#                                                        → clusters[0].rancher
#   - Management vs downstream cluster classification    → clusters[0].rancher.is_management_cluster
#                                                          + top-level rancher.{is_management_cluster, downstream_clusters_total}
#   - Fleet inventory (clusters / bundles) when CRDs present
#                                                        → clusters[0].rancher.{fleet_clusters_total, fleet_bundles_total}
#   - Longhorn presence + volume count (informational, not in strict schema —
#     surfaced via warnings[] only).
#
# --dry-run mode emits a schema-valid stub via lib/output-bundle.sh::dry_run_stub.
#
# Read-only.
#
# Requirements: bash 4+, kubectl, jq.
#
# Usage:
#   ./rancher-export.sh [--dry-run] [--output FILE] [--namespaces "ns1,ns2"]
#                       [--exclude "..."] [--cluster-name NAME]
#
# Exit codes: 0 = success, 2 = usage, 3 = no kubectl access.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/output-bundle.sh
source "$SCRIPT_DIR/lib/output-bundle.sh"
# shellcheck source=lib/kubectl-collectors.sh
source "$SCRIPT_DIR/lib/kubectl-collectors.sh"

DRY_RUN=0
OUTPUT=""
INCLUDE_NS=""
EXCLUDE_NS="kube-system,kube-public,kube-node-lease,cattle-system,cattle-fleet-system,cattle-fleet-local-system,cattle-impersonation-system,cattle-monitoring-system,cattle-logging-system,fleet-system,fleet-default,fleet-local,ingress-nginx,longhorn-system"
CLUSTER_NAME=""

usage() { sed -n '2,30p' "$0"; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --output)       acmf::common::need_val "$1" "${2:-}"; OUTPUT="$2"; shift 2 ;;
    --namespaces)   acmf::common::need_val "$1" "${2:-}"; INCLUDE_NS="$2"; shift 2 ;;
    --exclude)      acmf::common::need_val "$1" "${2:-}"; EXCLUDE_NS="$2"; shift 2 ;;
    --cluster-name) acmf::common::need_val "$1" "${2:-}"; CLUSTER_NAME="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -z "$OUTPUT" ]] && OUTPUT="discovery-bundle-rancher-$(date -u +%Y%m%dT%H%M%SZ).json"

acmf::common::init
trap 'rm -rf "$ACMF_TMPDIR"' EXIT

if [[ "$DRY_RUN" -eq 1 ]]; then
  acmf::common::log "Dry-run mode: emitting schema-valid stub bundle for Rancher."
  acmf::bundle::dry_run_stub "$OUTPUT" "rancher-export-script (dry-run)" "rancher" "mock-rancher-cluster" "other" \
    "rancher-export: real-cluster mode auto-detects distribution (k3s/rke2/rke/rancher-managed/vanilla-or-imported) from node kubeletVersion" \
    "rancher-export: management vs downstream cluster classification — re-run against the management cluster context for Fleet bundles + cluster templates" \
    "rancher-export: Fleet inventory (clusters/bundles) collected when fleet.cattle.io CRDs present"
  acmf::common::log "Wrote stub bundle: $OUTPUT"
  exit 0
fi

# ---------------------------- Real collection ----------------------------
acmf::common::require kubectl || { echo "kubectl required" >&2; exit 3; }
acmf::common::require jq || { echo "jq required" >&2; exit 3; }
kubectl version --request-timeout=5s >/dev/null 2>&1 || { echo "kubectl cannot reach cluster" >&2; exit 3; }

[[ -z "$CLUSTER_NAME" ]] && CLUSTER_NAME="$(kubectl config current-context 2>/dev/null || echo unknown)"

if [[ -n "$INCLUDE_NS" ]]; then
  NS_LIST="$(echo "$INCLUDE_NS" | tr ',' '\n' | sed '/^$/d')"
else
  NS_LIST="$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n')"
  EXCLUDE_RE="$(echo "$EXCLUDE_NS" | tr ',' '|')"
  NS_LIST="$(echo "$NS_LIST" | grep -Ev "^(${EXCLUDE_RE})$" || true)"
fi
NS_INCLUDED_JSON="$(echo "$NS_LIST" | jq -R . | jq -s .)"
NS_EXCLUDED_JSON="$(echo "$EXCLUDE_NS" | tr ',' '\n' | jq -R . | jq -s .)"

K8S_VER="$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion // "unknown"')"
NODE_COUNT="$(kubectl get nodes -o json 2>/dev/null | jq '.items | length')"

# ---- Distribution detection ----
NODES_JSON="$(kubectl get nodes -o json 2>/dev/null || echo '{"items":[]}')"
KUBELET_VER="$(echo "$NODES_JSON" | jq -r '(.items // [])[0].status.nodeInfo.kubeletVersion // ""')"
DISTRO="unknown"
SERVER_VER=""
case "$KUBELET_VER" in
  *k3s*)  DISTRO="k3s";  SERVER_VER="$KUBELET_VER" ;;
  *rke2*) DISTRO="rke2"; SERVER_VER="$KUBELET_VER" ;;
  *)
    if kubectl get ns cattle-system >/dev/null 2>&1; then
      # Cattle agent → managed by Rancher; check for RKE1 (Docker-based) signal.
      if kubectl -n kube-system get cm full-cluster-state >/dev/null 2>&1; then
        DISTRO="rke"
      else
        DISTRO="rancher-managed"
      fi
      SERVER_VER="$KUBELET_VER"
    else
      DISTRO="vanilla-or-imported"
      SERVER_VER="$KUBELET_VER"
    fi
    ;;
esac

# ---- Management vs downstream classification ----
IS_MGMT="false"
if kubectl get crd clusters.provisioning.cattle.io >/dev/null 2>&1 \
   && kubectl -n cattle-system get deploy rancher >/dev/null 2>&1; then
  IS_MGMT="true"
fi

# ---- Fleet inventory ----
FLEET_CLUSTERS_TOTAL=0
FLEET_BUNDLES_TOTAL=0
if kubectl get crd clusters.fleet.cattle.io >/dev/null 2>&1; then
  acmf::common::log "Collecting Fleet inventory..."
  FLEET_CLUSTERS_JSON="$(kubectl get clusters.fleet.cattle.io -A -o json 2>/dev/null || echo '{"items":[]}')"
  FLEET_BUNDLES_JSON="$(kubectl get bundles.fleet.cattle.io -A -o json 2>/dev/null  || echo '{"items":[]}')"
  FLEET_CLUSTERS_TOTAL="$(echo "$FLEET_CLUSTERS_JSON" | jq '(.items // []) | length')"
  FLEET_BUNDLES_TOTAL="$(echo "$FLEET_BUNDLES_JSON"  | jq '(.items // []) | length')"
else
  acmf::common::skip "kubectl get clusters.fleet.cattle.io" \
    "Fleet CRDs not present (downstream cluster without Fleet agent, or non-Rancher cluster)"
fi

# ---- Longhorn (informational warning only — main schema doesn't have a
#      slot for Longhorn; surface as a warning so downstream consumers can act).
if kubectl get ns longhorn-system >/dev/null 2>&1; then
  LH_VOL_COUNT="$(kubectl -n longhorn-system get volumes.longhorn.io -o json 2>/dev/null | jq '(.items // []) | length' || echo 0)"
  acmf::common::warn "Rancher: Longhorn detected with ${LH_VOL_COUNT} volume(s) — Longhorn snapshots are stored in-cluster; on EKS, equivalent is EBS Snapshot + AWS Backup (different DR model)."
fi

# Build cluster.rancher block
CLUSTER_RANCHER_JSON="$(jq -n --arg distro "$DISTRO" --arg sv "$SERVER_VER" \
  --argjson mgmt "$IS_MGMT" --argjson fct "$FLEET_CLUSTERS_TOTAL" --argjson fbt "$FLEET_BUNDLES_TOTAL" \
  '{distribution:$distro, server_version:$sv, is_management_cluster:$mgmt, fleet_clusters_total:$fct, fleet_bundles_total:$fbt}')"

# Build clusters[]
CLUSTERS_JSON="$(jq -n --arg name "$CLUSTER_NAME" --arg ver "$K8S_VER" --argjson nc "${NODE_COUNT:-0}" \
  --argjson rancher "$CLUSTER_RANCHER_JSON" \
  '[{ name:$name, version:$ver, location:"unknown", platform:"other",
      control_plane:{ ha_mode:"unknown", node_count:$nc },
      node_pools:[], anthos_version:null, anthos_config_management_version:null,
      service_mesh:{ enabled:false, type:"none", version:null },
      rancher:$rancher }]')"

# K8s core layers via shared collectors.
WORKLOADS_JSON="$(acmf::k8s::collect_workloads "$NS_LIST" "$CLUSTER_NAME")"
NETWORKING_JSON="$(acmf::k8s::collect_networking "$NS_LIST" "$CLUSTER_NAME")"
STORAGE_JSON="$(acmf::k8s::collect_storage "$NS_LIST" "$CLUSTER_NAME")"
IDENTITY_JSON="$(acmf::k8s::collect_identity "$NS_LIST" "$CLUSTER_NAME")"
CRDS_JSON="$(acmf::k8s::collect_crds)"

EXT_JSON="[]"
VMW_JSON='{"clusters":[],"hosts":[],"datastores":[],"vm_to_node_mapping":[]}'
UTIL_JSON='{"nodes":[],"pods":[],"summary":{"cluster_cpu_utilization_pct":0.0,"cluster_memory_utilization_pct":0.0,"over_provisioning_ratio":0.0,"metrics_source":null}}'
TRAFFIC_JSON='{"pairs":[],"summary":{"east_west_bytes_per_sec":0,"north_south_bytes_per_sec":0,"total_service_pairs":0,"telemetry_source":null}}'

# Precise warnings — only when actionable.
if [[ "$IS_MGMT" == "true" ]]; then
  acmf::common::warn "Rancher: this is the management cluster — Fleet bundles and cluster templates are visible here. Re-run against each downstream cluster's kubeconfig for workload-level discovery."
elif kubectl get ns cattle-system >/dev/null 2>&1; then
  acmf::common::warn "Rancher: this is a downstream cluster — Fleet bundles deployed by the management cluster, cluster templates, and Rancher RBAC are NOT in this bundle. Run rancher-export.sh against the management cluster context too."
fi
if [[ "$DISTRO" == "rke" ]]; then
  acmf::common::warn "Rancher: RKE1 (Docker-based) is end-of-life. Recommend RKE → RKE2 in-place migration before EKS migration."
fi

SCOPE_JSON="$(jq -n --arg c "$CLUSTER_NAME" --argjson inc "$NS_INCLUDED_JSON" --argjson exc "$NS_EXCLUDED_JSON" \
  '{ clusters:[$c], namespaces_included:$inc, namespaces_excluded:$exc }')"

# Emit canonical bundle, then layer top-level rancher{} block when management.
acmf::bundle::emit "$OUTPUT" "$(acmf::common::generated_at)" "rancher-export-script" \
  "$SCOPE_JSON" "$CLUSTERS_JSON" "$WORKLOADS_JSON" "$NETWORKING_JSON" \
  "$STORAGE_JSON" "$IDENTITY_JSON" "$EXT_JSON" "$CRDS_JSON" \
  "$VMW_JSON" "$UTIL_JSON" "$TRAFFIC_JSON"

if [[ "$IS_MGMT" == "true" ]]; then
  jq --argjson n "$FLEET_CLUSTERS_TOTAL" \
     '. + { rancher: { is_management_cluster: true, downstream_clusters_total: $n } }' \
     "$OUTPUT" > "$OUTPUT.tmp" && mv "$OUTPUT.tmp" "$OUTPUT"
fi

acmf::common::log "Wrote: $OUTPUT"
acmf::common::log "Validate: npx --yes -p ajv-cli@5 -p ajv-formats@2 ajv validate -s schemas/discovery-bundle.schema.json -d $OUTPUT -c ajv-formats"
