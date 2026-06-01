#!/usr/bin/env bash
# vanilla-k8s-export.sh
#
# ACMF Phase 1 (Assess) — generic / vanilla Kubernetes (kubeadm,
# self-managed, kops, Talos, kubespray, EKS-Anywhere, etc.) self-export.
#
# Real-cluster mode runs the shared kubectl collectors (lib/kubectl-collectors.sh)
# and layers on signals that change the most between vanilla clusters and EKS:
#   - Bootstrap signal (kubeadm vs cluster-api vs unknown)  → cluster.bootstrap, top-level vanilla.bootstrapper
#   - CNI plugin (calico/cilium/flannel/weave/aws-vpc-cni)  → cluster.vanilla.cni
#   - Ingress controller (ingress-nginx/traefik/...)         → cluster.vanilla.ingress_controller
#   - OS image distribution per node                         → cluster.vanilla.os_images[]
#   - kubelet version skew across nodes                      → cluster.vanilla.kubelet_skew_detected
#   - admission webhook count (validating + mutating)        → cluster.vanilla.admission_webhooks_*
#
# --dry-run mode emits a schema-valid stub via lib/output-bundle.sh::dry_run_stub.
#
# Read-only.
#
# Requirements: bash 4+, kubectl, jq.
#
# Usage:
#   ./vanilla-k8s-export.sh [--dry-run] [--output FILE] [--namespaces "ns1,ns2"]
#                            [--exclude "..."] [--cluster-name NAME]
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
EXCLUDE_NS="kube-system,kube-public,kube-node-lease"
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

[[ -z "$OUTPUT" ]] && OUTPUT="discovery-bundle-vanilla-k8s-$(date -u +%Y%m%dT%H%M%SZ).json"

acmf::common::init
trap 'rm -rf "$ACMF_TMPDIR"' EXIT

if [[ "$DRY_RUN" -eq 1 ]]; then
  acmf::common::log "Dry-run mode: emitting schema-valid stub bundle for vanilla-k8s."
  acmf::bundle::dry_run_stub "$OUTPUT" "vanilla-k8s-export-script (dry-run)" "vanilla-k8s" "mock-vanilla-cluster" "other" \
    "vanilla-k8s-export: real-cluster mode detects bootstrap (kubeadm/cluster-api), CNI (calico/cilium/flannel/aws-vpc-cni), ingress controller, OS image distribution, kubelet version skew, and admission webhook counts" \
    "vanilla-k8s-export: kubelet skew across nodes is flagged because EKS managed node groups expect uniform versions"
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

# ---- CNI detection ----
CNI="unknown"
if   kubectl -n kube-system get ds calico-node       >/dev/null 2>&1; then CNI="calico"
elif kubectl -n kube-system get ds cilium            >/dev/null 2>&1; then CNI="cilium"
elif kubectl -n kube-system get ds aws-node          >/dev/null 2>&1; then CNI="aws-vpc-cni"
elif kubectl -n kube-system get ds kube-flannel-ds   >/dev/null 2>&1; then CNI="flannel"
elif kubectl -n kube-system get ds weave-net         >/dev/null 2>&1; then CNI="weave"
fi

# ---- Ingress controller detection ----
INGRESS_CTRL="none"
for ns_pair in \
    "ingress-nginx:ingress-nginx-controller" \
    "traefik:traefik" \
    "projectcontour:contour" \
    "haproxy-ingress:haproxy-ingress"; do
  ns="${ns_pair%%:*}"
  name="${ns_pair##*:}"
  if kubectl -n "$ns" get deploy "$name" >/dev/null 2>&1; then
    INGRESS_CTRL="$ns"
    break
  fi
done

# ---- Bootstrap detection ----
BOOTSTRAP="unknown"
if kubectl -n kube-system get cm kubeadm-config >/dev/null 2>&1; then
  BOOTSTRAP="kubeadm"
elif kubectl get crd clusters.cluster.x-k8s.io >/dev/null 2>&1; then
  BOOTSTRAP="cluster-api"
fi

# ---- OS image distribution + kubelet skew ----
NODES_JSON="$(kubectl get nodes -o json 2>/dev/null || echo '{"items":[]}')"
OS_IMAGES_JSON="$(echo "$NODES_JSON" | jq '
  [(.items // [])[] | .status.nodeInfo.osImage // "unknown"]
  | group_by(.) | map({os_image: .[0], count: length})')"
KUBELET_VERS_JSON="$(echo "$NODES_JSON" | jq '
  [(.items // [])[] | .status.nodeInfo.kubeletVersion // "unknown"] | unique')"
KUBELET_SKEW="false"
if [[ "$(echo "$KUBELET_VERS_JSON" | jq 'length')" -gt 1 ]]; then
  KUBELET_SKEW="true"
fi

# ---- Admission webhooks ----
VWC_TOTAL="$(kubectl get validatingwebhookconfiguration -o json 2>/dev/null | jq '(.items // []) | length' || echo 0)"
MWC_TOTAL="$(kubectl get mutatingwebhookconfiguration  -o json 2>/dev/null | jq '(.items // []) | length' || echo 0)"
TOTAL_WEBHOOKS=$((VWC_TOTAL + MWC_TOTAL))

# Build cluster.vanilla
CLUSTER_VANILLA_JSON="$(jq -n \
  --arg cni "$CNI" \
  --arg ic "$INGRESS_CTRL" \
  --argjson os "$OS_IMAGES_JSON" \
  --argjson kv "$KUBELET_VERS_JSON" \
  --argjson skew "$KUBELET_SKEW" \
  --argjson vwc "$VWC_TOTAL" \
  --argjson mwc "$MWC_TOTAL" \
  --argjson tot "$TOTAL_WEBHOOKS" \
  '{cni:$cni, ingress_controller:$ic, os_images:$os, kubelet_versions:$kv,
    kubelet_skew_detected:$skew, admission_webhooks_total:$tot,
    admission_webhooks_validating:$vwc, admission_webhooks_mutating:$mwc}')"

# Build clusters[]
if [[ "$BOOTSTRAP" != "unknown" ]]; then
  CLUSTERS_JSON="$(jq -n --arg name "$CLUSTER_NAME" --arg ver "$K8S_VER" --argjson nc "${NODE_COUNT:-0}" \
    --arg bs "$BOOTSTRAP" --argjson van "$CLUSTER_VANILLA_JSON" \
    '[{ name:$name, version:$ver, location:"unknown", platform:"other",
        control_plane:{ ha_mode:"unknown", node_count:$nc },
        node_pools:[], anthos_version:null, anthos_config_management_version:null,
        service_mesh:{ enabled:false, type:"none", version:null },
        bootstrap:$bs, vanilla:$van }]')"
else
  CLUSTERS_JSON="$(jq -n --arg name "$CLUSTER_NAME" --arg ver "$K8S_VER" --argjson nc "${NODE_COUNT:-0}" \
    --argjson van "$CLUSTER_VANILLA_JSON" \
    '[{ name:$name, version:$ver, location:"unknown", platform:"other",
        control_plane:{ ha_mode:"unknown", node_count:$nc },
        node_pools:[], anthos_version:null, anthos_config_management_version:null,
        service_mesh:{ enabled:false, type:"none", version:null },
        vanilla:$van }]')"
fi

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
if [[ "$KUBELET_SKEW" == "true" ]]; then
  acmf::common::warn "Vanilla-k8s: kubelet version skew detected across nodes ($(echo "$KUBELET_VERS_JSON" | jq -c .)) — must be reconciled before EKS migration; managed node groups expect uniform versions."
fi
if [[ "$TOTAL_WEBHOOKS" -gt 0 ]]; then
  acmf::common::warn "Vanilla-k8s: ${TOTAL_WEBHOOKS} admission webhook(s) (${VWC_TOTAL} validating + ${MWC_TOTAL} mutating) — each must be redeployed on EKS; ensure failurePolicy/timeout values match EKS API server tolerances."
fi
if [[ "$CNI" == "unknown" ]]; then
  acmf::common::warn "Vanilla-k8s: CNI plugin not auto-detected — verify manually; EKS targets are AWS VPC CNI, Calico (Tigera), or Cilium."
fi

SCOPE_JSON="$(jq -n --arg c "$CLUSTER_NAME" --argjson inc "$NS_INCLUDED_JSON" --argjson exc "$NS_EXCLUDED_JSON" \
  '{ clusters:[$c], namespaces_included:$inc, namespaces_excluded:$exc }')"

acmf::bundle::emit "$OUTPUT" "$(acmf::common::generated_at)" "vanilla-k8s-export-script" \
  "$SCOPE_JSON" "$CLUSTERS_JSON" "$WORKLOADS_JSON" "$NETWORKING_JSON" \
  "$STORAGE_JSON" "$IDENTITY_JSON" "$EXT_JSON" "$CRDS_JSON" \
  "$VMW_JSON" "$UTIL_JSON" "$TRAFFIC_JSON"

# Layer top-level vanilla{} block when bootstrapper was identified.
if [[ "$BOOTSTRAP" != "unknown" ]]; then
  jq --arg bs "$BOOTSTRAP" '. + { vanilla: { bootstrapper: $bs } }' \
     "$OUTPUT" > "$OUTPUT.tmp" && mv "$OUTPUT.tmp" "$OUTPUT"
fi

acmf::common::log "Wrote: $OUTPUT"
acmf::common::log "Validate: npx --yes -p ajv-cli@5 -p ajv-formats@2 ajv validate -s schemas/discovery-bundle.schema.json -d $OUTPUT -c ajv-formats"
