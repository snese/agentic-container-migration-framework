#!/usr/bin/env bash
# anthos-vmware-export.sh — ACMF Discovery Option 2 (self-export script).
#
# Read-only export of an Anthos-on-VMware cluster into a JSON bundle that
# validates against schemas/discovery-bundle.schema.json (schema_version 0.2.0).
#
# Dependencies (all read-only): bash 4+, kubectl, jq, gcloud (optional),
# govc (optional). No Python, no extra packages.
#
# Usage:
#   anthos-vmware-export.sh \
#       --context <kube-context> \
#       [--namespaces ns1,ns2]            # default: all non-system namespaces
#       [--include-system]                # include kube-*, gke-*, gmp-* ns
#       [--out discovery-bundle.json]     # default: ./discovery-bundle.json
#       [--no-vmware]                     # skip govc section
#       [--no-utilization]                # skip kubectl top
#       [--max-pods 50]                   # top-N pods by usage in utilization.pods[]
#
# Privacy: secret data fields and base64 secret payloads are NEVER captured.
# Env values are summarised as keys only (`KEY=<source>`); values are redacted.
#
# Exit code is always 0 unless a fatal precondition is missing (kubectl, jq).
# Per-section failures are logged into bundle.skipped[] / bundle.warnings[].

set -u
set -o pipefail
umask 077

# ---------- arg parsing ----------------------------------------------------

CONTEXT=""
NAMESPACES=""
INCLUDE_SYSTEM=0
OUT="discovery-bundle.json"
NO_VMWARE=0
NO_UTIL=0
MAX_PODS=50

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)         CONTEXT="$2"; shift 2 ;;
    --namespaces)      NAMESPACES="$2"; shift 2 ;;
    --include-system)  INCLUDE_SYSTEM=1; shift ;;
    --out)             OUT="$2"; shift 2 ;;
    --no-vmware)       NO_VMWARE=1; shift ;;
    --no-utilization)  NO_UTIL=1; shift ;;
    --max-pods)        MAX_PODS="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

for bin in kubectl jq; do
  command -v "$bin" >/dev/null || { echo "fatal: $bin not found in PATH" >&2; exit 2; }
done

KCTX_ARGS=()
[[ -n "$CONTEXT" ]] && KCTX_ARGS=(--context "$CONTEXT")

# ---------- helpers --------------------------------------------------------

TMPDIR_ROOT="$(mktemp -d -t acmf-export.XXXXXX)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

SKIPPED_FILE="$TMPDIR_ROOT/skipped.jsonl"
WARN_FILE="$TMPDIR_ROOT/warnings.jsonl"
: >"$SKIPPED_FILE"
: >"$WARN_FILE"

log()  { printf '[acmf-export] %s\n' "$*" >&2; }
warn() { printf '%s\n' "$*" | jq -R . >>"$WARN_FILE"; log "WARN: $*"; }
skip() { # skip <command> <reason>
  jq -nc --arg c "$1" --arg r "$2" '{command:$c, reason:$r}' >>"$SKIPPED_FILE"
  log "SKIP: $1 — $2"
}

# run_kubectl <label> <kubectl args...> — returns JSON or empty {}/[] on error.
run_kubectl_json() {
  local label="$1"; shift
  local out err rc
  out="$(kubectl "${KCTX_ARGS[@]}" "$@" -o json 2>"$TMPDIR_ROOT/err" )"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    err="$(tr '\n' ' ' <"$TMPDIR_ROOT/err" | head -c 400)"
    skip "kubectl $* (-o json)" "$label failed: $err"
    printf '%s' '{"items":[]}'
    return 0
  fi
  printf '%s' "$out"
}

run_kubectl_text() {
  local label="$1"; shift
  local out rc err
  out="$(kubectl "${KCTX_ARGS[@]}" "$@" 2>"$TMPDIR_ROOT/err")"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    err="$(tr '\n' ' ' <"$TMPDIR_ROOT/err" | head -c 400)"
    skip "kubectl $*" "$label failed: $err"
    printf ''
    return 0
  fi
  printf '%s' "$out"
}

# ---------- 0. scope -------------------------------------------------------

log "phase 0: scope"

CONTEXT_NAME="$(kubectl "${KCTX_ARGS[@]}" config current-context 2>/dev/null || echo "unknown")"

ALL_NS_JSON="$(run_kubectl_json "list namespaces" get ns)"
mapfile -t ALL_NS < <(printf '%s' "$ALL_NS_JSON" | jq -r '.items[].metadata.name')

is_system_ns() {
  case "$1" in
    kube-*|gke-*|gmp-*|anthos-*|config-management-*|cnrm-system|gatekeeper-system|istio-system|asm-system) return 0 ;;
    *) return 1 ;;
  esac
}

INCLUDED_NS=()
EXCLUDED_NS=()
if [[ -n "$NAMESPACES" ]]; then
  IFS=',' read -ra INCLUDED_NS <<<"$NAMESPACES"
  for ns in "${ALL_NS[@]}"; do
    keep=0
    for sel in "${INCLUDED_NS[@]}"; do [[ "$ns" == "$sel" ]] && keep=1; done
    [[ $keep -eq 0 ]] && EXCLUDED_NS+=("$ns")
  done
else
  for ns in "${ALL_NS[@]}"; do
    if is_system_ns "$ns" && [[ $INCLUDE_SYSTEM -eq 0 ]]; then
      EXCLUDED_NS+=("$ns")
    else
      INCLUDED_NS+=("$ns")
    fi
  done
fi

ns_array_json() { printf '%s\n' "$@" | jq -R . | jq -s .; }
INCLUDED_JSON="$(ns_array_json "${INCLUDED_NS[@]+"${INCLUDED_NS[@]}"}")"
EXCLUDED_JSON="$(ns_array_json "${EXCLUDED_NS[@]+"${EXCLUDED_NS[@]}"}")"

SCOPE_JSON="$(jq -nc \
  --arg ctx "$CONTEXT_NAME" \
  --argjson inc "$INCLUDED_JSON" \
  --argjson exc "$EXCLUDED_JSON" \
  '{clusters:[$ctx], namespaces_included:$inc, namespaces_excluded:$exc}')"

# ---------- 1. cluster inventory ------------------------------------------

log "phase 1: cluster inventory"

NODES_JSON="$(run_kubectl_json "list nodes" get nodes)"
SERVER_VERSION="$(run_kubectl_text "version" version --short=true 2>/dev/null \
  || kubectl "${KCTX_ARGS[@]}" version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion // ""')"
[[ -z "$SERVER_VERSION" ]] && SERVER_VERSION="unknown"

# Detect Anthos / Config Sync / ASM versions via well-known CR/Deployments.
ANTHOS_VER="$(run_kubectl_text "anthos onpremuserclusters" get onpremusercluster -A -o jsonpath='{.items[0].spec.gkeOnPremVersion}' 2>/dev/null)"
[[ -z "$ANTHOS_VER" ]] && ANTHOS_VER="null"
ACM_VER="$(run_kubectl_text "config-management" get configmanagement -A -o jsonpath='{.items[0].status.configManagementVersion}' 2>/dev/null)"
[[ -z "$ACM_VER" ]] && ACM_VER="null"
ASM_VER="$(run_kubectl_text "asm version" -n istio-system get deploy istiod -o jsonpath='{.spec.template.metadata.labels.istio\.io/rev}' 2>/dev/null)"
MESH_ENABLED="false"; MESH_TYPE="none"
if kubectl "${KCTX_ARGS[@]}" get ns istio-system >/dev/null 2>&1; then
  MESH_ENABLED="true"; MESH_TYPE="asm"
fi

CLUSTER_INVENTORY="$(jq -nc \
  --arg name "$CONTEXT_NAME" \
  --arg ver  "$SERVER_VERSION" \
  --arg anthos "$ANTHOS_VER" \
  --arg acm    "$ACM_VER" \
  --arg asmver "$ASM_VER" \
  --arg meshen "$MESH_ENABLED" \
  --arg meshtype "$MESH_TYPE" \
  --argjson nodes "$NODES_JSON" \
  '
  ($nodes.items | length) as $nc |
  {
    name: $name,
    version: $ver,
    location: "on-prem-vmware",
    platform: "vmware",
    control_plane: { ha_mode: "unknown", node_count: $nc },
    node_pools: ([$nodes.items
                  | group_by(.metadata.labels["cloud.google.com/gke-nodepool"] // "default-pool")[]
                  | { name: (.[0].metadata.labels["cloud.google.com/gke-nodepool"] // "default-pool"),
                      count: length,
                      machine_type: (.[0].metadata.labels["node.kubernetes.io/instance-type"] // "unknown"),
                      k8s_version: (.[0].status.nodeInfo.kubeletVersion // "unknown"),
                      taints: ([.[].spec.taints // [] | .[] | "\(.key)=\(.value // ""):\(.effect)"] | unique),
                      labels: ((.[0].metadata.labels // {}) | with_entries(select(.key | startswith("node.kubernetes.io/") | not)))
                    }]),
    anthos_version: ( if $anthos == "null" then null else $anthos end ),
    anthos_config_management_version: ( if $acm == "null" then null else $acm end ),
    service_mesh: { enabled: ($meshen=="true"), type: $meshtype, version: ( if $asmver=="" then null else $asmver end ) }
  }')"

# ---------- 2. workloads ---------------------------------------------------

log "phase 2: workloads"

classify() {
  # classify <kind> <name> <namespace>
  local kind="$1" name="$2" ns="$3"
  case "$kind" in
    Job|CronJob) echo "batch" ;;
    DaemonSet)   echo "system" ;;
    StatefulSet) echo "stateful" ;;
    Deployment)
      if is_system_ns "$ns"; then echo "system"
      else echo "stateless"; fi ;;
  esac
}

WORKLOADS_JSON='[]'
for kind in Deployment StatefulSet DaemonSet Job CronJob; do
  for ns in "${INCLUDED_NS[@]}"; do
    body="$(run_kubectl_json "list $kind in $ns" get "$kind" -n "$ns")"
    cnt="$(printf '%s' "$body" | jq '.items|length')"
    [[ "$cnt" == "0" ]] && continue
    enriched="$(printf '%s' "$body" | jq --arg cluster "$CONTEXT_NAME" --arg kind "$kind" '
      [.items[] | {
         cluster: $cluster,
         namespace: .metadata.namespace,
         kind: $kind,
         name: .metadata.name,
         classification: "stateless",
         replicas: { desired: (.spec.replicas // .spec.parallelism // null),
                     current: (.status.readyReplicas // .status.availableReplicas // .status.currentNumberScheduled // null) },
         images: [ (.spec.template.spec.containers // .spec.jobTemplate.spec.template.spec.containers // [])[].image ],
         resources: {
           requests: ((.spec.template.spec.containers // .spec.jobTemplate.spec.template.spec.containers // [])[0].resources.requests // {}),
           limits:   ((.spec.template.spec.containers // .spec.jobTemplate.spec.template.spec.containers // [])[0].resources.limits   // {})
         },
         env_summary: [
           ((.spec.template.spec.containers // .spec.jobTemplate.spec.template.spec.containers // [])[]
            | (.env // [])[]
            | if .valueFrom.secretKeyRef then "\(.name)=<secret:\(.valueFrom.secretKeyRef.name)>"
              elif .valueFrom.configMapKeyRef then "\(.name)=<configmap:\(.valueFrom.configMapKeyRef.name)>"
              elif .valueFrom.fieldRef then "\(.name)=<field:\(.valueFrom.fieldRef.fieldPath)>"
              else "\(.name)=<REDACTED>"
              end)
         ],
         volume_mounts: [
           ((.spec.template.spec.containers // .spec.jobTemplate.spec.template.spec.containers // [])[]
            | (.volumeMounts // [])[]
            | { name: .name, mount_path: .mountPath, read_only: (.readOnly // false) })
         ]
       }]')"
    # apply classification
    classified='[]'
    while IFS= read -r row; do
      n="$(jq -r .name <<<"$row")"
      cls="$(classify "$kind" "$n" "$ns")"
      classified="$(jq -c --argjson r "$row" --arg c "$cls" '. + [$r + {classification:$c}]' <<<"$classified")"
    done < <(printf '%s' "$enriched" | jq -c '.[]')
    WORKLOADS_JSON="$(jq -c --argjson a "$WORKLOADS_JSON" --argjson b "$classified" -n '$a + $b')"
  done
done

# ---------- 3. networking --------------------------------------------------

log "phase 3: networking"

SVCS='[]'; INGRESS='[]'
for ns in "${INCLUDED_NS[@]}"; do
  body="$(run_kubectl_json "list svc in $ns" get svc -n "$ns")"
  SVCS="$(jq -c --arg c "$CONTEXT_NAME" --argjson a "$SVCS" --argjson b "$body" -n '
    $a + [ $b.items[] | {
      cluster: $c, namespace: .metadata.namespace, name: .metadata.name,
      type: ( if (.spec.clusterIP=="None") then "Headless" else (.spec.type // "ClusterIP") end ),
      selectors: (.spec.selector // {}),
      external_ips: (.spec.externalIPs // []),
      ports: [ (.spec.ports // [])[] | { name: (.name // ""), port: .port, target_port: .targetPort, protocol: (.protocol // "TCP") } ]
    }]')"

  ingbody="$(run_kubectl_json "list ingress in $ns" get ingress -n "$ns")"
  INGRESS="$(jq -c --arg c "$CONTEXT_NAME" --argjson a "$INGRESS" --argjson b "$ingbody" -n '
    $a + [ $b.items[] | {
      cluster: $c, namespace: .metadata.namespace, name: .metadata.name, kind: "Ingress",
      hosts: [ (.spec.rules // [])[].host ],
      tls: ((.spec.tls // []) | length > 0)
    }]')"

  # Gateway API HTTPRoute (best-effort)
  gwbody="$(kubectl "${KCTX_ARGS[@]}" get httproute -n "$ns" -o json 2>/dev/null || echo '{"items":[]}')"
  INGRESS="$(jq -c --arg c "$CONTEXT_NAME" --argjson a "$INGRESS" --argjson b "$gwbody" -n '
    $a + [ $b.items[]? | { cluster:$c, namespace:.metadata.namespace, name:.metadata.name, kind:"HTTPRoute",
                           hosts: (.spec.hostnames // []), tls: false } ]')"
done

NP_COUNT=0
NP_SAMPLES='[]'
for ns in "${INCLUDED_NS[@]}"; do
  body="$(run_kubectl_json "list netpol in $ns" get networkpolicy -n "$ns")"
  c="$(printf '%s' "$body" | jq '.items|length')"
  NP_COUNT=$((NP_COUNT + c))
  NP_SAMPLES="$(jq -c --arg c "$CONTEXT_NAME" --argjson a "$NP_SAMPLES" --argjson b "$body" -n '
    ($a + [ $b.items[] | { cluster:$c, namespace:.metadata.namespace, name:.metadata.name,
                           policy_types: (.spec.policyTypes // []) }]) | .[0:10]')"
done

# Service mesh resource counts (best-effort, may not be installed)
mesh_count() { kubectl "${KCTX_ARGS[@]}" get "$1" -A --no-headers 2>/dev/null | wc -l | tr -d ' '; }
VS_COUNT="$(mesh_count virtualservice)"; [[ -z "$VS_COUNT" ]] && VS_COUNT=0
DR_COUNT="$(mesh_count destinationrule)"; [[ -z "$DR_COUNT" ]] && DR_COUNT=0
AP_COUNT="$(mesh_count authorizationpolicy)"; [[ -z "$AP_COUNT" ]] && AP_COUNT=0

NETWORKING_JSON="$(jq -nc \
  --argjson svcs "$SVCS" --argjson ing "$INGRESS" \
  --argjson npc "$NP_COUNT" --argjson nps "$NP_SAMPLES" \
  --argjson vsc "$VS_COUNT" --argjson drc "$DR_COUNT" --argjson apc "$AP_COUNT" \
  '{
    services: $svcs,
    ingress: $ing,
    network_policies: { count: $npc, samples: $nps },
    service_mesh: {
      virtual_services:       { count: $vsc, samples: [] },
      destination_rules:      { count: $drc, samples: [] },
      authorization_policies: { count: $apc, samples: [] }
    }
  }')"

# ---------- 4. storage -----------------------------------------------------

log "phase 4: storage"

SC_BODY="$(run_kubectl_json "storageclasses" get sc)"
SC_JSON="$(jq -c '[.items[] | { name: .metadata.name,
                                provisioner: (.provisioner // "unknown"),
                                parameters: (.parameters // {}),
                                reclaim_policy: (.reclaimPolicy // ""),
                                volume_binding_mode: (.volumeBindingMode // "") }]' <<<"$SC_BODY")"

PV_BODY="$(run_kubectl_json "pvs" get pv)"
PV_JSON="$(jq -c '[.items[] | {
  name: .metadata.name,
  size: (.spec.capacity.storage // "0"),
  reclaim_policy: (.spec.persistentVolumeReclaimPolicy // ""),
  access_modes: (.spec.accessModes // []),
  source_type: ( if .spec.csi.driver then .spec.csi.driver
                 elif .spec.nfs then "nfs"
                 elif .spec.hostPath then "hostpath"
                 elif .spec.vsphereVolume then "vsphere-volume"
                 else "unknown" end ),
  storage_class: (.spec.storageClassName // "")
}]' <<<"$PV_BODY")"

PVC_JSON='[]'
for ns in "${INCLUDED_NS[@]}"; do
  body="$(run_kubectl_json "list pvcs in $ns" get pvc -n "$ns")"
  PVC_JSON="$(jq -c --arg c "$CONTEXT_NAME" --argjson a "$PVC_JSON" --argjson b "$body" -n '
    $a + [ $b.items[] | { cluster:$c, namespace:.metadata.namespace, name:.metadata.name,
                          size: (.spec.resources.requests.storage // .status.capacity.storage // "0"),
                          linked_pv: (.spec.volumeName // null),
                          mounted_by: [] } ]')"
done

STORAGE_JSON="$(jq -nc --argjson sc "$SC_JSON" --argjson pv "$PV_JSON" --argjson pvc "$PVC_JSON" \
  '{ storage_classes:$sc, persistent_volumes:$pv, persistent_volume_claims:$pvc }')"

# ---------- 5. identity ----------------------------------------------------

log "phase 5: identity"

SA_TOTAL=0
SA_NONDEFAULT='[]'
for ns in "${INCLUDED_NS[@]}"; do
  body="$(run_kubectl_json "list sa in $ns" get sa -n "$ns")"
  c="$(jq '.items|length' <<<"$body")"
  SA_TOTAL=$((SA_TOTAL + c))
  SA_NONDEFAULT="$(jq -c --arg c "$CONTEXT_NAME" --argjson a "$SA_NONDEFAULT" --argjson b "$body" -n '
    $a + [ $b.items[] | select(.metadata.name != "default")
                      | { cluster:$c, namespace:.metadata.namespace, name:.metadata.name } ]')"
done

CRB_BODY="$(run_kubectl_json "clusterrolebindings" get clusterrolebinding)"
CRB_JSON="$(jq -c --arg c "$CONTEXT_NAME" '
  [ .items[]
    | select( (.subjects // []) | any(.kind=="User" or .kind=="Group" or (.kind=="ServiceAccount" and (.namespace // "" | startswith("kube-") | not))) )
    | { cluster:$c, name:.metadata.name, role_ref:.roleRef.name,
        subjects: [ (.subjects // [])[] | { kind:.kind, name:.name, namespace:(.namespace // "") } ] } ]' <<<"$CRB_BODY")"

# Workload Identity bindings — surfaced via SA annotation `iam.gke.io/gcp-service-account`.
WI_JSON='[]'
for ns in "${INCLUDED_NS[@]}"; do
  body="$(run_kubectl_json "wi sa in $ns" get sa -n "$ns")"
  WI_JSON="$(jq -c --arg c "$CONTEXT_NAME" --argjson a "$WI_JSON" --argjson b "$body" -n '
    $a + [ $b.items[]
           | select((.metadata.annotations // {})["iam.gke.io/gcp-service-account"])
           | { cluster:$c, namespace:.metadata.namespace, k8s_service_account:.metadata.name,
               external_identity: ("gsa:" + (.metadata.annotations["iam.gke.io/gcp-service-account"])) } ]')"
done

IDENTITY_JSON="$(jq -nc \
  --argjson tot "$SA_TOTAL" --argjson nd "$SA_NONDEFAULT" \
  --argjson crb "$CRB_JSON" --argjson wi "$WI_JSON" '
  { service_accounts: { total_count: $tot, with_non_default_tokens: $nd },
    cluster_role_bindings: $crb,
    workload_identity_bindings: $wi }')"

# ---------- 6. external dependencies (best-effort, env-derived) ----------

log "phase 6: external dependencies (env-derived)"

EXT_DEPS='[]'
# Walk each workload's containers' env (literal values) for hostname-shaped strings.
# We deliberately do NOT pull secret values; only `value:` fields are scanned.
for ns in "${INCLUDED_NS[@]}"; do
  for kind in Deployment StatefulSet; do
    body="$(run_kubectl_json "ext-deps $kind in $ns" get "$kind" -n "$ns")"
    EXT_DEPS="$(jq -c --arg c "$CONTEXT_NAME" --arg k "$kind" --argjson a "$EXT_DEPS" --argjson b "$body" -n '
      $a + [ $b.items[] as $w
             | (($w.spec.template.spec.containers // [])[].env // [])[]
             | select(.value != null and (.value | test("^[a-z0-9.-]+\\.[a-z]{2,}(:[0-9]+)?$")))
             | { host: ((.value | split(":"))[0]),
                 port: ( if (.value|test(":[0-9]+$")) then ((.value|split(":"))[1]|tonumber) else null end ),
                 protocol: null,
                 source: "env",
                 used_by: [ "\($c)/\($w.metadata.namespace)/\($k)/\($w.metadata.name)" ] } ]')"
  done
done
# dedup by host+port
EXT_DEPS="$(jq -c '
  group_by([.host, .port])
  | map({ host:.[0].host, port:.[0].port, protocol:.[0].protocol, source:.[0].source,
          used_by: ([.[].used_by[]] | unique) })' <<<"$EXT_DEPS")"

# ---------- 7. CRDs --------------------------------------------------------

log "phase 7: CRDs"

CRDS_BODY="$(run_kubectl_json "crds" get crd)"
CRDS_JSON="$(jq -c '
  def known($g):
    if   $g|test("cert-manager\\.io")          then "cert-manager"
    elif $g|test("externaldns\\.k8s\\.io")     then "external-dns"
    elif $g|test("monitoring\\.coreos\\.com")  then "prometheus-operator"
    elif $g|test("istio\\.io")                 then "istio"
    elif $g|test("config(sync|management)")    then "config-management"
    elif $g|test("gatekeeper\\.sh|constraints\\.gatekeeper") then "gatekeeper"
    elif $g|test("anthos|gke")                 then "anthos"
    else null end;
  [ .items[] | {
      group: .spec.group,
      version: ((.spec.versions // [])[0].name // .spec.version // "v1"),
      kind:    .spec.names.kind,
      scope:   .spec.scope,
      known_operator: known(.spec.group),
      needs_human_review: (known(.spec.group) == null)
  }]' <<<"$CRDS_BODY")"

# ---------- 8. VMware (govc) ----------------------------------------------

log "phase 8: VMware"

VM_CLUSTERS='[]'; VM_HOSTS='[]'; VM_DS='[]'; VM_MAP='[]'
if [[ $NO_VMWARE -eq 1 ]]; then
  skip "govc.*" "skipped via --no-vmware"
elif ! command -v govc >/dev/null; then
  skip "govc" "govc binary not found in PATH"
elif [[ -z "${GOVC_URL:-}" ]]; then
  skip "govc" "GOVC_URL not set; vCenter credentials required"
else
  if ! govc about >/dev/null 2>"$TMPDIR_ROOT/err"; then
    skip "govc about" "vCenter unreachable: $(head -c 200 "$TMPDIR_ROOT/err")"
  else
    # clusters
    while read -r c; do
      [[ -z "$c" ]] && continue
      dc="$(echo "$c" | awk -F/ '{print $2}')"
      name="$(basename "$c")"
      hc="$(govc find "$c" -type h 2>/dev/null | wc -l | tr -d ' ')"
      VM_CLUSTERS="$(jq -c --arg n "$name" --arg dc "$dc" --argjson hc "${hc:-0}" --argjson a "$VM_CLUSTERS" -n \
        '$a + [{name:$n, datacenter:$dc, host_count:$hc}]')"
    done < <(govc find / -type c 2>/dev/null)

    # hosts
    while read -r h; do
      [[ -z "$h" ]] && continue
      info_json="$(govc host.info -json -host "$h" 2>/dev/null || echo '{}')"
      VM_HOSTS="$(jq -c --arg name "$(basename "$h")" --argjson a "$VM_HOSTS" --argjson i "$info_json" -n '
        ($i.HostSystems[0] // {}) as $hs |
        $a + [{
          name: $name,
          cpu_cores: ((($hs.Hardware.CpuInfo.NumCpuCores) // 0) | tonumber? // 0),
          cpu_mhz:   ((($hs.Hardware.CpuInfo.Hz // 0) / 1000000) | floor),
          memory_gb: ((($hs.Hardware.MemorySize // 0) / 1073741824) | floor),
          cpu_utilization_pct: null,
          memory_utilization_pct: null
        }]')"
    done < <(govc find / -type h 2>/dev/null)

    # datastores
    while read -r d; do
      [[ -z "$d" ]] && continue
      info_json="$(govc datastore.info -json "$d" 2>/dev/null || echo '{}')"
      VM_DS="$(jq -c --arg name "$(basename "$d")" --argjson a "$VM_DS" --argjson i "$info_json" -n '
        ($i.Datastores[0] // {}) as $ds |
        $a + [{
          name: $name,
          type: (($ds.Summary.Type // "other") as $t |
                 if   ($t|ascii_upcase) == "VMFS" then "VMFS"
                 elif ($t|ascii_upcase) == "NFS"  then "NFS"
                 elif ($t|ascii_upcase) == "VSAN" then "vSAN"
                 elif ($t|ascii_upcase) == "VVOL" then "VVOL"
                 else "other" end),
          capacity_gb: ((($ds.Summary.Capacity // 0) / 1073741824) | floor),
          free_gb:     ((($ds.Summary.FreeSpace // 0) / 1073741824) | floor),
          iops_capability: null
        }]')"
    done < <(govc find / -type s 2>/dev/null)

    # vm → node mapping (best-effort: match VM name to node)
    while read -r node_name; do
      [[ -z "$node_name" ]] && continue
      vm_path="$(govc find / -type m -name "$node_name" 2>/dev/null | head -1)"
      [[ -z "$vm_path" ]] && continue
      VM_MAP="$(jq -c --arg vm "$(basename "$vm_path")" --arg node "$node_name" --argjson a "$VM_MAP" -n \
        '$a + [{vm_name:$vm, k8s_node:$node, cluster:"", host:""}]')"
    done < <(jq -r '.items[].metadata.name' <<<"$NODES_JSON")
  fi
fi

VMWARE_JSON="$(jq -nc \
  --argjson c "$VM_CLUSTERS" --argjson h "$VM_HOSTS" \
  --argjson d "$VM_DS"      --argjson m "$VM_MAP" \
  '{ clusters:$c, hosts:$h, datastores:$d, vm_to_node_mapping:$m }')"

# ---------- 9. utilization (kubectl top) ----------------------------------

log "phase 9: utilization"

UTIL_NODES='[]'; UTIL_PODS='[]'
SUM_CPU=null; SUM_MEM=null; OVER=null; METRICS_SRC=null

if [[ $NO_UTIL -eq 1 ]]; then
  skip "kubectl top" "skipped via --no-utilization"
else
  TOP_NODES_TXT="$(run_kubectl_text "kubectl top nodes" top nodes --no-headers)"
  if [[ -n "$TOP_NODES_TXT" ]]; then
    METRICS_SRC='"metrics-server"'
    # Build per-node merge of capacity + usage
    UTIL_NODES="$(jq -c --arg cluster "$CONTEXT_NAME" --argjson n "$NODES_JSON" \
      --arg top "$TOP_NODES_TXT" -n '
      ($top | split("\n") | map(select(length>0) | split(" +"; "x") | {name: .[0], cpu_usage: .[1], memory_usage: .[3]})) as $u |
      [ $n.items[] as $node |
        ($u | map(select(.name == $node.metadata.name)) | .[0] // {}) as $m |
        { cluster:$cluster, name:$node.metadata.name,
          cpu_capacity: ($node.status.capacity.cpu // ""),
          cpu_allocatable: ($node.status.allocatable.cpu // ""),
          cpu_usage: ($m.cpu_usage // null),
          memory_capacity: ($node.status.capacity.memory // ""),
          memory_allocatable: ($node.status.allocatable.memory // ""),
          memory_usage: ($m.memory_usage // null),
          cpu_utilization_pct_30d_avg: null, cpu_utilization_pct_30d_p95: null, cpu_utilization_pct_30d_max: null,
          memory_utilization_pct_30d_avg: null, memory_utilization_pct_30d_p95: null, memory_utilization_pct_30d_max: null
        } ]')"
  fi

  # top pods per included namespace
  for ns in "${INCLUDED_NS[@]}"; do
    txt="$(kubectl "${KCTX_ARGS[@]}" top pods -n "$ns" --no-headers 2>/dev/null || true)"
    [[ -z "$txt" ]] && continue
    UTIL_PODS="$(jq -c --arg cluster "$CONTEXT_NAME" --arg ns "$ns" --arg t "$txt" --argjson a "$UTIL_PODS" -n '
      $a + ( $t | split("\n") | map(select(length>0))
              | map(split(" +"; "x"))
              | map({ cluster:$cluster, namespace:$ns, name:.[0], owner:null,
                      cpu_request:null, cpu_limit:null, cpu_usage:.[1],
                      memory_request:null, memory_limit:null, memory_usage:.[2],
                      restart_count:null }) )')"
  done
  # cap to MAX_PODS (sort by raw cpu_usage string desc — best-effort)
  UTIL_PODS="$(jq -c --argjson n "$MAX_PODS" '
    sort_by(.cpu_usage // "") | reverse | .[0:$n]' <<<"$UTIL_PODS")"
fi

UTIL_JSON="$(jq -nc \
  --argjson nodes "$UTIL_NODES" --argjson pods "$UTIL_PODS" \
  --argjson sumcpu "$SUM_CPU" --argjson summem "$SUM_MEM" --argjson over "$OVER" \
  --argjson msrc "$METRICS_SRC" '
  { nodes:$nodes, pods:$pods,
    summary: { cluster_cpu_utilization_pct:$sumcpu, cluster_memory_utilization_pct:$summem,
               over_provisioning_ratio:$over, metrics_source:$msrc } }')"

# ---------- 10. traffic (best-effort: empty unless mesh telemetry) -------

log "phase 10: traffic (best-effort)"

TRAFFIC_JSON='{"pairs":[],"summary":{"east_west_bytes_per_sec":null,"north_south_bytes_per_sec":null,"total_service_pairs":null,"telemetry_source":null}}'
skip "prometheus istio_requests_total" "no telemetry scrape implemented in v0.3 self-export; fall back to mesh-aware Discovery Option 4"

# ---------- assemble bundle -----------------------------------------------

log "assembling bundle → $OUT"

GEN_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

SKIPPED_JSON="$(if [[ -s "$SKIPPED_FILE" ]]; then jq -s . "$SKIPPED_FILE"; else echo '[]'; fi)"
WARNINGS_JSON="$(if [[ -s "$WARN_FILE" ]]; then jq -s . "$WARN_FILE"; else echo '[]'; fi)"

jq -n \
  --arg ver "0.2.0" \
  --arg gen "$GEN_AT" \
  --arg by  "self-export-script" \
  --argjson scope    "$SCOPE_JSON" \
  --argjson clusters "[$CLUSTER_INVENTORY]" \
  --argjson workloads "$WORKLOADS_JSON" \
  --argjson networking "$NETWORKING_JSON" \
  --argjson storage    "$STORAGE_JSON" \
  --argjson identity   "$IDENTITY_JSON" \
  --argjson extdeps    "$EXT_DEPS" \
  --argjson crds       "$CRDS_JSON" \
  --argjson vmware     "$VMWARE_JSON" \
  --argjson util       "$UTIL_JSON" \
  --argjson traffic    "$TRAFFIC_JSON" \
  --argjson skipped    "$SKIPPED_JSON" \
  --argjson warnings   "$WARNINGS_JSON" \
  '{
     schema_version: $ver,
     generated_at: $gen,
     generated_by: $by,
     scope: $scope,
     clusters: $clusters,
     workloads: $workloads,
     networking: $networking,
     storage: $storage,
     identity: $identity,
     external_dependencies: $extdeps,
     crds: $crds,
     vmware: $vmware,
     utilization: $util,
     traffic: $traffic,
     skipped: $skipped,
     warnings: $warnings
   }' >"$OUT"

log "done. bundle written to $OUT"
log "  workloads: $(jq '.workloads|length' <"$OUT")"
log "  pvs: $(jq '.storage.persistent_volumes|length' <"$OUT")  pvcs: $(jq '.storage.persistent_volume_claims|length' <"$OUT")"
log "  crds: $(jq '.crds|length' <"$OUT")  warnings: $(jq '.warnings|length' <"$OUT")  skipped: $(jq '.skipped|length' <"$OUT")"
