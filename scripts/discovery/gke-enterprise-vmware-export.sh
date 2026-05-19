successfully downloaded text file (SHA: 096c0e71cd79e0287601d2a60d3a5dfe7699fb5f)#!/usr/bin/env bash
# gke-enterprise-vmware-export.sh
#
# ACMF Phase 1 (Assess) — GKE Enterprise on VMware (formerly Anthos) self-export discovery script.
#
# Produces a JSON discovery bundle conforming to:
#   schemas/discovery-bundle.schema.json (v0.2.0)
#
# Read-only. Redacts secrets. Skips on failure (logs to "skipped" / "warnings").
#
# Requirements:
#   - bash 4+
#   - kubectl (configured for the target GKE Enterprise cluster)
#   - jq
#   - Optional: gcloud (GKE Enterprise metadata), govc (vSphere layer), kubectl top
#
# Usage:
#   ./gke-enterprise-vmware-export.sh [--dry-run] [--output FILE] [--namespaces "ns1,ns2"]
#                             [--exclude "kube-system,gke-system,gmp-system"]
#                             [--cluster-name NAME] [--no-vmware]
#
# Examples:
#   ./gke-enterprise-vmware-export.sh --output bundle.json
#   ./gke-enterprise-vmware-export.sh --dry-run --output mock.json
#
# Validate locally:
#   npx --yes ajv-cli validate -s schemas/discovery-bundle.schema.json -d bundle.json
#
# Exit codes: 0 = success (bundle written), 2 = usage error, 3 = no kubectl access.

set -uo pipefail

# ------------------------- Config / argv -------------------------
DRY_RUN=0
OUTPUT=""
INCLUDE_NS=""
EXCLUDE_NS="kube-system,gke-system,gmp-system,kube-public,kube-node-lease,config-management-system,istio-system,asm-system,anthos-identity-service"
CLUSTER_NAME=""
SKIP_VMWARE=0

usage() {
  sed -n '2,30p' "$0"
  exit 2
}

need_val() {
  # Validate that flag $1 has a non-empty value $2 that is not another flag.
  if [[ -z "${2:-}" || "${2:0:2}" == "--" ]]; then
    echo "error: $1 requires a value" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --output)       need_val "$1" "${2:-}"; OUTPUT="$2"; shift 2 ;;
    --namespaces)   need_val "$1" "${2:-}"; INCLUDE_NS="$2"; shift 2 ;;
    --exclude)      need_val "$1" "${2:-}"; EXCLUDE_NS="$2"; shift 2 ;;
    --cluster-name) need_val "$1" "${2:-}"; CLUSTER_NAME="$2"; shift 2 ;;
    --no-vmware) SKIP_VMWARE=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -z "$OUTPUT" ]] && OUTPUT="discovery-bundle-$(date -u +%Y%m%dT%H%M%SZ).json"

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Working state arrays (jq-friendly tmp files)
TMPDIR_ROOT="$(mktemp -d -t acmf-export-XXXXXX)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT
SKIPPED_FILE="$TMPDIR_ROOT/skipped.json"; echo "[]" > "$SKIPPED_FILE"
WARN_FILE="$TMPDIR_ROOT/warnings.json"; echo "[]" > "$WARN_FILE"

log()  { echo "[acmf-export] $*" >&2; }
warn() { local m="$1"; jq --arg m "$m" '. += [$m]' "$WARN_FILE" > "$WARN_FILE.tmp" && mv "$WARN_FILE.tmp" "$WARN_FILE"; log "WARN: $m"; }
skip() { local cmd="$1" reason="$2"; jq --arg c "$cmd" --arg r "$reason" '. += [{command:$c, reason:$r}]' "$SKIPPED_FILE" > "$SKIPPED_FILE.tmp" && mv "$SKIPPED_FILE.tmp" "$SKIPPED_FILE"; log "SKIP [$cmd]: $reason"; }

require() { command -v "$1" >/dev/null 2>&1 || return 1; }

# ------------------------- Mock / dry-run -------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "Dry-run mode: emitting mock bundle (no cluster contact)."
  cat > "$OUTPUT" <<EOF
{
  "schema_version": "0.2.0",
  "generated_at": "$GENERATED_AT",
  "generated_by": "self-export-script (dry-run)",
  "scope": {
    "clusters": ["mock-anthos"],
    "namespaces_included": ["app-a", "app-b"],
    "namespaces_excluded": ["kube-system", "gke-system", "gmp-system"]
  },
  "clusters": [
    {
      "name": "mock-anthos",
      "version": "1.28.5-gke.1217",
      "location": "dc-mock-1",
      "platform": "vmware",
      "control_plane": { "ha_mode": "stacked-ha", "node_count": 3 },
      "node_pools": [
        { "name": "default-pool", "count": 6, "machine_type": "vsphere-8vcpu-32gb", "k8s_version": "1.28.5", "taints": [], "labels": { "tier": "app" } }
      ],
      "anthos_version": "1.16.3",
      "anthos_config_management_version": "1.17.1",
      "service_mesh": { "enabled": true, "type": "asm", "version": "1.20.2" }
    }
  ],
  "workloads": [
    {
      "cluster": "mock-anthos",
      "namespace": "app-a",
      "kind": "Deployment",
      "name": "frontend",
      "classification": "stateless",
      "replicas": { "desired": 3, "current": 3 },
      "images": ["registry.example.com/app-a/frontend:v1.0.0"],
      "resources": { "requests": { "cpu": "200m", "memory": "256Mi" }, "limits": { "cpu": "500m", "memory": "512Mi" } },
      "env_summary": ["DB_PASSWORD=<REDACTED>"],
      "volume_mounts": []
    }
  ],
  "networking": {
    "services": [
      { "cluster": "mock-anthos", "namespace": "app-a", "name": "frontend", "type": "ClusterIP", "selectors": {"app":"frontend"}, "external_ips": [], "ports": [ { "name": "http", "port": 80, "target_port": 8080, "protocol": "TCP" } ] }
    ],
    "ingress": [
      { "cluster": "mock-anthos", "namespace": "app-a", "name": "frontend", "kind": "Ingress", "hosts": ["app.example.com"], "tls": true }
    ],
    "network_policies": { "count": 4, "samples": [] },
    "service_mesh": {
      "virtual_services": { "count": 2, "samples": [] },
      "destination_rules": { "count": 2, "samples": [] },
      "authorization_policies": { "count": 1, "samples": [] }
    }
  },
  "storage": {
    "storage_classes": [
      { "name": "vsphere-csi-fast", "provisioner": "csi.vsphere.vmware.com", "parameters": {"storagepolicyname":"gold"}, "reclaim_policy": "Delete", "volume_binding_mode": "WaitForFirstConsumer" }
    ],
    "persistent_volumes": [],
    "persistent_volume_claims": []
  },
  "identity": {
    "service_accounts": { "total_count": 12, "with_non_default_tokens": [] },
    "cluster_role_bindings": [],
    "workload_identity_bindings": [
      { "cluster": "mock-anthos", "namespace": "app-a", "k8s_service_account": "frontend-sa", "external_identity": "gsa:frontend@proj.iam.gserviceaccount.com" }
    ]
  },
  "external_dependencies": [],
  "crds": [],
  "vmware": { "clusters": [], "hosts": [], "datastores": [], "vm_to_node_mapping": [] },
  "utilization": {
    "nodes": [],
    "pods": [],
    "summary": { "cluster_cpu_utilization_pct": 35.0, "cluster_memory_utilization_pct": 55.0, "over_provisioning_ratio": 2.1, "metrics_source": null }
  },
  "traffic": { "pairs": [], "summary": { "east_west_bytes_per_sec": 0, "north_south_bytes_per_sec": 0, "total_service_pairs": 0, "telemetry_source": null } },
  "skipped": [
    { "command": "live-cluster-collection", "reason": "dry-run mode: no cluster contacted" }
  ],
  "warnings": ["dry-run output — not from a real cluster"]
}
EOF
  log "Wrote mock bundle: $OUTPUT"
  exit 0
fi

# ------------------------- Real collection -------------------------
require kubectl || { echo "kubectl required" >&2; exit 3; }
require jq || { echo "jq required" >&2; exit 3; }
kubectl version --request-timeout=5s >/dev/null 2>&1 || { echo "kubectl cannot reach cluster" >&2; exit 3; }

# Resolve cluster name
if [[ -z "$CLUSTER_NAME" ]]; then
  CLUSTER_NAME="$(kubectl config current-context 2>/dev/null || echo unknown)"
fi

# Resolve namespaces
if [[ -n "$INCLUDE_NS" ]]; then
  NS_LIST="$(echo "$INCLUDE_NS" | tr ',' '\n' | sed '/^$/d')"
else
  NS_LIST="$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n')"
  EXCLUDE_RE="$(echo "$EXCLUDE_NS" | tr ',' '|')"
  NS_LIST="$(echo "$NS_LIST" | grep -Ev "^(${EXCLUDE_RE})$" || true)"
fi
NS_INCLUDED_JSON="$(echo "$NS_LIST" | jq -R . | jq -s .)"
NS_EXCLUDED_JSON="$(echo "$EXCLUDE_NS" | tr ',' '\n' | jq -R . | jq -s .)"

# ---- clusters ----
log "Collecting cluster info..."
K8S_VER="$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion // "unknown"')"
NODE_COUNT="$(kubectl get nodes -o json 2>/dev/null | jq '.items | length')"
ASM_ENABLED=false; ASM_VER=null
if kubectl get ns istio-system >/dev/null 2>&1 || kubectl get ns asm-system >/dev/null 2>&1; then
  ASM_ENABLED=true
  ASM_VER="$(kubectl -n istio-system get deploy istiod -o jsonpath='{.metadata.labels.istio\.io/rev}' 2>/dev/null || echo null)"
  [[ -z "$ASM_VER" || "$ASM_VER" == "null" ]] && ASM_VER=null || ASM_VER="\"$ASM_VER\""
fi
CLUSTERS_JSON=$(jq -n \
  --arg name "$CLUSTER_NAME" \
  --arg ver "$K8S_VER" \
  --argjson nc "${NODE_COUNT:-0}" \
  --argjson asm "$ASM_ENABLED" \
  '[{ name:$name, version:$ver, location:"unknown", platform:"vmware",
      control_plane:{ ha_mode:"unknown", node_count:$nc },
      node_pools:[],
      anthos_version:null,
      anthos_config_management_version:null,
      service_mesh:{ enabled:$asm, type:(if $asm then "asm" else "none" end), version:null } }]')

# ---- workloads ----
log "Collecting workloads..."
WORKLOADS_JSON="[]"
for ns in $NS_LIST; do
  for kind in Deployment StatefulSet DaemonSet Job CronJob; do
    raw="$(kubectl -n "$ns" get "$kind" -o json 2>/dev/null || echo '{"items":[]}')"
    classification="stateless"
    case "$kind" in
      StatefulSet) classification="stateful" ;;
      Job|CronJob) classification="batch" ;;
      DaemonSet)   classification="system" ;;
    esac
    add="$(echo "$raw" | jq --arg c "$CLUSTER_NAME" --arg ns "$ns" --arg k "$kind" --arg cls "$classification" '
      [ .items[] | {
        cluster: $c, namespace: $ns, kind: $k, name: .metadata.name, classification: $cls,
        replicas: { desired: (.spec.replicas // null), current: (.status.replicas // .status.currentReplicas // null) },
        images: [ (.spec.template.spec.containers // [])[].image ],
        resources: {
          requests: ( (.spec.template.spec.containers // [])[0].resources.requests // {} ),
          limits:   ( (.spec.template.spec.containers // [])[0].resources.limits   // {} )
        },
        env_summary: [ (.spec.template.spec.containers // [])[].env[]? | (.name + "=" + (if .valueFrom then "<ref:" + ((.valueFrom|keys[0])|tostring) + ">" else "<REDACTED>" end)) ],
        volume_mounts: [ (.spec.template.spec.containers // [])[].volumeMounts[]? | { name: .name, mount_path: .mountPath, read_only: (.readOnly // false) } ]
      } ]')"
    WORKLOADS_JSON="$(jq -n --argjson a "$WORKLOADS_JSON" --argjson b "$add" '$a + $b')"
  done
done

# ---- networking ----
log "Collecting networking..."
SVCS_JSON="[]"; ING_JSON="[]"
for ns in $NS_LIST; do
  s="$(kubectl -n "$ns" get svc -o json 2>/dev/null || echo '{"items":[]}')"
  add="$(echo "$s" | jq --arg c "$CLUSTER_NAME" --arg ns "$ns" '
    [ .items[] | {
      cluster:$c, namespace:$ns, name:.metadata.name, type:.spec.type,
      selectors:(.spec.selector // {}),
      external_ips:(.spec.externalIPs // []),
      ports:[ (.spec.ports // [])[] | { name:(.name // ""), port:.port, target_port:(.targetPort|tostring), protocol:(.protocol // "TCP") } ]
    } ]')"
  SVCS_JSON="$(jq -n --argjson a "$SVCS_JSON" --argjson b "$add" '$a + $b')"

  i="$(kubectl -n "$ns" get ingress -o json 2>/dev/null || echo '{"items":[]}')"
  add="$(echo "$i" | jq --arg c "$CLUSTER_NAME" --arg ns "$ns" '
    [ .items[] | {
      cluster:$c, namespace:$ns, name:.metadata.name, kind:"Ingress",
      hosts:[ (.spec.rules // [])[].host ],
      tls: ((.spec.tls // []) | length > 0)
    } ]')"
  ING_JSON="$(jq -n --argjson a "$ING_JSON" --argjson b "$add" '$a + $b')"
done

NP_COUNT="$(kubectl get networkpolicy -A -o json 2>/dev/null | jq '.items | length' || echo 0)"
VS_COUNT="$(kubectl get virtualservices.networking.istio.io -A -o json 2>/dev/null | jq '.items | length' || echo 0)"
DR_COUNT="$(kubectl get destinationrules.networking.istio.io -A -o json 2>/dev/null | jq '.items | length' || echo 0)"
AP_COUNT="$(kubectl get authorizationpolicies.security.istio.io -A -o json 2>/dev/null | jq '.items | length' || echo 0)"

NETWORKING_JSON=$(jq -n \
  --argjson svc "$SVCS_JSON" --argjson ing "$ING_JSON" \
  --argjson np "${NP_COUNT:-0}" --argjson vs "${VS_COUNT:-0}" \
  --argjson dr "${DR_COUNT:-0}" --argjson ap "${AP_COUNT:-0}" '
  { services:$svc, ingress:$ing,
    network_policies: { count:$np, samples:[] },
    service_mesh: {
      virtual_services:{ count:$vs, samples:[] },
      destination_rules:{ count:$dr, samples:[] },
      authorization_policies:{ count:$ap, samples:[] }
    } }')

# ---- storage ----
log "Collecting storage..."
SC_JSON="$(kubectl get sc -o json 2>/dev/null | jq '[ .items[] | {
  name:.metadata.name, provisioner:.provisioner, parameters:(.parameters // {}),
  reclaim_policy:(.reclaimPolicy // "Delete"), volume_binding_mode:(.volumeBindingMode // "Immediate")
} ]' || echo '[]')"
PV_JSON="$(kubectl get pv -o json 2>/dev/null | jq '[ .items[] | {
  name:.metadata.name, size:.spec.capacity.storage, reclaim_policy:.spec.persistentVolumeReclaimPolicy,
  access_modes:.spec.accessModes,
  source_type: ( if .spec.csi then .spec.csi.driver else (.spec | keys[] | select(. != "capacity" and . != "accessModes" and . != "persistentVolumeReclaimPolicy" and . != "storageClassName" and . != "claimRef" and . != "volumeMode" and . != "mountOptions" and . != "nodeAffinity")) end ),
  storage_class:(.spec.storageClassName // null)
} ]' || echo '[]')"
PVC_JSON="[]"
for ns in $NS_LIST; do
  add="$(kubectl -n "$ns" get pvc -o json 2>/dev/null | jq --arg c "$CLUSTER_NAME" --arg ns "$ns" '[ .items[] | {
    cluster:$c, namespace:$ns, name:.metadata.name, size:.spec.resources.requests.storage,
    linked_pv:(.spec.volumeName // null), mounted_by:[]
  } ]' || echo '[]')"
  PVC_JSON="$(jq -n --argjson a "$PVC_JSON" --argjson b "$add" '$a + $b')"
done
STORAGE_JSON=$(jq -n --argjson sc "$SC_JSON" --argjson pv "$PV_JSON" --argjson pvc "$PVC_JSON" \
  '{ storage_classes:$sc, persistent_volumes:$pv, persistent_volume_claims:$pvc }')

# ---- identity ----
log "Collecting identity..."
SA_TOTAL="$(kubectl get sa -A -o json 2>/dev/null | jq '.items | length' || echo 0)"
WI_JSON="[]"
for ns in $NS_LIST; do
  add="$(kubectl -n "$ns" get sa -o json 2>/dev/null | jq --arg c "$CLUSTER_NAME" --arg ns "$ns" '[
    .items[] | select(.metadata.annotations["iam.gke.io/gcp-service-account"]) | {
      cluster:$c, namespace:$ns, k8s_service_account:.metadata.name,
      external_identity:("gsa:" + .metadata.annotations["iam.gke.io/gcp-service-account"])
    } ]' || echo '[]')"
  WI_JSON="$(jq -n --argjson a "$WI_JSON" --argjson b "$add" '$a + $b')"
done
CRB_JSON="$(kubectl get clusterrolebindings -o json 2>/dev/null | jq --arg c "$CLUSTER_NAME" '[ .items[] | {
  cluster:$c, name:.metadata.name, role_ref:.roleRef.name,
  subjects:[ (.subjects // [])[] | { kind:.kind, name:.name, namespace:(.namespace // "") } ]
} ]' || echo '[]')"
IDENTITY_JSON=$(jq -n --argjson t "${SA_TOTAL:-0}" --argjson crb "$CRB_JSON" --argjson wi "$WI_JSON" \
  '{ service_accounts:{ total_count:$t, with_non_default_tokens:[] }, cluster_role_bindings:$crb, workload_identity_bindings:$wi }')

# ---- external_dependencies (best-effort: scan configmaps & env hosts) ----
EXT_JSON="[]"
# Cheap heuristic: look at env vars that look like *_HOST/*_URL across discovered workloads
EXT_JSON="$(echo "$WORKLOADS_JSON" | jq '[ .[] as $w |
  ($w.env_summary[]? | capture("^(?<k>[A-Z_]+(_HOST|_URL))=") | {k:.k}) as $m |
  { host:("env-ref:" + $m.k), port:0, protocol:"unknown", source:"env",
    used_by:[ ($w.cluster + "/" + $w.namespace + "/" + $w.kind + "/" + $w.name) ] }
] | unique_by(.host)' 2>/dev/null || echo '[]')"

# ---- crds ----
log "Collecting CRDs..."
KNOWN_OPERATORS_RE='cert-manager|external-dns|prometheus|grafana|argo|flux|istio|knative|kyverno|gatekeeper|kueue|kueue|crossplane'
CRDS_JSON="$(kubectl get crd -o json 2>/dev/null | jq --arg known "$KNOWN_OPERATORS_RE" '[ .items[] | {
  group:.spec.group,
  version:(.spec.versions[0].name // "v1"),
  kind:.spec.names.kind,
  scope:.spec.scope,
  known_operator: ( if (.spec.group | test($known; "i")) then (.spec.group | split(".")[0]) else null end ),
  needs_human_review: ( (.spec.group | test($known; "i")) | not )
} ]' || echo '[]')"

# ---- vmware (govc, optional) ----
log "Collecting VMware layer..."
VMW_JSON='{"clusters":[],"hosts":[],"datastores":[],"vm_to_node_mapping":[]}'
if [[ "$SKIP_VMWARE" -eq 1 ]]; then
  skip "govc" "--no-vmware flag set"
elif require govc && [[ -n "${GOVC_URL:-}" ]]; then
  CL="$(govc ls -t ClusterComputeResource '/*/host/*' 2>/dev/null | jq -R . | jq -s 'map({name: ., datacenter:"unknown", host_count:0})' || echo '[]')"
  VMW_JSON="$(jq -n --argjson cl "$CL" '{ clusters:$cl, hosts:[], datastores:[], vm_to_node_mapping:[] }')"
else
  skip "govc" "govc not installed or GOVC_URL not set"
fi

# ---- utilization ----
log "Collecting utilization..."
NODE_UTIL_JSON="[]"; POD_UTIL_JSON="[]"
NODES_JSON="$(kubectl get nodes -o json 2>/dev/null || echo '{"items":[]}')"
TOP_NODES="$(kubectl top nodes --no-headers 2>/dev/null || true)"
if [[ -z "$TOP_NODES" ]]; then
  skip "kubectl top nodes" "metrics-server unavailable or RBAC denied"
fi
NODE_UTIL_JSON="$(echo "$NODES_JSON" | jq --arg c "$CLUSTER_NAME" '[ .items[] | {
  cluster:$c, name:.metadata.name,
  cpu_capacity:.status.capacity.cpu, cpu_allocatable:.status.allocatable.cpu, cpu_usage:"unknown",
  memory_capacity:.status.capacity.memory, memory_allocatable:.status.allocatable.memory, memory_usage:"unknown",
  cpu_utilization_pct_30d_avg:0.0, cpu_utilization_pct_30d_p95:0.0, cpu_utilization_pct_30d_max:0.0,
  memory_utilization_pct_30d_avg:0.0, memory_utilization_pct_30d_p95:0.0, memory_utilization_pct_30d_max:0.0
} ]')"

UTIL_JSON=$(jq -n --argjson n "$NODE_UTIL_JSON" --argjson p "$POD_UTIL_JSON" '{
  nodes:$n, pods:$p,
  summary:{ cluster_cpu_utilization_pct:0.0, cluster_memory_utilization_pct:0.0, over_provisioning_ratio:0.0, metrics_source:null }
}')

# ---- traffic ----
TRAFFIC_JSON='{ "pairs": [], "summary": { "east_west_bytes_per_sec": 0, "north_south_bytes_per_sec": 0, "total_service_pairs": 0, "telemetry_source": null } }'
skip "traffic-telemetry" "Prometheus/Istio telemetry not queried by this script (manual export recommended)"

# ------------------------- Assemble -------------------------
log "Assembling bundle..."
SKIPPED_CONTENT="$(cat "$SKIPPED_FILE")"
WARN_CONTENT="$(cat "$WARN_FILE")"

jq -n \
  --arg gen_at "$GENERATED_AT" \
  --arg gen_by "self-export-script" \
  --argjson scope "$(jq -n --arg c "$CLUSTER_NAME" --argjson inc "$NS_INCLUDED_JSON" --argjson exc "$NS_EXCLUDED_JSON" '{ clusters:[$c], namespaces_included:$inc, namespaces_excluded:$exc }')" \
  --argjson clusters "$CLUSTERS_JSON" \
  --argjson workloads "$WORKLOADS_JSON" \
  --argjson networking "$NETWORKING_JSON" \
  --argjson storage "$STORAGE_JSON" \
  --argjson identity "$IDENTITY_JSON" \
  --argjson ext "$EXT_JSON" \
  --argjson crds "$CRDS_JSON" \
  --argjson vmware "$VMW_JSON" \
  --argjson util "$UTIL_JSON" \
  --argjson traffic "$TRAFFIC_JSON" \
  --argjson skipped "$SKIPPED_CONTENT" \
  --argjson warnings "$WARN_CONTENT" \
  '{
    schema_version: "0.2.0",
    generated_at: $gen_at,
    generated_by: $gen_by,
    scope: $scope,
    clusters: $clusters,
    workloads: $workloads,
    networking: $networking,
    storage: $storage,
    identity: $identity,
    external_dependencies: $ext,
    crds: $crds,
    vmware: $vmware,
    utilization: $util,
    traffic: $traffic,
    skipped: $skipped,
    warnings: $warnings
  }' > "$OUTPUT"

log "Wrote: $OUTPUT"
log "Validate: npx --yes ajv-cli validate -s schemas/discovery-bundle.schema.json -d $OUTPUT"
