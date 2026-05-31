#!/usr/bin/env bash
# scripts/discovery/openshift-export.sh
#
# ACMF Phase 1 self-export — Red Hat OpenShift Container Platform (OCP) 4.x.
#
# Uses kubectl for the K8s core, then layers on OpenShift-specific resources
# via `oc` if available: Routes, ImageStreams, BuildConfigs, OperatorGroups,
# Subscriptions, MachineConfigPools, SecurityContextConstraints + effective
# SCC bindings per namespace, ROSA detection, plus a per-Subscription AWS
# migration rating (easy/hard/blocker) drawn from the table in
# adapters/source/openshift/mapping.md.
#
# Read-only.
#
# Required tools : kubectl, jq
# Optional tools : oc      (OpenShift CLI — strongly recommended)
# Permissions    : cluster-reader (or self-provisioner with read-only Roles).
# Estimated time : 2-4 min for clusters with many Operators / ImageStreams.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_common.sh"

PLATFORM="openshift"

print_usage() {
  cat <<EOF
OpenShift (OCP) discovery export.

Usage: $(basename "$0") [options]

Options:
  --output FILE
  --include-namespaces CSV
  --exclude-namespaces CSV
  --include-system         Don't skip openshift-*/kube-* projects (verbose)
  --kubeconfig PATH
  --context NAME
  --dry-run
  -h, --help

What this collects (in addition to the K8s core layer):
  - ClusterVersion (current_version, channel)
  - Routes total, ImageStreams + BuildConfigs total
  - OLM Subscriptions (each rated easy/hard/blocker → AWS target)
  - MachineConfigPool ready/total
  - SecurityContextConstraints + effective SCC bindings per namespace
  - ROSA detection via 'oc get infrastructure cluster'

Operators not in the built-in rating table are tagged 'unknown' and surface
a single aggregated SME warning. See adapters/source/openshift/mapping.md
for the rating rationale.
EOF
}

# ---------------------------------------------------------------------------
# OpenShift Operator → AWS migration rating table.
#
# Echoes "rating|aws_target|rationale" for the given Operator package name.
# Empty string if not in the table → caller marks "unknown".
#
# Sources:
#   - AWS native equivalents per
#     https://docs.aws.amazon.com/eks/ and AWS Prescriptive Guidance for
#     "OpenShift to EKS" patterns.
#   - When no native equivalent exists (KubeVirt, ODF/Ceph, MetalLB), we mark
#     'blocker' with a redesign rationale rather than guess.
# ---------------------------------------------------------------------------
openshift_operator_rating() {
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
    kubevirt-hyperconverged|cnv-operator|hyperconverged-cluster-operator)
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
    openshift-cnv-operator|kubevirt-operator)
      echo "blocker|Amazon EC2 + AWS Application Migration Service (MGN)|VMs leave Kubernetes entirely on AWS" ;;

    *) echo "" ;;
  esac
}

main() {
  parse_common_args "$@"

  require_cmd kubectl
  require_cmd jq

  if ! have_cmd oc; then
    log_warn "oc not found — Routes / ImageStreams / BuildConfigs / Subscriptions / SCC will be skipped."
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log_info "Dry-run: emitting schema-valid stub to ${OUTPUT_FILE}"
    emit_bundle_stub "$PLATFORM" "$OUTPUT_FILE"
    log_info "Planned commands:"
    core_dry_run_hint
    log_dim "  oc get clusterversion version -o json"
    log_dim "  oc get infrastructure cluster -o json   (ROSA detection)"
    log_dim "  oc get route -A -o json"
    log_dim "  oc get imagestream -A -o json"
    log_dim "  oc get buildconfig -A -o json"
    log_dim "  oc get subscription,operatorgroup -A -o json"
    log_dim "  oc get machineconfigpool -o json"
    log_dim "  oc get scc -o json"
    log_dim "  oc get rolebinding,clusterrolebinding -A -o json   (filter system:openshift:scc:*)"
    return 0
  fi

  bundle_skeleton "$PLATFORM" >"$OUTPUT_FILE"
  local bundle="$OUTPUT_FILE"

  log_info "Collecting K8s core layer…"
  core_kube_collect "$bundle" "$PLATFORM" "openshift"

  if ! have_cmd oc; then
    bundle_add_skipped "$bundle" "oc get route,imagestream,buildconfig,subscription,scc" \
      "oc CLI not installed; OpenShift-specific objects not collected"
    log_info "Bundle written: $bundle"
    return 0
  fi

  log_info "Collecting OpenShift-specific resources via oc…"

  # ClusterVersion
  local cv_json
  cv_json="$(oc get clusterversion version -o json 2>/dev/null || echo '{}')"
  if [ -n "$cv_json" ] && [ "$cv_json" != "{}" ]; then
    jq --argjson cv "$cv_json" \
       '.clusters[0].openshift = {
          current_version: ($cv.status.desired.version // "unknown"),
          channel: ($cv.spec.channel // "stable")
        }' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
  fi

  # Infrastructure → ROSA detection
  local infra_json provider is_rosa
  infra_json="$(oc get infrastructure cluster -o json 2>/dev/null || echo '{}')"
  provider="$(printf '%s' "$infra_json" | jq -r '.status.platform // "unknown"' 2>/dev/null || echo unknown)"
  # ROSA-classic identifies as AWS + controlPlaneTopology HighlyAvailable; ROSA-HCP marks ".status.controlPlaneTopology=External".
  if printf '%s' "$infra_json" | jq -e '(.status.platform == "AWS") and ((.status.platformStatus.aws.resourceTags // []) | any(.key == "red-hat-managed" and .value == "true"))' >/dev/null 2>&1; then
    is_rosa="true"
  elif [ "$provider" = "AWS" ] && printf '%s' "$infra_json" | jq -e '.status.controlPlaneTopology == "External"' >/dev/null 2>&1; then
    is_rosa="true"
  else
    is_rosa="false"
  fi

  # Routes
  local routes_json
  routes_json="$(oc get route -A -o json 2>/dev/null || echo '{"items":[]}')"

  # ImageStreams + BuildConfigs
  local is_json bc_json
  is_json="$(oc get imagestream -A -o json 2>/dev/null || echo '{"items":[]}')"
  bc_json="$(oc get buildconfig -A -o json 2>/dev/null || echo '{"items":[]}')"

  # OLM Subscriptions — base list
  local sub_json
  sub_json="$(oc get subscription -A -o json 2>/dev/null || echo '{"items":[]}')"

  # Build subscriptions array with migration ratings
  local subs_array unknown_count
  subs_array="[]"
  unknown_count=0
  if printf '%s' "$sub_json" | jq -e '.items | length > 0' >/dev/null 2>&1; then
    local count i pkg ns name channel source rating_str rating aws_target rationale entry
    count="$(printf '%s' "$sub_json" | jq '.items | length')"
    i=0
    while [ "$i" -lt "$count" ]; do
      pkg="$(printf '%s' "$sub_json" | jq -r ".items[$i].spec.name // \"unknown\"")"
      ns="$(printf '%s' "$sub_json" | jq -r ".items[$i].metadata.namespace // \"\"")"
      name="$(printf '%s' "$sub_json" | jq -r ".items[$i].metadata.name // \"\"")"
      channel="$(printf '%s' "$sub_json" | jq -r ".items[$i].spec.channel // \"\"")"
      source="$(printf '%s' "$sub_json" | jq -r ".items[$i].spec.source // \"\"")"
      rating_str="$(openshift_operator_rating "$pkg")"
      if [ -z "$rating_str" ]; then
        rating="unknown"
        aws_target=""
        rationale="Operator '$pkg' not in built-in rating table; SME review required."
        unknown_count=$((unknown_count + 1))
      else
        rating="${rating_str%%|*}"
        local rest="${rating_str#*|}"
        aws_target="${rest%%|*}"
        rationale="${rest#*|}"
      fi
      entry="$(jq -n \
        --arg ns "$ns" --arg name "$name" --arg pkg "$pkg" \
        --arg ch "$channel" --arg src "$source" \
        --arg rating "$rating" --arg target "$aws_target" --arg rat "$rationale" \
        '{namespace: $ns, name: $name, package: $pkg, channel: $ch, source: $src,
          migration_rating: {rating: $rating, aws_target: $target, rationale: $rat}}')"
      subs_array="$(printf '%s' "$subs_array" | jq --argjson e "$entry" '. + [$e]')"
      i=$((i + 1))
    done
  fi

  # MachineConfigPool
  local mcp_json mcp_array
  mcp_json="$(oc get machineconfigpool -o json 2>/dev/null || echo '{"items":[]}')"
  mcp_array="$(jq -n --argjson m "$mcp_json" \
    '[(($m.items // [])[] | { name: .metadata.name, ready: .status.readyMachineCount, total: .status.machineCount })]')"

  # SCCs + effective SCC bindings per namespace
  # Strategy: any RoleBinding/ClusterRoleBinding pointing at a ClusterRole named
  # 'system:openshift:scc:<scc-name>' is an effective SCC grant. Surface as scc_usage[].
  local rb_json crb_json scc_usage
  rb_json="$(oc get rolebinding -A -o json 2>/dev/null || echo '{"items":[]}')"
  crb_json="$(oc get clusterrolebinding -o json 2>/dev/null || echo '{"items":[]}')"
  scc_usage="$(jq -n \
    --argjson rb "$rb_json" \
    --argjson crb "$crb_json" \
    '
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

  # SCC inventory (informational)
  local scc_json scc_total
  scc_json="$(oc get scc -o json 2>/dev/null || echo '{"items":[]}')"
  scc_total="$(printf '%s' "$scc_json" | jq '(.items // []) | length')"

  # Assemble openshift block in one pass
  jq \
    --argjson r "$routes_json" \
    --argjson is "$is_json" \
    --argjson bc "$bc_json" \
    --argjson subs "$subs_array" \
    --argjson mcp "$mcp_array" \
    --argjson scc "$scc_usage" \
    --arg provider "$provider" \
    --argjson rosa "$is_rosa" \
    --argjson scc_total "$scc_total" \
    '
    .openshift = ((.openshift // {}) + {
       infrastructure_provider: $provider,
       is_rosa: $rosa,
       image_streams_total: (($is.items // []) | length),
       build_configs_total: (($bc.items // []) | length),
       subscriptions: $subs,
       machine_config_pools: $mcp,
       scc_usage: $scc,
       scc_total: $scc_total
     })
    | .networking = ((.networking // {}) + {
       openshift_routes_total: (($r.items // []) | length)
     })
    ' \
    "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # Precise warnings (only emit when conditions hold; no blanket stub)
  if [ "$unknown_count" -gt 0 ]; then
    bundle_add_warning "$bundle" \
      "OpenShift: ${unknown_count} Operator(s) not in built-in rating table — SME review required (see .openshift.subscriptions[] where migration_rating.rating == 'unknown')."
  fi
  if [ "$is_rosa" = "true" ]; then
    bundle_add_warning "$bundle" \
      "OpenShift: ROSA detected (infrastructure provider=AWS, red-hat-managed). ROSA→EKS migration scope differs from on-prem OCP→EKS — networking/IAM mostly stays; mainly a control-plane SKU swap."
  fi
  local scc_usage_count
  scc_usage_count="$(printf '%s' "$scc_usage" | jq 'length')"
  if [ "$scc_usage_count" -gt 0 ]; then
    bundle_add_warning "$bundle" \
      "OpenShift: ${scc_usage_count} effective SCC binding(s) detected — each must map to PodSecurity Admission (PSA) label on EKS (see .openshift.scc_usage)."
  fi

  log_info "Bundle written: $bundle"
}

main "$@"
