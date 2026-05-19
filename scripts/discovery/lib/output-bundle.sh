#!/usr/bin/env bash
# scripts/discovery/lib/output-bundle.sh
#
# Builds a schema-valid (schemas/discovery-bundle.schema.json) JSON
# discovery bundle from per-section JSON fragments. Source-agnostic.
#
# Required env / variables before calling acmf::bundle::emit:
#   ACMF_SKIPPED_FILE, ACMF_WARN_FILE  (from lib/common.sh)
#
# Usage:
#   acmf::bundle::emit OUTPUT_PATH GENERATED_AT GENERATED_BY \
#     SCOPE_JSON CLUSTERS_JSON WORKLOADS_JSON NETWORKING_JSON \
#     STORAGE_JSON IDENTITY_JSON EXT_JSON CRDS_JSON VMWARE_JSON \
#     UTIL_JSON TRAFFIC_JSON

# shellcheck disable=SC2034

acmf::bundle::emit() {
  local out="$1" gen_at="$2" gen_by="$3"
  local scope="$4" clusters="$5" workloads="$6" networking="$7"
  local storage="$8" identity="$9" ext="${10}" crds="${11}"
  local vmware="${12}" util="${13}" traffic="${14}"

  local skipped warnings
  skipped="$(cat "$ACMF_SKIPPED_FILE")"
  warnings="$(cat "$ACMF_WARN_FILE")"

  jq -n \
    --arg gen_at "$gen_at" \
    --arg gen_by "$gen_by" \
    --argjson scope "$scope" \
    --argjson clusters "$clusters" \
    --argjson workloads "$workloads" \
    --argjson networking "$networking" \
    --argjson storage "$storage" \
    --argjson identity "$identity" \
    --argjson ext "$ext" \
    --argjson crds "$crds" \
    --argjson vmware "$vmware" \
    --argjson util "$util" \
    --argjson traffic "$traffic" \
    --argjson skipped "$skipped" \
    --argjson warnings "$warnings" \
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
    }' > "$out"
}

# A minimal schema-valid empty-ish bundle. Used by the dry-run path of
# stub source adapters (gke, aks, openshift, rancher) so they can emit a
# schema-valid bundle without any real cluster contact while still
# advertising they are stubs via the warnings array.
#
# Usage:
#   acmf::bundle::dry_run_stub OUTPUT_PATH GENERATED_BY SOURCE_LABEL CLUSTER_LABEL PLATFORM_ENUM [warning ...]
acmf::bundle::dry_run_stub() {
  local out="$1" gen_by="$2" source_label="$3" cluster_label="$4" platform="$5"
  shift 5
  local gen_at
  gen_at="$(acmf::common::generated_at)"

  acmf::common::skip "live-cluster-collection" "dry-run mode: no cluster contacted"
  acmf::common::warn "dry-run output — not from a real cluster ($source_label)"
  acmf::common::warn "[STUB] $source_label adapter — schema-valid skeleton; real-cluster collection pending"
  local extra
  for extra in "$@"; do
    acmf::common::warn "$extra"
  done

  local scope clusters
  scope="$(jq -n --arg c "$cluster_label" '{ clusters:[$c], namespaces_included:["app-a"], namespaces_excluded:["kube-system"] }')"
  clusters="$(jq -n --arg c "$cluster_label" --arg src "$source_label" --arg plat "$platform" '
    [{ name:$c, version:"unknown", location:"unknown", platform:$plat,
       control_plane:{ ha_mode:"unknown", node_count:0 },
       node_pools:[],
       anthos_version:null,
       anthos_config_management_version:null,
       service_mesh:{ enabled:false, type:"none", version:null } }]')"

  local empty_networking empty_storage empty_identity empty_util empty_traffic empty_vmware
  empty_networking='{"services":[],"ingress":[],"network_policies":{"count":0,"samples":[]},"service_mesh":{"virtual_services":{"count":0,"samples":[]},"destination_rules":{"count":0,"samples":[]},"authorization_policies":{"count":0,"samples":[]}}}'
  empty_storage='{"storage_classes":[],"persistent_volumes":[],"persistent_volume_claims":[]}'
  empty_identity='{"service_accounts":{"total_count":0,"with_non_default_tokens":[]},"cluster_role_bindings":[],"workload_identity_bindings":[]}'
  empty_util='{"nodes":[],"pods":[],"summary":{"cluster_cpu_utilization_pct":0.0,"cluster_memory_utilization_pct":0.0,"over_provisioning_ratio":0.0,"metrics_source":null}}'
  empty_traffic='{"pairs":[],"summary":{"east_west_bytes_per_sec":0,"north_south_bytes_per_sec":0,"total_service_pairs":0,"telemetry_source":null}}'
  empty_vmware='{"clusters":[],"hosts":[],"datastores":[],"vm_to_node_mapping":[]}'

  acmf::bundle::emit "$out" "$gen_at" "$gen_by" \
    "$scope" "$clusters" "[]" "$empty_networking" \
    "$empty_storage" "$empty_identity" "[]" "[]" \
    "$empty_vmware" "$empty_util" "$empty_traffic"
}
