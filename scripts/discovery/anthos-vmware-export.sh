#!/usr/bin/env bash
# scripts/discovery/anthos-vmware-export.sh
#
# ACMF Phase 1 self-export script — Anthos clusters on VMware vSphere.
#
# Reads cluster topology, workloads, networking, storage, identity, CRDs, and
# (optionally) the underlying vSphere inventory, then writes a single JSON
# bundle that conforms to schemas/discovery-bundle.schema.json.
#
# Read-only: this script never issues a write/mutate command. If a command
# would require write access it is logged to bundle.skipped[] and execution
# continues.
#
# Usage:
#   ./anthos-vmware-export.sh \
#       [--output discovery-bundle.json] \
#       [--include-namespaces app1,app2] \
#       [--exclude-namespaces noisy] \
#       [--include-system] \
#       [--kubeconfig PATH] [--context CTX] \
#       [--dry-run]
#
# Required tools : kubectl, jq
# Optional tools : gcloud   (Anthos-on-GCP control-plane metadata)
#                  govc     (vSphere VM↔node mapping; set GOVC_URL etc.)
# Permissions    : read-only ServiceAccount with cluster-reader equivalent.
#                  govc account must be a vSphere read-only role.
# Estimated time : 1-3 min for ≤5 clusters / ≤200 workloads (without govc).
#
# Air-gapped friendly: no outbound network calls beyond the customer's own
# kube-apiserver / vCenter. Does not phone home.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_common.sh"

PLATFORM="anthos-vmware"

print_usage() {
  cat <<EOF
Anthos-on-VMware discovery export.

Usage: $(basename "$0") [options]

Options:
  --output FILE            Output bundle path (default: ./discovery-bundle.json)
  --include-namespaces CSV Limit collection to listed namespaces
  --exclude-namespaces CSV Skip these namespaces (added to default system list)
  --include-system         Do NOT skip kube-*/gke-*/gmp-*/config-management-* namespaces
  --kubeconfig PATH        Override KUBECONFIG
  --context NAME           kubectl context to use (defaults to current)
  --dry-run                Print planned commands; emit a stub bundle only
  -h, --help               This help

Read-only. Estimated runtime 1-3 min for small fleets.
EOF
}

main() {
  parse_common_args "$@"

  require_cmd kubectl "Install: https://kubernetes.io/docs/tasks/tools/"
  require_cmd jq      "Install: https://stedolan.github.io/jq/"

  if ! have_cmd gcloud; then
    log_warn "gcloud not found — skipping Anthos-on-GCP metadata enrichment."
  fi
  if ! have_cmd govc; then
    log_warn "govc not found — skipping vSphere VM↔node mapping."
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log_info "Dry-run: emitting schema-valid stub bundle to ${OUTPUT_FILE}"
    emit_bundle_stub "$PLATFORM" "$OUTPUT_FILE"
    log_info "Planned commands (subset):"
    log_dim "  kubectl version -o json"
    log_dim "  kubectl get nodes -o json"
    log_dim "  kubectl get ns -o json"
    log_dim "  kubectl get deploy,sts,ds,job,cronjob -A -o json"
    log_dim "  kubectl get svc,ingress,networkpolicy -A -o json"
    log_dim "  kubectl get pv,pvc,sc -A -o json"
    log_dim "  kubectl get sa,rolebinding,clusterrolebinding -A -o json"
    log_dim "  kubectl get crd -o json"
    log_dim "  kubectl -n istio-system get virtualservices,destinationrules -o json (if istio installed)"
    log_dim "  govc ls / vm.info / host.info  (if govc available)"
    log_info "Dry-run complete."
    return 0
  fi

  # 1. Initialize bundle skeleton
  local bundle="$OUTPUT_FILE"
  bundle_skeleton "$PLATFORM" >"$bundle"
  log_info "Initialized bundle at $bundle"

  # 2. Cluster inventory (current context only — multi-cluster discovery is
  #    iterative: rerun with --context for each cluster).
  log_info "Collecting cluster info…"
  local cluster_name cluster_version
  if cluster_name="$(kc config current-context 2>/dev/null)"; then :; else cluster_name="unknown"; fi
  cluster_version="$(kc version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion // "unknown"')"

  # Anthos version probes (best-effort, namespace-dependent).
  local anthos_ver="" csm_ver=""
  anthos_ver="$(kc -n kube-system get deployment gke-connect-agent -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null \
                  | awk -F: '{print $NF}')" || true
  csm_ver="$(kc -n istio-system get deployment istiod -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null \
                  | awk -F: '{print $NF}')" || true

  local nodes_json
  nodes_json="$(kc get nodes -o json 2>/dev/null || echo '{"items":[]}')"

  local cluster_block
  cluster_block="$(jq -n \
    --arg name    "$cluster_name" \
    --arg version "$cluster_version" \
    --arg plat    "$PLATFORM" \
    --arg av      "$anthos_ver" \
    --arg cv      "$csm_ver" \
    --argjson nodes "$nodes_json" \
    '{
       name: $name,
       version: $version,
       platform: $plat,
       location: "on-prem-vmware",
       control_plane: { ha: ((($nodes.items // []) | map(select(.metadata.labels["node-role.kubernetes.io/control-plane"] != null)) | length) > 1) },
       node_pools: ((($nodes.items // []) | group_by(.metadata.labels["cloud.google.com/gke-nodepool"] // "default") | map({
         name: (.[0].metadata.labels["cloud.google.com/gke-nodepool"] // "default"),
         count: length,
         k8s_version: (.[0].status.nodeInfo.kubeletVersion // "unknown"),
         os_image: (.[0].status.nodeInfo.osImage // "unknown")
       }))),
       anthos: {
         version: $av,
         service_mesh: { istio_version: $cv }
       }
     }')"

  jq --argjson c "$cluster_block" \
     '.clusters += [$c] | .scope.clusters += [$c.name]' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # 3. Namespaces
  log_info "Collecting namespaces…"
  local ns_excludes
  ns_excludes="$(effective_excludes "anthos-vmware")"
  local ns_json
  ns_json="$(kc get ns -o json 2>/dev/null || echo '{"items":[]}')"

  # Build the final namespace list to scan.
  local ns_list
  ns_list="$(jq -n \
    --argjson all "$ns_json" \
    --arg inc "$NS_INCLUDE" \
    --arg exc "$ns_excludes" \
    '
    ($all.items // []) | map(.metadata.name)
      | (if ($inc|length) > 0 then map(select(. as $n | ($inc | split(",")) | index($n))) else . end)
      | (if ($exc|length) > 0 then map(select(. as $n | ($exc | split(",")) | index($n) | not)) else . end)
    ')"

  # 4. Workloads (Deployments / StatefulSets / DaemonSets / Jobs / CronJobs)
  log_info "Collecting workloads…"
  local wl_json
  wl_json="$(kc get deploy,sts,ds,job,cronjob -A -o json 2>/dev/null || echo '{"items":[]}')"

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
            elif (.metadata.namespace | test("^(kube|gke|gmp|config-management)-")) then "system"
            else "stateless" end
          ),
          replicas: { desired: (.spec.replicas // 1), current: (.status.replicas // 0) },
          containers: [(.spec.template.spec.containers // .spec.jobTemplate.spec.template.spec.containers // [])[] | {
            name, image,
            resources: (.resources // {})
          }],
          volumes: [((.spec.template.spec.volumes // []) | .[] | { name })],
          labels: (.metadata.labels // {})
        }
    ]')"

  jq --argjson wl "$wl_array" '.workloads += $wl' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # 5. Networking
  log_info "Collecting networking…"
  local svc_json ing_json np_json
  svc_json="$(kc get svc -A -o json 2>/dev/null || echo '{"items":[]}')"
  ing_json="$(kc get ingress -A -o json 2>/dev/null || echo '{"items":[]}')"
  np_json="$(kc get networkpolicy -A -o json 2>/dev/null || echo '{"items":[]}')"

  local net_block
  net_block="$(jq -n \
    --argjson svc "$svc_json" \
    --argjson ing "$ing_json" \
    --argjson np  "$np_json" \
    '{
       services_total: (($svc.items // []) | length),
       services_by_type: (($svc.items // []) | group_by(.spec.type // "ClusterIP") | map({(.[0].spec.type // "ClusterIP"): length}) | add),
       ingress_total: (($ing.items // []) | length),
       network_policies_total: (($np.items // []) | length)
     }')"

  jq --argjson n "$net_block" '.networking = $n' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # 6. Storage
  log_info "Collecting storage…"
  local sc_json pv_json pvc_json
  sc_json="$(kc get sc -o json 2>/dev/null || echo '{"items":[]}')"
  pv_json="$(kc get pv -o json 2>/dev/null || echo '{"items":[]}')"
  pvc_json="$(kc get pvc -A -o json 2>/dev/null || echo '{"items":[]}')"

  local storage_block
  storage_block="$(jq -n \
    --argjson sc "$sc_json" \
    --argjson pv "$pv_json" \
    --argjson pvc "$pvc_json" \
    '{
       storage_classes: [(($sc.items // [])[] | { name: .metadata.name, provisioner: .provisioner })],
       pv_count: (($pv.items // []) | length),
       pvc_count: (($pvc.items // []) | length),
       provisioners_in_use: [(($pv.items // [])[].spec.csi.driver // ($pv.items // [])[].spec.storageClassName // "unknown")] | unique,
       vsphere_csi_pv_count: [(($pv.items // [])[] | select(.spec.csi.driver == "csi.vsphere.vmware.com"))] | length
     }')"

  jq --argjson s "$storage_block" '.storage = $s' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # 7. Identity / RBAC
  log_info "Collecting identity / RBAC…"
  local sa_json crb_json
  sa_json="$(kc get sa -A -o json 2>/dev/null  || echo '{"items":[]}')"
  crb_json="$(kc get clusterrolebinding -o json 2>/dev/null || echo '{"items":[]}')"
  local id_block
  id_block="$(jq -n \
    --argjson sa "$sa_json" \
    --argjson crb "$crb_json" \
    '{
       service_accounts_total: (($sa.items // []) | length),
       cluster_role_bindings_total: (($crb.items // []) | length),
       workload_identity_enabled: (($sa.items // []) | any(.metadata.annotations["iam.gke.io/gcp-service-account"]?))
     }')"
  jq --argjson i "$id_block" '.identity = $i' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # 8. CRDs
  log_info "Collecting CRDs…"
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

  # 9. External dependencies (heuristic: scan env vars for hostnames)
  log_info "Inferring external dependencies…"
  local ext_array
  ext_array="$(jq -n --argjson w "$wl_json" \
    '[($w.items // [])[]?.spec.template.spec.containers[]?.env[]?
      | select(.value? | type == "string" and test("^[a-zA-Z0-9.-]+\\.(svc|com|net|io|local)(:[0-9]+)?$"))
      | { host: .value, used_by: [] }] | unique_by(.host)' 2>/dev/null || echo '[]')"
  jq --argjson e "$ext_array" '.external_dependencies += $e' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # 10. vSphere layer (optional)
  if have_cmd govc; then
    log_info "Collecting vSphere inventory via govc (read-only)…"
    if govc about >/dev/null 2>&1; then
      local hosts dstores
      hosts="$(govc find -type h 2>/dev/null | wc -l | tr -d ' ')"
      dstores="$(govc find -type s 2>/dev/null | wc -l | tr -d ' ')"
      jq --arg hosts "$hosts" --arg ds "$dstores" \
         '.vmware = { hosts_count: ($hosts|tonumber), datastores_count: ($ds|tonumber) }' \
         "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
    else
      bundle_add_skipped "$bundle" "govc about" "vCenter unreachable or GOVC_URL/GOVC_USERNAME unset"
    fi
  else
    bundle_add_skipped "$bundle" "govc ls / vm.info" "govc CLI not installed"
  fi

  # 11. Precise warnings (only when actionable)
  local csi_pv_count
  csi_pv_count="$(jq -r '.storage.vsphere_csi_pv_count // 0' "$bundle")"
  if [ "$csi_pv_count" -gt 0 ]; then
    bundle_add_warning "$bundle" \
      "Anthos-vmware: ${csi_pv_count} vSphere CSI PV(s) detected — each block volume needs a data-migration plan (DMS for DBs, fresh-load + replay for caches; EBS/EFS targeting depends on access mode)."
  fi

  log_info "Bundle written: $bundle"
  log_info "Hint: validate with scripts/discovery/validate-bundle.sh \"$bundle\""
}

main "$@"
