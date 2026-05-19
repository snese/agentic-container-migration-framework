#!/usr/bin/env bash
# gke-export.sh
#
# ACMF Phase 1 (Assess) — GKE (cloud-native) self-export discovery script.
#
# STATUS: 🟡 Stub — entry point exists, dry-run mode emits a schema-valid
# bundle. Real-cluster collection is delegated to the shared
# kubectl-collectors but several GKE-specific concerns are still
# pending (see [STUB] markers below).
#
# Produces a JSON discovery bundle conforming to:
#   schemas/discovery-bundle.schema.json (v0.2.0)
#
# Read-only. Redacts secrets. Skips on failure (logs to "skipped" / "warnings").
#
# Requirements:
#   - bash 4+, kubectl, jq
#   - Optional: gcloud (GKE metadata, IAM Workload Identity bindings)
#
# Usage:
#   ./gke-export.sh [--dry-run] [--output FILE] [--namespaces "ns1,ns2"]
#                   [--exclude "kube-system,..."] [--cluster-name NAME]
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
EXCLUDE_NS="kube-system,gke-system,gmp-system,kube-public,kube-node-lease"
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

[[ -z "$OUTPUT" ]] && OUTPUT="discovery-bundle-gke-$(date -u +%Y%m%dT%H%M%SZ).json"

acmf::common::init
trap 'rm -rf "$ACMF_TMPDIR"' EXIT

if [[ "$DRY_RUN" -eq 1 ]]; then
  acmf::common::log "Dry-run mode: emitting schema-valid stub bundle for GKE."
  acmf::bundle::dry_run_stub "$OUTPUT" "gke-export-script (dry-run)" "gke" "mock-gke-cluster" "gcp" \
    "[STUB] gke-export: GKE Workload Identity (KSA -> GSA) collection pending — gcloud iam policy bindings" \
    "[STUB] gke-export: Autopilot vs Standard cluster mode detection pending — gcloud container clusters describe"
  acmf::common::log "Wrote stub bundle: $OUTPUT"
  exit 0
fi

# ------------------------- Real collection -------------------------
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

acmf::common::log "Collecting cluster info..."
K8S_VER="$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion // "unknown"')"
NODE_COUNT="$(kubectl get nodes -o json 2>/dev/null | jq '.items | length')"
CLUSTERS_JSON="$(jq -n --arg name "$CLUSTER_NAME" --arg ver "$K8S_VER" --argjson nc "${NODE_COUNT:-0}" \
  '[{ name:$name, version:$ver, location:"unknown", platform:"gcp",
      control_plane:{ ha_mode:"unknown", node_count:$nc },
      node_pools:[],
      anthos_version:null,
      anthos_config_management_version:null,
      service_mesh:{ enabled:false, type:"none", version:null } }]')"

# [STUB] gke-export: enrich CLUSTERS_JSON with `gcloud container clusters describe`
# to populate node_pools, autopilot mode, release channel, location.
acmf::common::skip "gcloud container clusters describe" "[STUB] not yet wired — see ROADMAP"

WORKLOADS_JSON="$(acmf::k8s::collect_workloads "$NS_LIST" "$CLUSTER_NAME")"
NETWORKING_JSON="$(acmf::k8s::collect_networking "$NS_LIST" "$CLUSTER_NAME")"
STORAGE_JSON="$(acmf::k8s::collect_storage "$NS_LIST" "$CLUSTER_NAME")"
IDENTITY_JSON="$(acmf::k8s::collect_identity "$NS_LIST" "$CLUSTER_NAME")"
CRDS_JSON="$(acmf::k8s::collect_crds)"

EXT_JSON="[]"
VMW_JSON='{"clusters":[],"hosts":[],"datastores":[],"vm_to_node_mapping":[]}'
UTIL_JSON='{"nodes":[],"pods":[],"summary":{"cluster_cpu_utilization_pct":0.0,"cluster_memory_utilization_pct":0.0,"over_provisioning_ratio":0.0,"metrics_source":null}}'
TRAFFIC_JSON='{"pairs":[],"summary":{"east_west_bytes_per_sec":0,"north_south_bytes_per_sec":0,"total_service_pairs":0,"telemetry_source":null}}'
acmf::common::skip "traffic-telemetry" "Cloud Monitoring / VPC flow logs not queried by this script"

SCOPE_JSON="$(jq -n --arg c "$CLUSTER_NAME" --argjson inc "$NS_INCLUDED_JSON" --argjson exc "$NS_EXCLUDED_JSON" \
  '{ clusters:[$c], namespaces_included:$inc, namespaces_excluded:$exc }')"

acmf::bundle::emit "$OUTPUT" "$(acmf::common::generated_at)" "gke-export-script" \
  "$SCOPE_JSON" "$CLUSTERS_JSON" "$WORKLOADS_JSON" "$NETWORKING_JSON" \
  "$STORAGE_JSON" "$IDENTITY_JSON" "$EXT_JSON" "$CRDS_JSON" \
  "$VMW_JSON" "$UTIL_JSON" "$TRAFFIC_JSON"

acmf::common::log "Wrote: $OUTPUT"
acmf::common::log "Validate: npx --yes ajv-cli validate -s schemas/discovery-bundle.schema.json -d $OUTPUT"
