#!/usr/bin/env bash
# scripts/discovery/_common.sh
#
# Shared helpers for ACMF Phase 1 discovery export scripts.
# Sourced by anthos-vmware-export.sh, anthos-gcp-export.sh, ... etc.
#
# This file is read-only utility code — it MUST NOT issue any kubectl/cloud
# write operations of its own. Callers are responsible for keeping their
# command list read-only.

# Strict mode for sourced scripts
set -o nounset
set -o pipefail

# ----- ANSI helpers (best-effort; safe in non-tty) -----
if [ -t 2 ]; then
  __C_RED=$'\033[0;31m'
  __C_YEL=$'\033[0;33m'
  __C_GRN=$'\033[0;32m'
  __C_DIM=$'\033[2m'
  __C_RST=$'\033[0m'
else
  __C_RED=""; __C_YEL=""; __C_GRN=""; __C_DIM=""; __C_RST=""
fi

log_info()  { printf '%s[INFO]%s %s\n'  "${__C_GRN}" "${__C_RST}" "$*" >&2; }
log_warn()  { printf '%s[WARN]%s %s\n'  "${__C_YEL}" "${__C_RST}" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "${__C_RED}" "${__C_RST}" "$*" >&2; }
log_dim()   { printf '%s%s%s\n'         "${__C_DIM}" "$*" "${__C_RST}" >&2; }

# Schema constant — bump when the bundle schema changes.
ACMF_SCHEMA_VERSION="${ACMF_SCHEMA_VERSION:-1.0.0}"

# ----- preflight -----

# require_cmd <name> [<install-hint>]
# Exit 2 if the command is missing.
require_cmd() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Required command not found in PATH: $cmd"
    if [ -n "$hint" ]; then
      log_error "  → $hint"
    fi
    exit 2
  fi
}

# Best-effort soft check (warn but do not exit).
have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# ----- arg parsing helpers -----

# Common flag names every export script accepts.
#   --output FILE          (default: ./discovery-bundle.json)
#   --include-namespaces a,b,c
#   --exclude-namespaces  x,y
#   --include-system     (include kube-*/openshift-*/cattle-* namespaces)
#   --dry-run            (print planned commands, do not execute)
#   --kubeconfig FILE
#   --context NAME
#   --help / -h
#
# Caller is expected to:
#   1. parse_common_args "$@" first, then handle leftover platform-specific flags
#   2. read globals: OUTPUT_FILE, NS_INCLUDE, NS_EXCLUDE, INCLUDE_SYSTEM, DRY_RUN,
#                    KUBECONFIG_FILE, KUBE_CONTEXT, REMAINING_ARGS

OUTPUT_FILE="discovery-bundle.json"
NS_INCLUDE=""
NS_EXCLUDE=""
INCLUDE_SYSTEM=0
DRY_RUN=0
KUBECONFIG_FILE=""
KUBE_CONTEXT=""
REMAINING_ARGS=()

parse_common_args() {
  REMAINING_ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --output)
        OUTPUT_FILE="${2:?}"; shift 2 ;;
      --output=*)
        OUTPUT_FILE="${1#*=}"; shift ;;
      --include-namespaces)
        NS_INCLUDE="${2:?}"; shift 2 ;;
      --include-namespaces=*)
        NS_INCLUDE="${1#*=}"; shift ;;
      --exclude-namespaces)
        NS_EXCLUDE="${2:?}"; shift 2 ;;
      --exclude-namespaces=*)
        NS_EXCLUDE="${1#*=}"; shift ;;
      --include-system)
        INCLUDE_SYSTEM=1; shift ;;
      --dry-run)
        DRY_RUN=1; shift ;;
      --kubeconfig)
        KUBECONFIG_FILE="${2:?}"; shift 2 ;;
      --kubeconfig=*)
        KUBECONFIG_FILE="${1#*=}"; shift ;;
      --context)
        KUBE_CONTEXT="${2:?}"; shift 2 ;;
      --context=*)
        KUBE_CONTEXT="${1#*=}"; shift ;;
      -h|--help)
        # Caller defines print_usage; if missing, just exit 0 silently.
        if declare -f print_usage >/dev/null 2>&1; then print_usage; fi
        exit 0 ;;
      --)
        shift; REMAINING_ARGS+=("$@"); break ;;
      *)
        REMAINING_ARGS+=("$1"); shift ;;
    esac
  done
}

# kubectl wrapper that respects --kubeconfig / --context flags.
kc() {
  local args=()
  [ -n "$KUBECONFIG_FILE" ] && args+=(--kubeconfig "$KUBECONFIG_FILE")
  [ -n "$KUBE_CONTEXT" ]    && args+=(--context "$KUBE_CONTEXT")
  if [ "$DRY_RUN" = "1" ]; then
    printf 'DRY-RUN: kubectl %s %s\n' "${args[*]:-}" "$*" >&2
    return 0
  fi
  kubectl "${args[@]}" "$@"
}

# Run a command (or echo it if --dry-run); used for non-kubectl tools.
run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf 'DRY-RUN: %s\n' "$*" >&2
    return 0
  fi
  "$@"
}

# ----- bundle assembly helpers -----

# now_iso → ISO-8601 UTC "2026-05-27T06:40:00Z"
now_iso() {
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

# bundle_skeleton <source_platform>
# Print a minimal, schema-valid bundle skeleton to stdout.
bundle_skeleton() {
  local platform="$1"
  local include_csv exclude_csv
  if [ -n "$NS_INCLUDE" ]; then
    include_csv="$(printf '%s' "$NS_INCLUDE" | jq -R 'split(",") | map(select(length>0))')"
  else
    include_csv="[]"
  fi
  if [ -n "$NS_EXCLUDE" ]; then
    exclude_csv="$(printf '%s' "$NS_EXCLUDE" | jq -R 'split(",") | map(select(length>0))')"
  else
    exclude_csv="[]"
  fi

  jq -n \
    --arg sv "$ACMF_SCHEMA_VERSION" \
    --arg ts "$(now_iso)" \
    --arg gen "self-export-script" \
    --arg plat "$platform" \
    --argjson inc "$include_csv" \
    --argjson exc "$exclude_csv" \
    '{
       schema_version: $sv,
       generated_at: $ts,
       generated_by: $gen,
       source_platform: $plat,
       scope: {
         clusters: [],
         namespaces_included: $inc,
         namespaces_excluded: $exc
       },
       clusters: [],
       workloads: [],
       networking: {},
       storage: {},
       identity: {},
       external_dependencies: [],
       crds: [],
       skipped: [],
       warnings: []
     }'
}

# emit_bundle_stub <source_platform> <output_path>
# Used by --dry-run mode to drop a minimal but schema-valid bundle so callers
# can chain validate-bundle.sh in CI even when no cluster is reachable.
emit_bundle_stub() {
  local platform="$1"
  local out="$2"
  bundle_skeleton "$platform" | \
    jq --arg cmd "live-cluster-discovery" --arg reason "dry-run mode" \
       '.skipped += [{command: $cmd, reason: $reason}]
        | .warnings += ["Generated by --dry-run; no live data collected."]' \
    >"$out"
}

# Default system-namespace exclusion list per platform family.
# Callers can override by passing --include-system.
default_system_namespaces() {
  case "${1:-generic}" in
    anthos-*)
      echo "kube-system,kube-public,kube-node-lease,gke-system,gmp-system,config-management-system,anthos-identity-service,gke-managed-system,gke-connect" ;;
    openshift)
      echo "openshift,openshift-apiserver,openshift-authentication,openshift-cluster-version,openshift-controller-manager,openshift-dns,openshift-etcd,openshift-image-registry,openshift-ingress,openshift-kube-apiserver,openshift-kube-controller-manager,openshift-kube-scheduler,openshift-machine-api,openshift-machine-config-operator,openshift-marketplace,openshift-monitoring,openshift-network-operator,openshift-node,openshift-operator-lifecycle-manager,openshift-operators,openshift-sdn,openshift-service-ca,kube-system,kube-public,kube-node-lease" ;;
    rancher)
      echo "kube-system,kube-public,kube-node-lease,cattle-system,cattle-fleet-system,cattle-fleet-local-system,cattle-impersonation-system,cattle-monitoring-system,cattle-logging-system,fleet-default,fleet-local,ingress-nginx,longhorn-system" ;;
    *)
      echo "kube-system,kube-public,kube-node-lease" ;;
  esac
}

# Resolve the effective namespace exclusion list (CSV).
effective_excludes() {
  local platform="${1:-generic}"
  if [ "$INCLUDE_SYSTEM" = "1" ]; then
    printf '%s\n' "$NS_EXCLUDE"
    return
  fi
  local sys
  sys="$(default_system_namespaces "$platform")"
  if [ -z "$NS_EXCLUDE" ]; then
    printf '%s\n' "$sys"
  else
    printf '%s,%s\n' "$sys" "$NS_EXCLUDE"
  fi
}

# ----- CRD classification heuristics (shared) -----
crd_is_known() {
  case "$1" in
    *cert-manager.io*|*external-dns*|*monitoring.coreos.com*|*networking.istio.io*) return 0 ;;
    *gateway.networking.k8s.io*|*argoproj.io*|*flux*|*postgres-operator*|*kafka.strimzi.io*) return 0 ;;
    *) return 1 ;;
  esac
}

# Convenience: append a skipped entry to the bundle file in-place.
bundle_add_skipped() {
  local file="$1" cmd="$2" reason="$3"
  local tmp; tmp="$(mktemp)"
  jq --arg c "$cmd" --arg r "$reason" \
     '.skipped += [{command: $c, reason: $r}]' \
     "$file" >"$tmp" && mv "$tmp" "$file"
}

bundle_add_warning() {
  local file="$1" msg="$2"
  local tmp; tmp="$(mktemp)"
  jq --arg m "$msg" '.warnings += [$m]' "$file" >"$tmp" && mv "$tmp" "$file"
}

# ----- shared core collector (kubectl-only) -----
#
# core_kube_collect <bundle_path> <platform> <cluster_location>
#
# Collects clusters / namespaces / workloads / networking / storage / identity
# / CRDs / external_dependencies via plain kubectl. Platform scripts call this
# first, then layer on platform-specific blocks (Anthos meta, OpenShift
# operators, Rancher fleet, vSphere, etc.).
#
# Globals consumed: NS_INCLUDE, NS_EXCLUDE, INCLUDE_SYSTEM, KUBECONFIG_FILE,
# KUBE_CONTEXT, DRY_RUN.
#
# Sets exported globals for downstream platform-specific steps:
#   CORE_CLUSTER_NAME      — kube context / cluster name
#   CORE_NS_LIST_JSON      — JSON array of in-scope namespaces
#   CORE_WORKLOADS_RAW     — full kubectl get workloads JSON (for re-mining)
core_kube_collect() {
  local bundle="$1"
  local platform="$2"
  local location="${3:-unknown}"

  local cluster_name cluster_version
  cluster_name="$(kc config current-context 2>/dev/null || echo unknown)"
  cluster_version="$(kc version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion // "unknown"')"
  CORE_CLUSTER_NAME="$cluster_name"

  local nodes_json
  nodes_json="$(kc get nodes -o json 2>/dev/null || echo '{"items":[]}')"

  local cluster_block
  cluster_block="$(jq -n \
    --arg name "$cluster_name" \
    --arg version "$cluster_version" \
    --arg plat "$platform" \
    --arg loc "$location" \
    --argjson nodes "$nodes_json" \
    '{
       name: $name,
       version: $version,
       platform: $plat,
       location: $loc,
       control_plane: { ha: ((($nodes.items // []) | map(select(.metadata.labels["node-role.kubernetes.io/control-plane"] != null or .metadata.labels["node-role.kubernetes.io/master"] != null)) | length) > 1) },
       node_pools: ((($nodes.items // []) | group_by(.metadata.labels["node.kubernetes.io/instance-type"] // .metadata.labels["beta.kubernetes.io/instance-type"] // "default") | map({
         name: (.[0].metadata.labels["node.kubernetes.io/instance-type"] // .[0].metadata.labels["beta.kubernetes.io/instance-type"] // "default"),
         count: length,
         k8s_version: (.[0].status.nodeInfo.kubeletVersion // "unknown"),
         os_image: (.[0].status.nodeInfo.osImage // "unknown")
       })))
     }')"
  jq --argjson c "$cluster_block" \
     '.clusters += [$c] | .scope.clusters += [$c.name]' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # Namespaces
  local ns_excludes ns_json ns_list
  ns_excludes="$(effective_excludes "$platform")"
  ns_json="$(kc get ns -o json 2>/dev/null || echo '{"items":[]}')"
  ns_list="$(jq -n \
    --argjson all "$ns_json" \
    --arg inc "$NS_INCLUDE" \
    --arg exc "$ns_excludes" \
    '
    ($all.items // []) | map(.metadata.name)
      | (if ($inc|length) > 0 then map(select(. as $n | ($inc | split(",")) | index($n))) else . end)
      | (if ($exc|length) > 0 then map(select(. as $n | ($exc | split(",")) | index($n) | not)) else . end)
    ')"
  CORE_NS_LIST_JSON="$ns_list"

  # Workloads
  local wl_json
  wl_json="$(kc get deploy,sts,ds,job,cronjob -A -o json 2>/dev/null || echo '{"items":[]}')"
  CORE_WORKLOADS_RAW="$wl_json"
  local wl_array
  wl_array="$(jq -n \
    --argjson w "$wl_json" \
    --argjson nslist "$ns_list" \
    --arg cluster "$cluster_name" \
    '
    [($w.items // [])[] | select(.metadata.namespace as $ns | ($nslist | index($ns)))
      | {
          cluster: $cluster,
          namespace: .metadata.namespace,
          kind: (.kind // "Other"),
          name: .metadata.name,
          classification: (
            if .kind == "StatefulSet" then "stateful"
            elif .kind == "Job" or .kind == "CronJob" then "batch"
            elif (.metadata.namespace | test("^(kube|gke|gmp|openshift|cattle|fleet|config-management)-")) then "system"
            else "stateless" end
          ),
          replicas: { desired: (.spec.replicas // 1), current: (.status.replicas // 0) },
          containers: [(.spec.template.spec.containers // .spec.jobTemplate.spec.template.spec.containers // [])[] | { name, image, resources: (.resources // {}) }],
          volumes: [((.spec.template.spec.volumes // []) | .[] | { name })],
          labels: (.metadata.labels // {})
        }
    ]')"
  jq --argjson wl "$wl_array" '.workloads += $wl' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # Networking
  local svc_json ing_json np_json
  svc_json="$(kc get svc -A -o json 2>/dev/null || echo '{"items":[]}')"
  ing_json="$(kc get ingress -A -o json 2>/dev/null || echo '{"items":[]}')"
  np_json="$(kc get networkpolicy -A -o json 2>/dev/null  || echo '{"items":[]}')"
  local net_block
  net_block="$(jq -n --argjson svc "$svc_json" --argjson ing "$ing_json" --argjson np "$np_json" \
    '{
       services_total: (($svc.items // []) | length),
       services_by_type: (($svc.items // []) | group_by(.spec.type // "ClusterIP") | map({(.[0].spec.type // "ClusterIP"): length}) | add),
       ingress_total: (($ing.items // []) | length),
       network_policies_total: (($np.items // []) | length)
     }')"
  jq --argjson n "$net_block" '.networking = $n' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # Storage
  local sc_json pv_json pvc_json
  sc_json="$(kc get sc -o json 2>/dev/null   || echo '{"items":[]}')"
  pv_json="$(kc get pv -o json 2>/dev/null   || echo '{"items":[]}')"
  pvc_json="$(kc get pvc -A -o json 2>/dev/null || echo '{"items":[]}')"
  local storage_block
  storage_block="$(jq -n --argjson sc "$sc_json" --argjson pv "$pv_json" --argjson pvc "$pvc_json" \
    '{
       storage_classes: [(($sc.items // [])[] | { name: .metadata.name, provisioner: .provisioner })],
       pv_count: (($pv.items // []) | length),
       pvc_count: (($pvc.items // []) | length),
       provisioners_in_use: [(($pv.items // [])[].spec.csi.driver // ($pv.items // [])[].spec.storageClassName // "unknown")] | unique
     }')"
  jq --argjson s "$storage_block" '.storage = $s' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # Identity
  local sa_json crb_json
  sa_json="$(kc get sa -A -o json 2>/dev/null    || echo '{"items":[]}')"
  crb_json="$(kc get clusterrolebinding -o json 2>/dev/null || echo '{"items":[]}')"
  local id_block
  id_block="$(jq -n --argjson sa "$sa_json" --argjson crb "$crb_json" \
    '{
       service_accounts_total: (($sa.items // []) | length),
       cluster_role_bindings_total: (($crb.items // []) | length)
     }')"
  jq --argjson i "$id_block" '.identity = $i' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # CRDs
  local crd_json
  crd_json="$(kc get crd -o json 2>/dev/null || echo '{"items":[]}')"
  local crd_array
  crd_array="$(jq -n --argjson c "$crd_json" \
    '[($c.items // [])[] | {
       name: .metadata.name,
       group: .spec.group,
       versions: [.spec.versions[].name],
       scope: .spec.scope
     }]')"
  jq --argjson c "$crd_array" '.crds += $c' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # External dependencies (heuristic: env-var hostnames)
  local ext_array
  ext_array="$(jq -n --argjson w "$wl_json" \
    '[($w.items // [])[]?.spec.template.spec.containers[]?.env[]?
      | select(.value? | type == "string" and test("^[a-zA-Z0-9.-]+\\.(svc|com|net|io|local)(:[0-9]+)?$"))
      | { host: .value, used_by: [] }] | unique_by(.host)' 2>/dev/null || echo '[]')"
  jq --argjson e "$ext_array" '.external_dependencies += $e' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
}

# Default dry-run hint for platforms that don't override it.
core_dry_run_hint() {
  log_dim "  kubectl version -o json"
  log_dim "  kubectl get nodes -o json"
  log_dim "  kubectl get ns -o json"
  log_dim "  kubectl get deploy,sts,ds,job,cronjob -A -o json"
  log_dim "  kubectl get svc,ingress,networkpolicy -A -o json"
  log_dim "  kubectl get pv,pvc,sc -A -o json"
  log_dim "  kubectl get sa,clusterrolebinding -A -o json"
  log_dim "  kubectl get crd -o json"
}
