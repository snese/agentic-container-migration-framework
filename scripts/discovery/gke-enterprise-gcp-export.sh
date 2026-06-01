#!/usr/bin/env bash
# gke-enterprise-gcp-export.sh
#
# ACMF Phase 1 (Assess) — GKE Enterprise on GCP (formerly Anthos on GCP)
# self-export. Targets standalone GKE clusters fleet-registered into
# GKE Enterprise and Anthos Config Management / Anthos Service Mesh layers.
#
# Real-cluster mode runs the shared kubectl collectors (lib/kubectl-collectors.sh)
# and layers on GCP-specific enrichment:
#   - Workload Identity bindings — every ServiceAccount with the
#     `iam.gke.io/gcp-service-account` annotation. The shared identity
#     collector (acmf::k8s::collect_identity) already extracts these into
#     identity.workload_identity_bindings[]; this script counts them and
#     emits an aggregated warning so engagement teams can size IRSA work.
#   - Config Connector (KCC) presence + managed CRD kinds
#                                                       → clusters[0].anthos.config_connector
#   - Optional `gcloud container clusters describe` enrichment when
#     gcloud is present and GCLOUD_PROJECT is set:
#                                                       → clusters[0].location
#                                                       → clusters[0].anthos.release_channel
#                                                       → clusters[0].anthos.workload_identity_pool
#   - Anthos Service Mesh (managed Istio) detection      → clusters[0].service_mesh
#
# --dry-run mode emits a schema-valid stub via lib/output-bundle.sh::dry_run_stub.
#
# Read-only.
#
# Requirements: bash 4+, kubectl, jq.  Optional: gcloud.
#
# Optional env:
#   GCLOUD_PROJECT  GCP project (enables `gcloud container clusters describe`)
#   GCLOUD_REGION   GCP region or zone (passed to describe)
#
# Usage:
#   ./gke-enterprise-gcp-export.sh [--dry-run] [--output FILE] [--namespaces ...]
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
EXCLUDE_NS="kube-system,gke-system,gmp-system,kube-public,kube-node-lease,config-management-system,gke-managed-system,gke-connect,anthos-identity-service,asm-system,istio-system"
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

[[ -z "$OUTPUT" ]] && OUTPUT="discovery-bundle-gke-enterprise-gcp-$(date -u +%Y%m%dT%H%M%SZ).json"

acmf::common::init
trap 'rm -rf "$ACMF_TMPDIR"' EXIT

if [[ "$DRY_RUN" -eq 1 ]]; then
  acmf::common::log "Dry-run mode: emitting schema-valid stub bundle for GKE Enterprise on GCP."
  acmf::bundle::dry_run_stub "$OUTPUT" "gke-enterprise-gcp-export-script (dry-run)" "gke-enterprise-gcp" "mock-gke-enterprise-cluster" "gcp" \
    "gke-enterprise-gcp-export: real-cluster mode collects Workload Identity (KSA→GSA) bindings; each pair must be rewritten as IRSA on EKS" \
    "gke-enterprise-gcp-export: Config Connector (KCC) detection — translate to AWS Controllers for Kubernetes (ACK) or Terraform/CDK; no 1:1 mapping for every GCP resource" \
    "gke-enterprise-gcp-export: gcloud container clusters describe enrichment runs only when gcloud is installed and GCLOUD_PROJECT/GCLOUD_REGION are set"
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

# ---- Service mesh detection (ASM / Istio) ----
ASM_ENABLED="false"
ASM_VER="null"
if kubectl get ns istio-system >/dev/null 2>&1 || kubectl get ns asm-system >/dev/null 2>&1; then
  ASM_ENABLED="true"
  REV="$(kubectl -n istio-system get deploy istiod -o jsonpath='{.metadata.labels.istio\.io/rev}' 2>/dev/null || echo '')"
  if [[ -n "$REV" ]]; then
    ASM_VER="\"$REV\""
  fi
fi

# ---- Config Connector (KCC) ----
acmf::common::log "Probing Config Connector (KCC)..."
CRD_JSON="$(kubectl get crd -o json 2>/dev/null || echo '{"items":[]}')"
KCC_KINDS_JSON="$(echo "$CRD_JSON" | jq '
  [(.items // [])[]
    | select((.spec.group // "") | endswith("cnrm.cloud.google.com"))
    | (.spec.names.kind // "")] | unique')"
KCC_COUNT="$(echo "$KCC_KINDS_JSON" | jq 'length')"
if [[ "$KCC_COUNT" -gt 0 ]]; then
  CONFIG_CONNECTOR_JSON="$(jq -n --argjson n "$KCC_COUNT" --argjson k "$KCC_KINDS_JSON" \
    '{installed:true, crd_count:$n, managed_resource_kinds:$k}')"
else
  CONFIG_CONNECTOR_JSON='{"installed":false,"crd_count":0,"managed_resource_kinds":[]}'
fi

# ---- gcloud control-plane enrichment (optional) ----
LOCATION="unknown"
RELEASE_CHANNEL=""
WI_POOL_JSON="null"
if acmf::common::require gcloud && [[ -n "${GCLOUD_PROJECT:-}" ]]; then
  acmf::common::log "Enriching with gcloud container clusters describe..."
  GKE_JSON=""
  if [[ -n "${GCLOUD_REGION:-}" ]]; then
    GKE_JSON="$(gcloud container clusters describe "$CLUSTER_NAME" \
                  --project="$GCLOUD_PROJECT" --region="$GCLOUD_REGION" --format=json 2>/dev/null \
                || gcloud container clusters describe "$CLUSTER_NAME" \
                  --project="$GCLOUD_PROJECT" --zone="$GCLOUD_REGION" --format=json 2>/dev/null \
                || echo '')"
  fi
  if [[ -n "$GKE_JSON" ]]; then
    LOCATION="$(echo "$GKE_JSON" | jq -r '.location // "gcp"')"
    RELEASE_CHANNEL="$(echo "$GKE_JSON" | jq -r '.releaseChannel.channel // "STABLE"')"
    WI_POOL="$(echo "$GKE_JSON" | jq -r '.workloadIdentityConfig.workloadPool // ""')"
    if [[ -n "$WI_POOL" ]]; then
      WI_POOL_JSON="\"$WI_POOL\""
    fi
  else
    acmf::common::skip "gcloud container clusters describe $CLUSTER_NAME" \
      "GCLOUD_REGION not set or describe returned empty — gcloud enrichment skipped"
  fi
else
  acmf::common::skip "gcloud container clusters describe" \
    "gcloud or GCLOUD_PROJECT not available — control-plane metadata not enriched"
fi

# Build clusters[].anthos
ANTHOS_JSON="$(jq -n --argjson cc "$CONFIG_CONNECTOR_JSON" --arg rc "$RELEASE_CHANNEL" --argjson wi "$WI_POOL_JSON" '
  ({config_connector:$cc, workload_identity_pool:$wi}
   | if ($rc | length) > 0 then . + {release_channel:$rc} else . end)
')"

# Build clusters[]
CLUSTERS_JSON="$(jq -n --arg name "$CLUSTER_NAME" --arg ver "$K8S_VER" --arg loc "$LOCATION" \
  --argjson nc "${NODE_COUNT:-0}" --argjson asm "$ASM_ENABLED" --argjson asmv "$ASM_VER" \
  --argjson anthos "$ANTHOS_JSON" \
  '[{ name:$name, version:$ver, location:$loc, platform:"gcp",
      control_plane:{ ha_mode:"unknown", node_count:$nc },
      node_pools:[], anthos_version:null, anthos_config_management_version:null,
      service_mesh:{ enabled:$asm, type:(if $asm then "asm" else "none" end), version:$asmv },
      anthos:$anthos }]')"

# K8s core layers via shared collectors. Identity collector already extracts
# Workload Identity bindings via the iam.gke.io/gcp-service-account annotation.
WORKLOADS_JSON="$(acmf::k8s::collect_workloads "$NS_LIST" "$CLUSTER_NAME")"
NETWORKING_JSON="$(acmf::k8s::collect_networking "$NS_LIST" "$CLUSTER_NAME")"
STORAGE_JSON="$(acmf::k8s::collect_storage "$NS_LIST" "$CLUSTER_NAME")"
IDENTITY_JSON="$(acmf::k8s::collect_identity "$NS_LIST" "$CLUSTER_NAME")"
CRDS_JSON="$(acmf::k8s::collect_crds)"

# Count Workload Identity bindings for the warning.
WI_COUNT="$(echo "$IDENTITY_JSON" | jq '(.workload_identity_bindings // []) | length')"

EXT_JSON="[]"
VMW_JSON='{"clusters":[],"hosts":[],"datastores":[],"vm_to_node_mapping":[]}'
UTIL_JSON='{"nodes":[],"pods":[],"summary":{"cluster_cpu_utilization_pct":0.0,"cluster_memory_utilization_pct":0.0,"over_provisioning_ratio":0.0,"metrics_source":null}}'
TRAFFIC_JSON='{"pairs":[],"summary":{"east_west_bytes_per_sec":0,"north_south_bytes_per_sec":0,"total_service_pairs":0,"telemetry_source":null}}'

# Precise warnings.
if [[ "$WI_COUNT" -gt 0 ]]; then
  acmf::common::warn "GKE Enterprise on GCP: ${WI_COUNT} Workload Identity binding(s) — each KSA→GSA pair must be rewritten as an IRSA role on EKS (annotation eks.amazonaws.com/role-arn + IAM trust policy)."
fi
if [[ "$KCC_COUNT" -gt 0 ]]; then
  acmf::common::warn "GKE Enterprise on GCP: Config Connector (KCC) detected with ${KCC_COUNT} managed CRD kinds — translate to AWS Controllers for Kubernetes (ACK) or Terraform/CDK; no 1:1 type mapping for every GCP resource."
fi

SCOPE_JSON="$(jq -n --arg c "$CLUSTER_NAME" --argjson inc "$NS_INCLUDED_JSON" --argjson exc "$NS_EXCLUDED_JSON" \
  '{ clusters:[$c], namespaces_included:$inc, namespaces_excluded:$exc }')"

acmf::bundle::emit "$OUTPUT" "$(acmf::common::generated_at)" "gke-enterprise-gcp-export-script" \
  "$SCOPE_JSON" "$CLUSTERS_JSON" "$WORKLOADS_JSON" "$NETWORKING_JSON" \
  "$STORAGE_JSON" "$IDENTITY_JSON" "$EXT_JSON" "$CRDS_JSON" \
  "$VMW_JSON" "$UTIL_JSON" "$TRAFFIC_JSON"

acmf::common::log "Wrote: $OUTPUT"
acmf::common::log "Validate: npx --yes -p ajv-cli@5 -p ajv-formats@2 ajv validate -s schemas/discovery-bundle.schema.json -d $OUTPUT -c ajv-formats"
