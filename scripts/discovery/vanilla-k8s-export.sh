#!/usr/bin/env bash
# scripts/discovery/vanilla-k8s-export.sh
#
# ACMF Phase 1 self-export — generic / vanilla Kubernetes (kubeadm,
# self-managed, kops, Talos, kubespray, EKS-Anywhere, etc., or anything that
# doesn't fit the other adapters).
#
# This is the catch-all script. It runs the K8s core collector and then adds
# bootstrapper signals (kubeadm), CNI detection, ingress controller
# detection, OS image distribution, kubelet version skew, and admission
# webhook count — the four signals that change the most between vanilla
# clusters and EKS-managed clusters.
#
# Read-only.
#
# Required tools : kubectl, jq
# Optional tools : (none)
# Permissions    : cluster-reader.
# Estimated time : 1-2 min.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_common.sh"

PLATFORM="vanilla-k8s"

print_usage() {
  cat <<EOF
Vanilla Kubernetes (kubeadm / self-managed / Talos / kops / EKS-anywhere)
discovery export.

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
  - Bootstrap signal (kubeadm vs other)
  - CNI plugin (calico / cilium / flannel / weave / aws-node)
  - Ingress controller (ingress-nginx / traefik / contour)
  - OS image distribution per node pool
  - kubelet version skew across nodes
  - admission webhook counts (validating + mutating)

If the active context is actually on a managed/branded distro (OpenShift,
Rancher, GKE), prefer that adapter — this one is the fallback.
EOF
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
    log_dim "  kubectl -n kube-system get configmap kubeadm-config -o yaml   (if kubeadm)"
    log_dim "  kubectl -n kube-system get ds calico-node|cilium|kube-flannel-ds|weave-net|aws-node"
    log_dim "  kubectl get -n ingress-nginx,traefik,projectcontour deploy -o name"
    log_dim "  kubectl get nodes -o json   (osImage + kubeletVersion distribution)"
    log_dim "  kubectl get validatingwebhookconfiguration,mutatingwebhookconfiguration -o json"
    return 0
  fi

  bundle_skeleton "$PLATFORM" >"$OUTPUT_FILE"
  local bundle="$OUTPUT_FILE"

  log_info "Collecting K8s core layer…"
  core_kube_collect "$bundle" "$PLATFORM" "self-managed"

  # ---- CNI detection ----
  local cni="unknown"
  if kc -n kube-system get ds calico-node >/dev/null 2>&1; then
    cni="calico"
  elif kc -n kube-system get ds cilium >/dev/null 2>&1; then
    cni="cilium"
  elif kc -n kube-system get ds aws-node >/dev/null 2>&1; then
    cni="aws-vpc-cni"
  elif kc -n kube-system get ds kube-flannel-ds >/dev/null 2>&1; then
    cni="flannel"
  elif kc -n kube-system get ds weave-net >/dev/null 2>&1; then
    cni="weave"
  fi

  # ---- Ingress controller detection ----
  local ingress_ctrl="none"
  for ns_pair in \
      "ingress-nginx:ingress-nginx-controller" \
      "traefik:traefik" \
      "projectcontour:contour" \
      "haproxy-ingress:haproxy-ingress"; do
    local ns="${ns_pair%%:*}" name="${ns_pair##*:}"
    if kc -n "$ns" get deploy "$name" >/dev/null 2>&1; then
      ingress_ctrl="$ns"
      break
    fi
  done

  # ---- Cluster bootstrap (kubeadm) ----
  local bootstrap="unknown"
  if kc -n kube-system get cm kubeadm-config >/dev/null 2>&1; then
    bootstrap="kubeadm"
  elif kc get crd clusters.cluster.x-k8s.io >/dev/null 2>&1; then
    bootstrap="cluster-api"
  fi

  # ---- OS image distribution + kubelet skew ----
  local nodes_json os_images kubelet_versions kubelet_skew
  nodes_json="$(kc get nodes -o json 2>/dev/null || echo '{"items":[]}')"
  os_images="$(printf '%s' "$nodes_json" | jq '
    [(.items // [])[] | .status.nodeInfo.osImage // "unknown"]
    | group_by(.) | map({os_image: .[0], count: length})')"
  kubelet_versions="$(printf '%s' "$nodes_json" | jq '
    [(.items // [])[] | .status.nodeInfo.kubeletVersion // "unknown"] | unique')"
  if [ "$(printf '%s' "$kubelet_versions" | jq 'length')" -gt 1 ]; then
    kubelet_skew="true"
  else
    kubelet_skew="false"
  fi

  # ---- Admission webhooks ----
  local vwc_json mwc_json vwc_total mwc_total
  vwc_json="$(kc get validatingwebhookconfiguration -o json 2>/dev/null || echo '{"items":[]}')"
  mwc_json="$(kc get mutatingwebhookconfiguration -o json 2>/dev/null  || echo '{"items":[]}')"
  vwc_total="$(printf '%s' "$vwc_json" | jq '(.items // []) | length')"
  mwc_total="$(printf '%s' "$mwc_json" | jq '(.items // []) | length')"

  # Assemble vanilla cluster block
  jq \
    --arg cni "$cni" \
    --arg ic "$ingress_ctrl" \
    --arg bs "$bootstrap" \
    --argjson os "$os_images" \
    --argjson kv "$kubelet_versions" \
    --argjson skew "$kubelet_skew" \
    --argjson vwc "$vwc_total" \
    --argjson mwc "$mwc_total" \
    '
    .clusters[0] = (.clusters[0] + (if $bs != "unknown" then {bootstrap: $bs} else {} end))
    | .clusters[0].vanilla = ((.clusters[0].vanilla // {}) + {
        cni: $cni,
        ingress_controller: $ic,
        os_images: $os,
        kubelet_versions: $kv,
        kubelet_skew_detected: $skew,
        admission_webhooks_total: ($vwc + $mwc),
        admission_webhooks_validating: $vwc,
        admission_webhooks_mutating: $mwc
      })
    | .networking = ((.networking // {}) + {
        cni: $cni,
        ingress_controller: $ic
      })
    | .vanilla = ((.vanilla // {}) + (if $bs != "unknown" then {bootstrapper: $bs} else {} end))
    ' \
    "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # ---- Precise warnings (only when actionable) ----
  if [ "$kubelet_skew" = "true" ]; then
    bundle_add_warning "$bundle" \
      "Vanilla-k8s: kubelet version skew detected across nodes ($(printf '%s' "$kubelet_versions" | jq -c .)) — must be reconciled before EKS migration; managed node groups expect uniform versions."
  fi
  local custom_webhooks
  custom_webhooks=$((vwc_total + mwc_total))
  if [ "$custom_webhooks" -gt 0 ]; then
    bundle_add_warning "$bundle" \
      "Vanilla-k8s: ${custom_webhooks} admission webhook(s) (${vwc_total} validating + ${mwc_total} mutating) — each must be redeployed on EKS; ensure failurePolicy/timeout values match EKS API server tolerances."
  fi
  if [ "$cni" = "unknown" ]; then
    bundle_add_warning "$bundle" \
      "Vanilla-k8s: CNI plugin not auto-detected — verify manually; EKS targets are AWS VPC CNI, Calico (Tigera), or Cilium."
  fi

  log_info "Bundle written: $bundle"
}

main "$@"
