# Source Adapter: Vanilla / Self-Managed Kubernetes

**Status:** ✅ v0.8 — discovery complete. CNI plugin, ingress controller, OS image distribution, kubelet version skew, and admission webhook counts are now auto-collected. Bootstrapper-specific quirks (kubeadm vs kops vs Talos vs kubespray) are surfaced via warnings rather than custom blocks.

## Scope

The catch-all adapter for Kubernetes clusters that don't fit any other source adapter:

- `kubeadm`-bootstrapped clusters
- `kops`-managed clusters (often on AWS already!)
- `Talos Linux`
- `kubespray` / `cluster-api`
- `EKS-Anywhere` / `OpenShift Local` (CRC) — usually use the more specific adapter, but this is the fallback
- DIY / hand-rolled clusters

If you're not sure which adapter to use, start here.

## What this adapter provides

- Discovery prompt: [`prompts/discovery/vanilla-k8s.prompt.md`](../../../prompts/discovery/vanilla-k8s.prompt.md)
- Self-export script: [`scripts/discovery/vanilla-k8s-export.sh`](../../../scripts/discovery/vanilla-k8s-export.sh)
- Feature mapping: [`mapping.md`](mapping.md)
- Known gotchas: [`gotchas.md`](gotchas.md)
- Fixtures (small + realistic) for offline testing

## Distinguishing signals

| Signal | What we check |
|---|---|
| kubeadm bootstrap | `kubeadm-config` ConfigMap in `kube-system` |
| CNI | DaemonSet in `kube-system` matching `calico-node`, `cilium`, `weave-net`, `kube-flannel-ds` |
| Ingress controller | Deployment `ingress-nginx-controller`, `traefik`, `contour`, `haproxy` |
| Cluster API (CAPI) | `clusters.cluster.x-k8s.io` CRD |

## Migration target priority

1. **EKS** — primary target for K8s-API-heavy portfolios
2. **ECS Fargate** — for stateless 12-factor workloads where dropping K8s API is acceptable
3. **App Runner** — single-service HTTP apps

See [`mapping.md`](mapping.md) for the feature matrix.
