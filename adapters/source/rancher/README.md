# Source Adapter: Rancher (RKE / RKE2 / K3s / imported)

**Status:** ✅ v0.8 — discovery complete. Distribution detection (k3s/rke2/rke/rancher-managed/imported), server version, and management vs downstream cluster classification are auto-collected. Fleet inventory + Longhorn probe still require running against the management cluster context for the full picture (the script emits a warning when run downstream-only).

## Scope

Kubernetes clusters managed by Rancher 2.x. Five common shapes:

1. **RKE** (legacy, Docker-based) — being EOL'd
2. **RKE2** — modern, systemd-based, hardened-by-default
3. **K3s** — lightweight (edge / dev clusters)
4. **Imported** — Rancher manages a third-party cluster (EKS, GKE, etc.) for visibility
5. **Hosted** (RKE2 in vSphere / Harvester / etc.)

This adapter discovers from the **downstream** cluster's perspective. Some Rancher metadata
(Fleet bundles deployed by the management cluster, cluster templates) lives only on the
**management** cluster — re-run with the management cluster context for that.

## What this adapter provides

- Discovery prompt: [`prompts/discovery/rancher.prompt.md`](../../../prompts/discovery/rancher.prompt.md)
- Self-export script: [`scripts/discovery/rancher-export.sh`](../../../scripts/discovery/rancher-export.sh)
- Feature mapping: [`mapping.md`](mapping.md)
- Known gotchas: [`gotchas.md`](gotchas.md)
- Fixtures (small + realistic) for offline testing

## Distinguishing signals

| Signal | What we check |
|---|---|
| Distribution | Node `kubeletVersion` contains `k3s` / `rke2` |
| Rancher-managed | `cattle-system` namespace present |
| Fleet (GitOps) | `clusters.fleet.cattle.io` CRD |
| Longhorn (CSI) | `longhorn-system` namespace + Longhorn CRDs |
| Cattle agent | `cattle-cluster-agent` Deployment in `cattle-system` |

## Migration target priority

1. **EKS** — primary target. RKE2 + Longhorn + Fleet → EKS + EBS/EFS + Flux is the most common path.
2. **ECS** — viable for stateless portions; Fleet GitOps doesn't carry over directly.
3. **App Runner** — only relevant for tiny single-service portfolios.

See [`mapping.md`](mapping.md) for the feature matrix and [`gotchas.md`](gotchas.md) for surprises.
