#!/usr/bin/env bash
# gke-enterprise-baremetal-export.sh
#
# ACMF Phase 1 (Assess) — GKE Enterprise on Bare Metal (formerly Anthos
# clusters on bare metal) self-export.
#
# Real-cluster mode runs the shared kubectl collectors (lib/kubectl-collectors.sh)
# and layers on bare-metal-specific enrichment:
#   - Anthos bare-metal admin CRDs (cluster.baremetal.cluster.gke.io) when present
#                                                       → clusters[0].anthos.{baremetal_cluster_count, baremetal_cluster_names}
#   - Hardware-bound workload mining: hostNetwork, privileged, GPU, SR-IOV,
#     Multus annotations, hostPath, hostPID, hostIPC, RDMA, FPGA, hugepages
#                                                       → workloads_hardware_bound[]
#   Each hardware-bound workload requires SME triage for AWS placement
#   (EC2 *.metal vs ENA/EFA vs redesign).
#
# Out of scope (true SME items, not collected by the script):
#   - BMC/Redfish/IPMI hardware inventory (out-of-band channel)
#   - GPU driver compatibility matrix (NVIDIA driver vs CUDA vs EKS AMI)
#
# --dry-run mode emits a schema-valid stub via lib/output-bundle.sh::dry_run_stub.
#
# Read-only.
#
# Requirements: bash 4+, kubectl, jq.
#
# Usage:
#   ./gke-enterprise-baremetal-export.sh [--dry-run] [--output FILE] [--namespaces ...]
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
EXCLUDE_NS="kube-system,gke-system,gmp-system,kube-public,kube-node-lease,config-management-system,gke-managed-system,gke-connect,anthos-identity-service,asm-system,istio-system,anthos-creds,anthos-cluster-operator"
CLUSTER_NAME=""

usage() { sed -n '2,40p' "$0"; exit 2; }

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

[[ -z "$OUTPUT" ]] && OUTPUT="discovery-bundle-gke-enterprise-baremetal-$(date -u +%Y%m%dT%H%M%SZ).json"

acmf::common::init
trap 'rm -rf "$ACMF_TMPDIR"' EXIT

if [[ "$DRY_RUN" -eq 1 ]]; then
  acmf::common::log "Dry-run mode: emitting schema-valid stub bundle for GKE Enterprise on Bare Metal."
  acmf::bundle::dry_run_stub "$OUTPUT" "gke-enterprise-baremetal-export-script (dry-run)" "gke-enterprise-baremetal" "mock-baremetal-cluster" "baremetal" \
    "gke-enterprise-baremetal-export: real-cluster mode mines workloads for hostNetwork, privileged, GPU, SR-IOV, Multus, hostPath, hostPID, hostIPC, RDMA, FPGA, hugepages — each hit needs SME triage for AWS placement" \
    "gke-enterprise-baremetal-export: BMC/Redfish/IPMI hardware inventory + driver-version matrices remain SME items — bring rack/chassis docs to architecture review"
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

# ---- Anthos bare-metal CRDs ----
ANTHOS_BM_JSON="{}"
if kubectl get crd cluster.baremetal.cluster.gke.io >/dev/null 2>&1; then
  BM_JSON="$(kubectl get cluster.baremetal.cluster.gke.io -A -o json 2>/dev/null || echo '{"items":[]}')"
  # Default to valid JSON so --argjson below can never get empty/non-JSON input.
  BM_COUNT="$(echo "$BM_JSON" | jq '(.items // []) | length')"; BM_COUNT="${BM_COUNT:-0}"
  BM_NAMES_JSON="$(echo "$BM_JSON" | jq -c '[(.items // [])[] | .metadata.name]')"; BM_NAMES_JSON="${BM_NAMES_JSON:-[]}"
  ANTHOS_BM_JSON="$(jq -n --argjson c "$BM_COUNT" --argjson names "$BM_NAMES_JSON" \
    '{baremetal_cluster_count:$c, baremetal_cluster_names:$names}')"
else
  acmf::common::skip "kubectl get cluster.baremetal.cluster.gke.io" \
    "Anthos bare-metal CRDs not present (likely a user cluster, not admin)"
fi

# ---- Hardware-bound workload mining ----
acmf::common::log "Mining workloads for hardware-bound signals..."
WORKLOADS_RAW_JSON="$(kubectl get deploy,sts,ds,job,cronjob -A -o json 2>/dev/null || echo '{"items":[]}')"
HW_BOUND_JSON="$(echo "$WORKLOADS_RAW_JSON" | jq '
  def pod_spec(item):
    (item.spec.template.spec
      // item.spec.jobTemplate.spec.template.spec
      // null);
  def pod_meta(item):
    (item.spec.template.metadata
      // item.spec.jobTemplate.spec.template.metadata
      // {});
  def detect(item):
    pod_spec(item) as $ps
    | pod_meta(item) as $pm
    | if $ps == null then [] else
        [
          (if ($ps.hostNetwork // false) then "hostNetwork" else empty end),
          (if ($ps.hostPID // false) then "hostPID" else empty end),
          (if ($ps.hostIPC // false) then "hostIPC" else empty end),
          (if (($ps.containers // []) | any(.securityContext.privileged == true))
             or (($ps.initContainers // []) | any(.securityContext.privileged == true))
           then "privileged" else empty end),
          (if (($ps.containers // []) | any(
                ((.resources.limits // {}) | keys) | any(. == "nvidia.com/gpu" or test("amd.com/gpu"; "i") or test("gpu"; "i"))
              )) then "gpu" else empty end),
          (if (($ps.containers // []) | any(
                ((.resources.limits // {}) | keys) | any(test("sriov"; "i"))
              )) then "sriov" else empty end),
          (if ($pm.annotations // {}) | has("k8s.v1.cni.cncf.io/networks")
             then "multus_annotation" else empty end),
          (if (($ps.volumes // []) | any(.hostPath != null))
             then "hostPath" else empty end),
          (if (($ps.containers // []) | any(
                ((.resources.limits // {}) | keys) | any(startswith("hugepages-"))
              )) then "huge_pages" else empty end),
          (if (($ps.containers // []) | any(
                ((.resources.limits // {}) | keys) | any(startswith("rdma/"))
              )) then "rdma" else empty end),
          (if (($ps.containers // []) | any(
                ((.resources.limits // {}) | keys) | any(test("fpga"; "i"))
              )) then "fpga" else empty end)
        ]
      end;
  [(.items // [])[]
    | . as $w
    | detect($w) as $reasons
    | select(($reasons | length) > 0)
    | {
        namespace: $w.metadata.namespace,
        name: $w.metadata.name,
        kind: ($w.kind // "Other"),
        reasons: ($reasons | unique),
        detail: ("Detected: " + ($reasons | unique | join(", ")))
      }
  ]
')"
HW_COUNT="$(echo "$HW_BOUND_JSON" | jq 'length')"

# Build clusters[]
CLUSTERS_JSON="$(jq -n --arg name "$CLUSTER_NAME" --arg ver "$K8S_VER" --argjson nc "${NODE_COUNT:-0}" \
  --argjson anthos "$ANTHOS_BM_JSON" \
  '[{ name:$name, version:$ver, location:"on-prem-baremetal", platform:"baremetal",
      control_plane:{ ha_mode:"unknown", node_count:$nc },
      node_pools:[], anthos_version:null, anthos_config_management_version:null,
      service_mesh:{ enabled:false, type:"none", version:null }
    }
    | if ($anthos | length) > 0 then . + { anthos: $anthos } else . end ]')"

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

# Precise warnings.
if [[ "$HW_COUNT" -gt 0 ]]; then
  acmf::common::warn "GKE Enterprise on Bare Metal: ${HW_COUNT} hardware-bound workload(s) detected (hostNetwork/privileged/GPU/SR-IOV/Multus/hostPath/etc.) — each needs SME triage for AWS placement (EC2 *.metal vs ENA/EFA vs redesign). See workloads_hardware_bound[]."
fi
acmf::common::warn "GKE Enterprise on Bare Metal: BMC/Redfish/IPMI hardware inventory + driver-version matrices remain SME items — bring rack/chassis docs to architecture review."

SCOPE_JSON="$(jq -n --arg c "$CLUSTER_NAME" --argjson inc "$NS_INCLUDED_JSON" --argjson exc "$NS_EXCLUDED_JSON" \
  '{ clusters:[$c], namespaces_included:$inc, namespaces_excluded:$exc }')"

acmf::bundle::emit "$OUTPUT" "$(acmf::common::generated_at)" "gke-enterprise-baremetal-export-script" \
  "$SCOPE_JSON" "$CLUSTERS_JSON" "$WORKLOADS_JSON" "$NETWORKING_JSON" \
  "$STORAGE_JSON" "$IDENTITY_JSON" "$EXT_JSON" "$CRDS_JSON" \
  "$VMW_JSON" "$UTIL_JSON" "$TRAFFIC_JSON"

# Layer top-level workloads_hardware_bound[] when any hits were found.
if [[ "$HW_COUNT" -gt 0 ]]; then
  jq --argjson hw "$HW_BOUND_JSON" '. + { workloads_hardware_bound: $hw }' \
     "$OUTPUT" > "$OUTPUT.tmp" && mv "$OUTPUT.tmp" "$OUTPUT"
fi

acmf::common::log "Wrote: $OUTPUT"
acmf::common::log "Validate: npx --yes -p ajv-cli@5 -p ajv-formats@2 ajv validate -s schemas/discovery-bundle.schema.json -d $OUTPUT -c ajv-formats"
