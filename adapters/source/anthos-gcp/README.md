# Source Adapter: Anthos on GCP (GKE)

**Status:** 🚧 v0.7-rc — basic mapping in place; SME review needed for Workload Identity Federation patterns and Anthos-specific KCC (Config Connector) coverage.

## Scope

GKE clusters running on Google Cloud, including:
- Standard mode + Autopilot
- Anthos Config Management (Config Sync, Policy Controller)
- Anthos Service Mesh (managed Istio)
- Workload Identity (KSA → GCP SA federation)

## What this adapter provides

- Discovery prompt: [`prompts/discovery/anthos-gcp.prompt.md`](../../../prompts/discovery/anthos-gcp.prompt.md)
- Self-export script: [`scripts/discovery/anthos-gcp-export.sh`](../../../scripts/discovery/anthos-gcp-export.sh)
- Feature mapping: [`mapping.md`](mapping.md)
- Known gotchas: [`gotchas.md`](gotchas.md)
- Fixtures (small + realistic) for offline testing

## Distinguishing signals

| Signal | What we check |
|---|---|
| GKE control plane | `gcloud container clusters describe` |
| Workload Identity Pool | `iam.gke.io/gcp-service-account` annotation on ServiceAccounts |
| Config Sync | `configsync.gke.io` CRDs (RootSync, RepoSync) |
| Service Mesh | `istiod` deployment in `istio-system`; managed via `meshconfig.googleapis.com` |
| Release channel | `cluster.releaseChannel.channel` from gcloud describe |

## Migration target priority

1. **EKS** — primary target. EKS Auto Mode is the closest equivalent to GKE Autopilot. IRSA replaces Workload Identity.
2. **ECS Fargate** — for stateless portfolios where dropping K8s API exposure is acceptable.
3. **App Runner** — single-service HTTP apps only.

See [`mapping.md`](mapping.md) for the full feature table.
