# Source Adapter: Vanilla / Self-Managed Kubernetes

**Status:** ✅ Phase 1 enrichment complete on main's `lib/` architecture.

The vanilla-k8s-export.sh script collects the four signals that change the
most between vanilla clusters and EKS-managed clusters, on top of the shared
K8s core layer:

- **Bootstrap signal** (kubeadm vs cluster-api vs unknown) →
  `clusters[0].bootstrap` and (when known) top-level `vanilla.bootstrapper`
- **CNI plugin** (calico / cilium / flannel / weave / aws-vpc-cni / unknown)
  → `clusters[0].vanilla.cni`
- **Ingress controller** (ingress-nginx / traefik / projectcontour /
  haproxy-ingress / none) → `clusters[0].vanilla.ingress_controller`
- **OS image distribution per node pool** → `clusters[0].vanilla.os_images[]`
- **kubelet version skew across nodes** →
  `clusters[0].vanilla.kubelet_skew_detected`
- **admission webhook count** (validating + mutating) →
  `clusters[0].vanilla.admission_webhooks_*`

If the active context is actually on a managed/branded distro (OpenShift,
Rancher, GKE Enterprise), prefer that adapter — this one is the catch-all
fallback.

## Scope

The catch-all adapter for Kubernetes clusters that don't fit any other source
adapter:

- `kubeadm`-bootstrapped clusters
- `kops`-managed clusters (often on AWS already!)
- `Talos Linux`
- `kubespray` / `cluster-api`
- `EKS-Anywhere` / `OpenShift Local` (CRC) — usually use the more specific
  adapter, but this is the fallback
- DIY / hand-rolled clusters

If you're not sure which adapter to use, start here.

## What this adapter provides

- Self-export script: [`scripts/discovery/vanilla-k8s-export.sh`](../../../scripts/discovery/vanilla-k8s-export.sh)
- Feature mapping: [`mapping.md`](mapping.md)
- Known gotchas: [`gotchas.md`](gotchas.md)
- Fixtures (small) for offline schema validation: [`fixtures/`](fixtures/)

## Distinguishing signals

| Signal | What we check |
|---|---|
| kubeadm bootstrap | `kubeadm-config` ConfigMap in `kube-system` |
| Cluster API (CAPI) | `clusters.cluster.x-k8s.io` CRD |
| CNI | DaemonSet in `kube-system` matching `calico-node`, `cilium`, `weave-net`, `kube-flannel-ds`, `aws-node` |
| Ingress controller | Deployment `ingress-nginx-controller`, `traefik`, `contour`, `haproxy-ingress` |

## Migration target priority

1. **EKS** — primary target for K8s-API-heavy portfolios
2. **ECS** — for stateless 12-factor workloads where dropping K8s API is
   acceptable

See [`mapping.md`](mapping.md) for the feature matrix.
