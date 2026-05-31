#!/usr/bin/env bash
# scripts/discovery/anthos-baremetal-export.sh
#
# ACMF Phase 1 self-export — Anthos clusters on bare-metal.
#
# Reads K8s + Anthos-on-bare-metal control-plane metadata, then mines the
# workload list for hardware-bound signals (hostNetwork, privileged, GPU,
# SR-IOV, Multus annotations, hostPath, hostPID, hostIPC, RDMA, hugepages).
# Each workload that hits one or more signal is added to
# .workloads_hardware_bound[] for SME triage.
#
# No hypervisor / vCenter layer (bare-metal). No gcloud probe of the
# underlying hardware — bare-metal customers may be air-gapped. BMC-level
# inventory (Redfish, IPMI) remains an SME exercise.
#
# Read-only.
#
# Required tools : kubectl, jq
# Optional tools : (none)
# Permissions    : cluster-reader on the user cluster.
# Estimated time : 1-2 min.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_common.sh"

PLATFORM="anthos-baremetal"

print_usage() {
  cat <<EOF
Anthos-on-bare-metal discovery export.

Usage: $(basename "$0") [options]

Options:
  --output FILE
  --include-namespaces CSV
  --exclude-namespaces CSV
  --include-system
  --kubeconfig PATH
  --context NAME
  --dry-run
  -h, --help

What this collects (in addition to the K8s core layer):
  - Anthos bare-metal CRDs (cluster.baremetal.cluster.gke.io) if present
  - workloads_hardware_bound[]: every workload using hostNetwork, privileged,
    GPU, SR-IOV, Multus annotations, hostPath, hostPID, hostIPC, RDMA, or
    hugepages — each requires SME review for AWS placement.

Out of scope (true SME items):
  - BMC/Redfish/IPMI hardware inventory
  - Driver-version compatibility (e.g. NVIDIA driver vs CUDA vs EKS AMI)
EOF
}

# ---------------------------------------------------------------------------
# Mine workloads JSON for hardware-bound signals.
#
# Input (stdin): kubectl get deploy,sts,ds,job,cronjob -A -o json
# Output (stdout): JSON array of {namespace, name, kind, reasons, detail}
#
# Each pod-template spec is checked for:
#   - hostNetwork=true / hostPID=true / hostIPC=true
#   - any container.securityContext.privileged=true
#   - any container.resources.limits keyed by nvidia.com/gpu
#   - any container.resources.limits keyed by *sriov*
#   - any container.resources.limits keyed by hugepages-*
#   - any container.resources.limits keyed by rdma/* or *fpga*
#   - any volume of type hostPath
#   - metadata.annotations["k8s.v1.cni.cncf.io/networks"] (Multus)
# ---------------------------------------------------------------------------
mine_hardware_bound() {
  jq '
    def pod_spec(item):
      (item.spec.template.spec
        // item.spec.jobTemplate.spec.template.spec
        // null);

    def pod_meta(item):
      (item.spec.template.metadata
        // item.spec.jobTemplate.spec.template.metadata
        // {});

    def detect(item):
      pod_spec(item) as $ps
      | pod_meta(item) as $pm
      | if $ps == null then [] else
          [
            (if ($ps.hostNetwork // false) then "hostNetwork" else empty end),
            (if ($ps.hostPID // false) then "hostPID" else empty end),
            (if ($ps.hostIPC // false) then "hostIPC" else empty end),
            (if (($ps.containers // []) | any(.securityContext.privileged == true))
               or (($ps.initContainers // []) | any(.securityContext.privileged == true))
             then "privileged" else empty end),
            (if (($ps.containers // []) | any(
                  ((.resources.limits // {}) | keys) | any(. == "nvidia.com/gpu" or test("amd.com/gpu"; "i") or test("gpu"; "i") )
                )) then "gpu" else empty end),
            (if (($ps.containers // []) | any(
                  ((.resources.limits // {}) | keys) | any(test("sriov"; "i"))
                )) then "sriov" else empty end),
            (if ($pm.annotations // {}) | has("k8s.v1.cni.cncf.io/networks")
               then "multus_annotation" else empty end),
            (if (($ps.volumes // []) | any(.hostPath != null))
               then "hostPath" else empty end),
            (if (($ps.containers // []) | any(
                  ((.resources.limits // {}) | keys) | any(startswith("hugepages-"))
                )) then "huge_pages" else empty end),
            (if (($ps.containers // []) | any(
                  ((.resources.limits // {}) | keys) | any(startswith("rdma/"))
                )) then "rdma" else empty end),
            (if (($ps.containers // []) | any(
                  ((.resources.limits // {}) | keys) | any(test("fpga"; "i"))
                )) then "fpga" else empty end)
          ]
        end;

    [(.items // [])[]
      | . as $w
      | detect($w) as $reasons
      | select(($reasons | length) > 0)
      | {
          namespace: $w.metadata.namespace,
          name: $w.metadata.name,
          kind: ($w.kind // "Other"),
          reasons: ($reasons | unique),
          detail: (
            "Detected: " + ($reasons | unique | join(", "))
          )
        }
    ]
  '
}

main() {
  parse_common_args "$@"

  require_cmd kubectl
  require_cmd jq

  if [ "$DRY_RUN" = "1" ]; then
    log_info "Dry-run: emitting schema-valid stub to ${OUTPUT_FILE}"
    emit_bundle_stub "$PLATFORM" "$OUTPUT_FILE"
    log_info "Planned commands:"
    core_dry_run_hint
    log_dim "  kubectl get cluster.baremetal.cluster.gke.io -A -o json   (if CRD installed)"
    log_dim "  (mine workloads JSON for hostNetwork/privileged/GPU/SR-IOV/Multus/hostPath signals)"
    return 0
  fi

  bundle_skeleton "$PLATFORM" >"$OUTPUT_FILE"
  local bundle="$OUTPUT_FILE"

  log_info "Collecting K8s core layer…"
  core_kube_collect "$bundle" "$PLATFORM" "on-prem-baremetal"

  # Anthos-on-bare-metal CRDs (best-effort).
  log_info "Probing bare-metal Anthos CRDs…"
  if kc get crd cluster.baremetal.cluster.gke.io >/dev/null 2>&1; then
    local bm_clusters
    bm_clusters="$(kc get cluster.baremetal.cluster.gke.io -A -o json 2>/dev/null || echo '{"items":[]}')"
    jq --argjson bm "$bm_clusters" \
       '.clusters[0].anthos = ((.clusters[0].anthos // {}) + {
          baremetal_cluster_count: (($bm.items // []) | length),
          baremetal_cluster_names: [(($bm.items // [])[].metadata.name)]
        })' \
       "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
  else
    bundle_add_skipped "$bundle" "kubectl get cluster.baremetal.cluster.gke.io" \
      "Anthos bare-metal CRDs not present (likely a user cluster, not admin)"
  fi

  # ---- Hardware-bound workload mining ----
  log_info "Mining workloads for hardware-bound signals…"
  local hw_array hw_count
  hw_array="$(printf '%s' "$CORE_WORKLOADS_RAW" | mine_hardware_bound)"
  hw_count="$(printf '%s' "$hw_array" | jq 'length')"
  jq --argjson hw "$hw_array" \
     '.workloads_hardware_bound = $hw' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # Precise warning (only emit if any hardware-bound workloads were found)
  if [ "$hw_count" -gt 0 ]; then
    bundle_add_warning "$bundle" \
      "Anthos-baremetal: ${hw_count} hardware-bound workload(s) detected (hostNetwork/privileged/GPU/SR-IOV/Multus/hostPath/etc.) — each needs SME triage for AWS placement (EC2 *.metal vs ENA/EFA vs redesign). See .workloads_hardware_bound[]."
  fi
  bundle_add_warning "$bundle" \
    "Anthos-baremetal: BMC/Redfish/IPMI hardware inventory + driver compatibility matrices remain SME items — bring rack/chassis docs to architecture review."

  log_info "Bundle written: $bundle"
}

main "$@"
