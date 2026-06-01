# Source Adapter: Rancher (RKE / RKE2 / K3s / imported)

**Status:** ✅ Phase 1 enrichment complete on main's `lib/` architecture.

The rancher-export.sh script collects Rancher-specific signals on top of the
shared K8s core layer:

- **Distribution detection** (k3s / rke2 / rke / rancher-managed /
  vanilla-or-imported) and server version → `clusters[0].rancher.{distribution, server_version}`
- **Management vs downstream cluster classification** →
  `clusters[0].rancher.is_management_cluster` and (when management)
  top-level `rancher.{is_management_cluster, downstream_clusters_total}`
- **Fleet inventory** (clusters / bundles) when CRDs present →
  `clusters[0].rancher.{fleet_clusters_total, fleet_bundles_total}`
- **Longhorn presence + volume count** → surfaced via `warnings[]`

If Fleet CRDs are not present (downstream cluster without Fleet agent, or
non-Rancher cluster), the script logs a `skipped[]` entry and continues.

## Scope

Kubernetes clusters managed by Rancher 2.x. Five common shapes:

1. **RKE** (legacy, Docker-based) — being EOL'd
2. **RKE2** — modern, systemd-based, hardened-by-default
3. **K3s** — lightweight (edge / dev clusters)
4. **Imported** — Rancher manages a third-party cluster (EKS, GKE, etc.) for
   visibility
5. **Hosted** (RKE2 in vSphere / Harvester / etc.)

This adapter discovers from the **downstream** cluster's perspective. Some
Rancher metadata (Fleet bundles deployed by the management cluster, cluster
templates) lives only on the **management** cluster — re-run with the
management cluster context for that.

## What this adapter provides

- Self-export script: [`scripts/discovery/rancher-export.sh`](../../../scripts/discovery/rancher-export.sh)
- Feature mapping: [`mapping.md`](mapping.md)
- Known gotchas: [`gotchas.md`](gotchas.md)
- Fixtures (small) for offline schema validation: [`fixtures/`](fixtures/)

## Distinguishing signals

| Signal | What we check |
|---|---|
| Distribution | Node `kubeletVersion` contains `k3s` / `rke2` |
| Rancher-managed | `cattle-system` namespace present |
| Management cluster | `clusters.provisioning.cattle.io` CRD + `cattle-system/rancher` Deployment |
| Fleet (GitOps) | `clusters.fleet.cattle.io` CRD |
| Longhorn (CSI) | `longhorn-system` namespace present |

## Migration target priority

1. **EKS** — primary target. RKE2 + Longhorn + Fleet → EKS + EBS/EFS + Flux is
   the most common path.
2. **ECS** — viable for stateless portions; Fleet GitOps doesn't carry over
   directly.

See [`mapping.md`](mapping.md) for the feature matrix and [`gotchas.md`](gotchas.md)
for surprises.
