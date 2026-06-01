# Source Adapter: GKE Enterprise on GCP (formerly Anthos on GCP)

**Status:** ✅ Phase 1 enrichment complete on main's `lib/` architecture.

> **Naming note.** This adapter follows main's `gke-enterprise-*` taxonomy
> (introduced when `anthos-vmware` → `gke-enterprise-vmware` shipped). The
> Google component-level names (Anthos Config Management, Anthos Service Mesh,
> Workload Identity, Config Connector / KCC) persist in Google's docs and
> APIs.

The gke-enterprise-gcp-export.sh script collects GCP-specific signals on top
of the shared K8s core layer:

- **Anthos Service Mesh (managed Istio) detection** →
  `clusters[0].service_mesh.{enabled, type, version}`
- **Workload Identity bindings** — the shared identity collector already
  extracts every ServiceAccount with the
  `iam.gke.io/gcp-service-account` annotation into
  `identity.workload_identity_bindings[]`. This script counts them and
  emits an aggregated warning so engagement teams can size IRSA work.
- **Config Connector (KCC)** presence + managed CRD kinds →
  `clusters[0].anthos.config_connector`
- **gcloud control-plane enrichment** (optional, runs only when `gcloud` is
  installed and `GCLOUD_PROJECT` is set):
  - `clusters[0].location` from `cluster.location`
  - `clusters[0].anthos.release_channel` from `cluster.releaseChannel.channel`
  - `clusters[0].anthos.workload_identity_pool` from
    `cluster.workloadIdentityConfig.workloadPool`

## Scope

GKE clusters running on Google Cloud, including:

- Standard mode + Autopilot
- Anthos Config Management (Config Sync, Policy Controller)
- Anthos Service Mesh (managed Istio)
- Workload Identity (KSA → GCP SA federation)
- Config Connector (KCC)

## What this adapter provides

- Self-export script: [`scripts/discovery/gke-enterprise-gcp-export.sh`](../../../scripts/discovery/gke-enterprise-gcp-export.sh)
- Feature mapping: [`mapping.md`](mapping.md)
- Known gotchas: [`gotchas.md`](gotchas.md)
- Fixtures (small) for offline schema validation: [`fixtures/`](fixtures/)

## Distinguishing signals

| Signal | What we check |
|---|---|
| GKE control plane | `gcloud container clusters describe` (when GCLOUD_PROJECT is set) |
| Workload Identity Pool | `iam.gke.io/gcp-service-account` annotation on ServiceAccounts (via shared identity collector) |
| Config Connector (KCC) | CRDs whose `spec.group` ends in `cnrm.cloud.google.com` |
| Anthos Service Mesh | `istiod` Deployment in `istio-system` (rev label) |
| Config Sync | `configsync.gke.io` CRDs (RootSync, RepoSync) |

## Migration target priority

1. **EKS** — primary target. EKS Auto Mode is the closest equivalent to GKE
   Autopilot. IRSA replaces Workload Identity.
2. **ECS** — for stateless portfolios where dropping K8s API exposure is
   acceptable.

See [`mapping.md`](mapping.md) for the full feature table.
