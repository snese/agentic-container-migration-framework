#!/usr/bin/env bash
# scripts/discovery/vanilla-k8s-export.sh
#
# ACMF Phase 1 self-export — generic / vanilla Kubernetes (kubeadm,
# self-managed, kops, Talos, etc., or anything that doesn't fit the other
# adapters).
#
# This is the catch-all script. It runs the K8s core collector and adds a
# few common signals: kubeadm config, ingress controller detection, CNI
# detection.
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
    log_dim "  kubectl get pods -A -l app.kubernetes.io/name in (ingress-nginx,traefik,contour) -o json"
    log_dim "  kubectl get ds -A -l k8s-app in (calico-node,cilium,weave-net) -o json"
    return 0
  fi

  bundle_skeleton "$PLATFORM" >"$OUTPUT_FILE"
  local bundle="$OUTPUT_FILE"

  log_info "Collecting K8s core layer…"
  core_kube_collect "$bundle" "$PLATFORM" "self-managed"

  # CNI detection (best-effort — looks at well-known DaemonSets in kube-system)
  local cni="unknown"
  if kc -n kube-system get ds calico-node >/dev/null 2>&1; then
    cni="calico"
  elif kc -n kube-system get ds cilium >/dev/null 2>&1; then
    cni="cilium"
  elif kc -n kube-system get ds weave-net >/dev/null 2>&1; then
    cni="weave"
  elif kc -n kube-system get ds kube-flannel-ds >/dev/null 2>&1; then
    cni="flannel"
  fi
  jq --arg cni "$cni" '.networking.cni = $cni' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # Ingress controller detection
  local ingress_ctrl="none"
  for ns_pair in "ingress-nginx:ingress-nginx-controller" "traefik:traefik" "projectcontour:contour"; do
    local ns="${ns_pair%%:*}" name="${ns_pair##*:}"
    if kc -n "$ns" get deploy "$name" >/dev/null 2>&1; then
      ingress_ctrl="$ns"
      break
    fi
  done
  jq --arg ic "$ingress_ctrl" '.networking.ingress_controller = $ic' \
     "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"

  # Cluster bootstrap signal — kubeadm-config means kubeadm-managed.
  if kc -n kube-system get cm kubeadm-config >/dev/null 2>&1; then
    jq '.clusters[0].bootstrap = "kubeadm"' "$bundle" >"${bundle}.tmp" && mv "${bundle}.tmp" "$bundle"
  fi

  log_info "Bundle written: $bundle"
}

main "$@"
