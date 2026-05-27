#!/usr/bin/env bash
# scripts/discovery/openshift-export.sh
#
# ACMF Phase 1 self-export — Red Hat OpenShift Container Platform (OCP) 4.x.
#
# Uses kubectl for the K8s core, then layers on OpenShift-specific resources
# via `oc` if available: Routes, ImageStreams, BuildConfigs, OperatorGroups,
# Subscriptions, MachineConfigPools.
#
# Read-only.
#
# Required tools : kubectl, jq
# Optional tools : oc      (OpenShift CLI — strongly recommended)
# Permissions    : cluster-reader (or self-provisioner with read-only Roles).
# Estimated time : 2-4 min for clusters with many Operators / ImageStreams.
#
# 🚧 v0.7-rc — OperatorHub mapping to AWS-native equivalents is partial:
#   we list installed Operators but do not yet rate "easy / hard / blocker".
#   See adapters/source/openshift/gotchas.md for the running gotcha list.

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

🚧 v0.7-rc — Operator-to-AWS mapping is stubbed; needs SME review.
EOF
}

main() {
  parse_common_args "$@"

  require_cmd kubectl
  require_cmd jq

  if ! have_cmd oc; then
    log_warn "oc not found — Routes / ImageStreams / BuildConfigs / Subscriptions will be skipped."
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log_info "Dry-run: emitting schema-valid stub to ${OUTPUT_FILE}"
    emit_bundle_stub "$PLATFORM" "$OUTPUT_FILE"
    log_info "Planned commands:"
    core_dry_run_hint
    log_dim "  oc get route -A -o json"
    log_dim "  oc get imagestream -A -o json"
    log_dim "  oc get buildconfig -A -o json"
    log_dim "  oc get subscription,operatorgroup -A -o json"
    log_dim "  oc get clusterversion version -o json"
    log_dim "  oc get machineconfigpool -o json"
    return 0
  fi

  bundle_skeleton "$PLATFORM" >"$OUTPUT_FILE"
  local bundle="$OUTPUT_FILE"

  log_info "Collecting K8s core layer…"
  core_kube_collect "$bundle" "$PLATFORM" "openshift"

  if have_cmd oc; then
    log_info "Collecting OpenShift-specific resources via oc…"

    # ClusterVersion → channel + currentVersion
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

    # Routes (OpenShift Ingress equivalent)
    local routes_json
    routes_json="$(oc get route -A -o json 2>/dev/null || echo '{"items":[]}')"
    jq --argjson r "$routes_json" \
       '.networking.openshift_routes_total = (($r.items // []) | length)' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

    # ImageStreams + BuildConfigs (S2I signal — these need ECR + CodeBuild migration)
    local is_json bc_json
    is_json="$(oc get imagestream -A -o json 2>/dev/null  || echo '{"items":[]}')"
    bc_json="$(oc get buildconfig -A -o json 2>/dev/null  || echo '{"items":[]}')"
    jq --argjson is "$is_json" --argjson bc "$bc_json" \
       '. + {
          openshift: {
            image_streams_total: (($is.items // []) | length),
            build_configs_total: (($bc.items // []) | length)
          }
        }' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

    # OLM Subscriptions = installed Operators
    local sub_json
    sub_json="$(oc get subscription -A -o json 2>/dev/null || echo '{"items":[]}')"
    local subs_array
    subs_array="$(jq -n --argjson s "$sub_json" \
      '[($s.items // [])[] | {
         namespace: .metadata.namespace,
         name: .metadata.name,
         package: .spec.name,
         channel: .spec.channel,
         source: .spec.source
       }]')"
    jq --argjson subs "$subs_array" \
       '.openshift.subscriptions = $subs' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

    # MachineConfigPool (cluster-as-code signal)
    local mcp_json
    mcp_json="$(oc get machineconfigpool -o json 2>/dev/null || echo '{"items":[]}')"
    jq --argjson m "$mcp_json" \
       '.openshift.machine_config_pools = [(($m.items // [])[] | { name: .metadata.name, ready: .status.readyMachineCount, total: .status.machineCount })]' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
  else
    bundle_add_skipped "$bundle" "oc get route,imagestream,buildconfig,subscription" \
      "oc CLI not installed; OpenShift-specific objects not collected"
  fi

  bundle_add_warning "$bundle" \
    "🚧 v0.7-rc: Operator-to-AWS mapping is partial; SME review required for stateful operators (Strimzi, Postgres-operator, etc.)."

  log_info "Bundle written: $bundle"
}

main "$@"
