#!/usr/bin/env bash
# openshift-export.sh
#
# ACMF Phase 1 (Assess) — Red Hat OpenShift Container Platform (OCP) self-export.
#
# Real-cluster mode runs the shared kubectl collectors (lib/kubectl-collectors.sh)
# and layers on OpenShift-specific enrichment via the `oc` CLI when available:
#   - ClusterVersion (current_version, channel)        → clusters[0].openshift
#   - Infrastructure / ROSA detection                  → openshift.{is_rosa, infrastructure_provider}
#                                                        and cluster.platform set to "aws" when ROSA.
#   - Routes total                                     → openshift.openshift_routes_total
#   - ImageStreams + BuildConfigs total (S2I signal)   → openshift.{image_streams_total, build_configs_total}
#   - OLM Subscriptions with AWS migration rating      → openshift.subscriptions[]
#     (rating ∈ easy/hard/blocker/unknown — see adapters/source/openshift/mapping.md)
#   - MachineConfigPool ready/total                    → openshift.machine_config_pools[]
#   - Effective SCC bindings per namespace             → openshift.scc_usage[]
#   - SecurityContextConstraints inventory             → openshift.scc_total
#
# --dry-run mode emits the same schema-valid stub bundle that the other adapters
# use (see lib/output-bundle.sh::acmf::bundle::dry_run_stub). The real-cluster
# enrichment above is layered on only when --dry-run is *not* set.
#
# Read-only. Redacts secrets via the shared collectors. Skips on failure
# (logs to bundle.skipped[] / bundle.warnings[]).
#
# Requirements: bash 4+, kubectl, jq. Optional: oc CLI (highly recommended).
#
# Usage:
#   ./openshift-export.sh [--dry-run] [--output FILE] [--namespaces "ns1,ns2"]
#                         [--exclude "kube-system,..."] [--cluster-name NAME]
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
EXCLUDE_NS="kube-system,kube-public,kube-node-lease,openshift,openshift-apiserver,openshift-authentication,openshift-controller-manager,openshift-dns,openshift-etcd,openshift-ingress,openshift-monitoring,openshift-operators,openshift-marketplace,openshift-machine-api,openshift-machine-config-operator,openshift-network-operator,openshift-image-registry,openshift-operator-lifecycle-manager,openshift-cluster-version,openshift-kube-apiserver,openshift-kube-controller-manager,openshift-kube-scheduler,openshift-sdn,openshift-service-ca,openshift-node"
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

[[ -z "$OUTPUT" ]] && OUTPUT="discovery-bundle-openshift-$(date -u +%Y%m%dT%H%M%SZ).json"

acmf::common::init
trap 'rm -rf "$ACMF_TMPDIR"' EXIT

# ---------------------------------------------------------------------------
# OpenShift Operator → AWS migration rating table.
#
# Echoes "rating|aws_target|rationale" for the given Operator package name.
# Empty string if not in the table → caller marks "unknown".
#
# Sources of truth:
#   - AWS-managed equivalents per the AWS docs (Amazon EKS, RDS, MSK, AMP/AMG…)
#   - When AWS has no native equivalent (KubeVirt, ODF/Ceph, MetalLB, WMCO,
#     SR-IOV/PTP), we mark 'blocker' with a redesign rationale rather than guess.
# ---------------------------------------------------------------------------
acmf::openshift::operator_rating() {
  local pkg="$1"
  case "$pkg" in
    # === easy: drop-in or 1:1 with AWS-managed equivalent ===
    cert-manager-operator|cert-manager)
      echo "easy|AWS Certificate Manager (ACM) for public certs; cert-manager-on-EKS for in-cluster|cert-manager runs on EKS unchanged; ACM replaces public-facing TLS issuance" ;;
    openshift-pipelines-operator-rh|tektoncd-operator)
      echo "easy|AWS CodePipeline + CodeBuild, or Tekton on EKS|Tekton CRDs portable to EKS; AWS-native CI is the typical move" ;;
    openshift-gitops-operator|argocd-operator)
      echo "easy|Argo CD on EKS|Drop-in; manifests portable" ;;
    cluster-logging|elasticsearch-operator|loki-operator)
      echo "easy|Amazon CloudWatch Logs / OpenSearch Service / Loki-on-EKS|Logging stack swap is mechanical; data-retention policy needs SME review" ;;
    cluster-monitoring-operator|prometheus-operator|kube-prometheus-stack)
      echo "easy|Amazon Managed Prometheus (AMP) + Amazon Managed Grafana (AMG)|ServiceMonitor/PodMonitor CRDs are portable; AMP stores metrics, AMG visualizes" ;;
    external-dns-operator|external-dns)
      echo "easy|external-dns on EKS with Route 53 provider|Drop-in; switch provider flag" ;;
    nfd|nfd-operator|node-feature-discovery-operator)
      echo "easy|Node Feature Discovery on EKS|Same operator runs on EKS" ;;
    gpu-operator-certified|nvidia-gpu-operator)
      echo "easy|NVIDIA GPU Operator on EKS (g5/p4/p5 instances)|Driver versions usually match between OCP and EKS-optimized AMI; instance class is the call" ;;
    redhat-oadp-operator|oadp-operator|velero)
      echo "easy|AWS Backup for Amazon EKS or Velero on EKS|Velero portable; AWS Backup integrates with IAM" ;;
    kasten-k10|k10-kasten-operator)
      echo "easy|AWS Backup for Amazon EKS, Velero on EKS, or Kasten K10 on EKS|Same Kasten product runs on EKS; or swap to AWS Backup" ;;

    # === hard: significant rewrite required, but feasible ===
    rhsso-operator|keycloak-operator|sso-operator)
      echo "hard|Amazon Cognito or AWS IAM Identity Center; or Keycloak on EKS|IdP migration is its own work stream; URL/realm/client config rebuild" ;;
    strimzi-kafka-operator|amq-streams)
      echo "hard|Amazon MSK (managed Kafka), or Strimzi on EKS|Topic/ACL replication via MirrorMaker2; broker-to-MSK semantics differ on storage" ;;
    crunchy-postgres-operator|postgresql-operator|cloud-native-postgresql|postgres-operator)
      echo "hard|Amazon RDS / Aurora PostgreSQL, or Postgres Operator on EKS|Operator-managed Postgres → managed RDS; failover, backup, PITR semantics change" ;;
    mongodb-enterprise|mongodb-atlas-kubernetes|percona-server-mongodb-operator)
      echo "hard|Amazon DocumentDB or MongoDB Atlas (3rd-party)|API compatibility caveats with DocumentDB; Atlas is 1:1 but external" ;;
    serverless-operator|knative-operator)
      echo "hard|AWS Lambda, AWS App Runner, or Knative on EKS|Knative Service → App Runner is closest match for HTTP; Eventing → EventBridge" ;;
    servicemeshoperator|istio-operator|maistra-operator)
      echo "hard|Istio on Amazon EKS, Amazon VPC Lattice, or App Mesh|Istio CRDs portable; Maistra-specific extensions need rewrite" ;;
    jaeger-operator|opentelemetry-operator)
      echo "hard|AWS X-Ray or OpenTelemetry Collector on EKS|OTel collector portable; X-Ray as native target requires exporter swap" ;;
    elasticsearch-eck-operator|eck-operator)
      echo "hard|Amazon OpenSearch Service, or ECK on EKS|Index/snapshot migration via CCR or _reindex" ;;
    redis-enterprise-operator)
      echo "hard|Amazon ElastiCache for Redis, or Redis Enterprise on EKS|Failover/persistence semantics differ" ;;
    rabbitmq-cluster-operator)
      echo "hard|Amazon MQ for RabbitMQ, or RabbitMQ Operator on EKS|Managed AMQ has version constraints" ;;
    submariner|submariner-operator)
      echo "hard|AWS Transit Gateway + VPC peering|Cross-cluster L3 connectivity via AWS networking, not overlay" ;;
    compliance-operator|file-integrity-operator)
      echo "hard|Amazon Inspector + AWS Config + AWS Audit Manager|Compliance scan model differs (agent vs API)" ;;
    aci-containers-operator|cilium-enterprise)
      echo "hard|Cilium on EKS or VPC CNI Network Policies|Cilium-on-EKS supported; ACI/Cisco-specific features may not port" ;;

    # === blocker: no native AWS equivalent; redesign required ===
    kubevirt-hyperconverged|cnv-operator|hyperconverged-cluster-operator|openshift-cnv-operator|kubevirt-operator)
      echo "blocker|Amazon EC2 (no K8s-native VM platform on EKS)|KubeVirt VMs are not containers; lift to EC2 or refactor to containers — separate work stream" ;;
    metallb-operator|metallb)
      echo "blocker|AWS Load Balancer Controller (ALB/NLB)|MetalLB BGP/L2 model has no AWS equivalent; LoadBalancer Services become managed ALB/NLB" ;;
    ocs-operator|odf-operator|odf-csi-addons-operator|local-storage-operator)
      echo "blocker|Amazon EBS / EFS / FSx for Lustre / Amazon S3 (per-tier redesign)|Ceph/ODF is converged storage; AWS splits block/file/object — storage tiering must be redesigned" ;;
    windows-machine-config-operator|wmco)
      echo "blocker|Windows worker nodes on Amazon EKS|EKS supports Windows nodes but provisioning/AMI model differs from MCO" ;;
    ptp-operator|sriov-network-operator)
      echo "blocker|Amazon EC2 with Elastic Fabric Adapter (EFA) / ENA|Telco/NFV hardware features (PTP, SR-IOV) are not exposed identically on EKS managed nodes" ;;
    nmstate-operator)
      echo "blocker|Amazon VPC + EC2 networking primitives|Bare-metal NIC bonding/VLAN config replaced by VPC + ENI patterns" ;;

    *) echo "" ;;
  esac
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  acmf::common::log "Dry-run mode: emitting schema-valid stub bundle for OpenShift."
  acmf::bundle::dry_run_stub "$OUTPUT" "openshift-export-script (dry-run)" "openshift" "mock-ocp-cluster" "other" \
    "openshift-export: real-cluster mode collects ClusterVersion, Routes, ImageStreams, BuildConfigs, OLM Subscriptions (with easy/hard/blocker/unknown rating), MachineConfigPools, and effective SCC bindings via the oc CLI" \
    "openshift-export: ROSA detection via 'oc get infrastructure cluster' — when ROSA, cluster.platform is set to 'aws'"
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

# ---- Layer in OpenShift control-plane signals via oc ----
OPENSHIFT_BLOCK_JSON='{}'        # top-level openshift{} block
CLUSTER_OPENSHIFT_JSON='null'    # clusters[0].openshift{} block
PLATFORM_ENUM="other"            # cluster.platform — flips to "aws" if ROSA
IS_ROSA="false"
INFRA_PROVIDER="unknown"
UNKNOWN_OP_COUNT=0
SCC_USAGE_COUNT=0
ROUTES_TOTAL=0

if acmf::common::require oc; then
  acmf::common::log "Collecting OpenShift-specific resources via oc..."

  # ClusterVersion → clusters[0].openshift
  CV_JSON="$(oc get clusterversion version -o json 2>/dev/null || echo '{}')"
  if [[ -n "$CV_JSON" && "$CV_JSON" != "{}" ]]; then
    CURRENT_VER="$(echo "$CV_JSON" | jq -r '.status.desired.version // "unknown"')"
    CHANNEL="$(echo "$CV_JSON" | jq -r '.spec.channel // "stable"')"
    CLUSTER_OPENSHIFT_JSON="$(jq -n --arg v "$CURRENT_VER" --arg c "$CHANNEL" '{current_version:$v, channel:$c}')"
  else
    acmf::common::skip "oc get clusterversion version" "ClusterVersion not readable (RBAC?) — clusters[0].openshift skipped"
  fi

  # Infrastructure → ROSA detection
  INFRA_JSON="$(oc get infrastructure cluster -o json 2>/dev/null || echo '{}')"
  INFRA_PROVIDER="$(echo "$INFRA_JSON" | jq -r '.status.platform // "unknown"')"
  # ROSA-classic: AWS + red-hat-managed=true tag. ROSA-HCP: AWS + controlPlaneTopology=External.
  if echo "$INFRA_JSON" | jq -e '(.status.platform == "AWS") and ((.status.platformStatus.aws.resourceTags // []) | any(.key == "red-hat-managed" and .value == "true"))' >/dev/null 2>&1; then
    IS_ROSA="true"
  elif [[ "$INFRA_PROVIDER" == "AWS" ]] && echo "$INFRA_JSON" | jq -e '.status.controlPlaneTopology == "External"' >/dev/null 2>&1; then
    IS_ROSA="true"
  fi
  # Map cluster.platform: ROSA → aws (since hosted on AWS); else stay "other".
  if [[ "$IS_ROSA" == "true" ]]; then
    PLATFORM_ENUM="aws"
  fi

  # Routes
  ROUTES_JSON="$(oc get route -A -o json 2>/dev/null || echo '{"items":[]}')"
  ROUTES_TOTAL="$(echo "$ROUTES_JSON" | jq '.items | length')"

  # ImageStreams + BuildConfigs (S2I signal)
  IS_JSON="$(oc get imagestream -A -o json 2>/dev/null || echo '{"items":[]}')"
  BC_JSON="$(oc get buildconfig -A -o json 2>/dev/null || echo '{"items":[]}')"
  IS_TOTAL="$(echo "$IS_JSON" | jq '.items | length')"
  BC_TOTAL="$(echo "$BC_JSON" | jq '.items | length')"

  # OLM Subscriptions
  SUB_JSON="$(oc get subscription -A -o json 2>/dev/null || echo '{"items":[]}')"
  SUBS_ARRAY="[]"
  SUB_COUNT="$(echo "$SUB_JSON" | jq '.items | length')"
  SUB_I=0
  while [[ "$SUB_I" -lt "$SUB_COUNT" ]]; do
    PKG="$(echo "$SUB_JSON" | jq -r ".items[$SUB_I].spec.name // \"unknown\"")"
    SUB_NS="$(echo "$SUB_JSON" | jq -r ".items[$SUB_I].metadata.namespace // \"\"")"
    SUB_NAME="$(echo "$SUB_JSON" | jq -r ".items[$SUB_I].metadata.name // \"\"")"
    SUB_CHANNEL="$(echo "$SUB_JSON" | jq -r ".items[$SUB_I].spec.channel // \"\"")"
    SUB_SOURCE="$(echo "$SUB_JSON" | jq -r ".items[$SUB_I].spec.source // \"\"")"
    RATING_STR="$(acmf::openshift::operator_rating "$PKG")"
    if [[ -z "$RATING_STR" ]]; then
      RATING="unknown"
      AWS_TARGET=""
      RATIONALE="Operator '$PKG' not in built-in rating table; SME review required."
      UNKNOWN_OP_COUNT=$((UNKNOWN_OP_COUNT + 1))
    else
      RATING="${RATING_STR%%|*}"
      REST="${RATING_STR#*|}"
      AWS_TARGET="${REST%%|*}"
      RATIONALE="${REST#*|}"
    fi
    ENTRY="$(jq -n \
      --arg ns "$SUB_NS" --arg name "$SUB_NAME" --arg pkg "$PKG" \
      --arg ch "$SUB_CHANNEL" --arg src "$SUB_SOURCE" \
      --arg rating "$RATING" --arg target "$AWS_TARGET" --arg rat "$RATIONALE" \
      '{namespace:$ns, name:$name, package:$pkg, channel:$ch, source:$src,
        migration_rating: {rating:$rating, aws_target:$target, rationale:$rat}}')"
    SUBS_ARRAY="$(jq -n --argjson a "$SUBS_ARRAY" --argjson e "$ENTRY" '$a + [$e]')"
    SUB_I=$((SUB_I + 1))
  done

  # MachineConfigPool
  MCP_JSON="$(oc get machineconfigpool -o json 2>/dev/null || echo '{"items":[]}')"
  MCP_ARRAY="$(echo "$MCP_JSON" | jq '[ (.items // [])[] | { name:.metadata.name, ready:(.status.readyMachineCount // null), total:(.status.machineCount // null) } ]')"

  # SCCs + effective SCC bindings
  RB_JSON="$(oc get rolebinding -A -o json 2>/dev/null || echo '{"items":[]}')"
  CRB_JSON="$(oc get clusterrolebinding -o json 2>/dev/null || echo '{"items":[]}')"
  SCC_USAGE="$(jq -n \
    --argjson rb "$RB_JSON" \
    --argjson crb "$CRB_JSON" '
    def extract:
      .items // []
      | map(select(.roleRef.name | tostring | startswith("system:openshift:scc:")))
      | map({
          scc: (.roleRef.name | sub("^system:openshift:scc:"; "")),
          namespace: (.metadata.namespace // null),
          binding_name: .metadata.name,
          subjects: (.subjects // [])
        });
    ($rb | extract) + ($crb | extract)
    ')"
  SCC_USAGE_COUNT="$(echo "$SCC_USAGE" | jq 'length')"

  SCC_JSON="$(oc get scc -o json 2>/dev/null || echo '{"items":[]}')"
  SCC_TOTAL="$(echo "$SCC_JSON" | jq '(.items // []) | length')"

  OPENSHIFT_BLOCK_JSON="$(jq -n \
    --arg provider "$INFRA_PROVIDER" \
    --argjson rosa "$IS_ROSA" \
    --argjson is_total "${IS_TOTAL:-0}" \
    --argjson bc_total "${BC_TOTAL:-0}" \
    --argjson routes_total "${ROUTES_TOTAL:-0}" \
    --argjson scc_total "${SCC_TOTAL:-0}" \
    --argjson subs "$SUBS_ARRAY" \
    --argjson mcp "$MCP_ARRAY" \
    --argjson scc "$SCC_USAGE" \
    '{ infrastructure_provider:$provider,
       is_rosa:$rosa,
       openshift_routes_total:$routes_total,
       image_streams_total:$is_total,
       build_configs_total:$bc_total,
       scc_total:$scc_total,
       subscriptions:$subs,
       machine_config_pools:$mcp,
       scc_usage:$scc }')"
else
  acmf::common::skip "oc get clusterversion,infrastructure,route,imagestream,buildconfig,subscription,machineconfigpool,scc" \
    "oc CLI not installed; OpenShift-specific objects not collected"
  acmf::common::warn "openshift-export: oc CLI not found — only K8s core layer collected; install oc for full OpenShift enrichment"
fi

# Build clusters array — start from kubectl version + node count, add per-cluster
# openshift block when ClusterVersion was readable.
CLUSTERS_JSON="$(jq -n --arg name "$CLUSTER_NAME" --arg ver "$K8S_VER" --argjson nc "${NODE_COUNT:-0}" \
  --arg plat "$PLATFORM_ENUM" --argjson ocp "$CLUSTER_OPENSHIFT_JSON" \
  '[{ name:$name, version:$ver, location:"unknown", platform:$plat,
      control_plane:{ ha_mode:"unknown", node_count:$nc },
      node_pools:[], anthos_version:null, anthos_config_management_version:null,
      service_mesh:{ enabled:false, type:"none", version:null } }
    | if $ocp != null then . + { openshift:$ocp } else . end ]')"

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
if [[ "$UNKNOWN_OP_COUNT" -gt 0 ]]; then
  acmf::common::warn "OpenShift: ${UNKNOWN_OP_COUNT} Operator(s) not in built-in rating table — SME review required (see openshift.subscriptions[] where migration_rating.rating == 'unknown')."
fi
if [[ "$IS_ROSA" == "true" ]]; then
  acmf::common::warn "OpenShift: ROSA detected (infrastructure provider=AWS, red-hat-managed). ROSA→EKS scope differs from on-prem OCP→EKS — networking/IAM mostly stays; mainly a control-plane SKU swap. cluster.platform set to 'aws'."
fi
if [[ "$SCC_USAGE_COUNT" -gt 0 ]]; then
  acmf::common::warn "OpenShift: ${SCC_USAGE_COUNT} effective SCC binding(s) detected — each must map to PodSecurity Admission (PSA) label on EKS (see openshift.scc_usage[])."
fi
if [[ "$ROUTES_TOTAL" -gt 0 ]]; then
  acmf::common::warn "OpenShift: ${ROUTES_TOTAL} Route(s) detected — each Route → typically 1 Ingress + 1 ACM cert + 1 ALB listener rule on EKS (path+host combos may split into multiple Ingress objects)."
fi

SCOPE_JSON="$(jq -n --arg c "$CLUSTER_NAME" --argjson inc "$NS_INCLUDED_JSON" --argjson exc "$NS_EXCLUDED_JSON" \
  '{ clusters:[$c], namespaces_included:$inc, namespaces_excluded:$exc }')"

# Use the standard emitter to assemble the schema-required top-level keys, then
# layer the optional openshift{} block on top before writing the final bundle.
acmf::bundle::emit "$OUTPUT" "$(acmf::common::generated_at)" "openshift-export-script" \
  "$SCOPE_JSON" "$CLUSTERS_JSON" "$WORKLOADS_JSON" "$NETWORKING_JSON" \
  "$STORAGE_JSON" "$IDENTITY_JSON" "$EXT_JSON" "$CRDS_JSON" \
  "$VMW_JSON" "$UTIL_JSON" "$TRAFFIC_JSON"

if [[ "$OPENSHIFT_BLOCK_JSON" != "{}" ]]; then
  jq --argjson ocp "$OPENSHIFT_BLOCK_JSON" '. + {openshift:$ocp}' "$OUTPUT" > "$OUTPUT.tmp" && mv "$OUTPUT.tmp" "$OUTPUT"
fi

acmf::common::log "Wrote: $OUTPUT"
acmf::common::log "Validate: npx --yes -p ajv-cli@5 -p ajv-formats@2 ajv validate -s schemas/discovery-bundle.schema.json -d $OUTPUT -c ajv-formats"
