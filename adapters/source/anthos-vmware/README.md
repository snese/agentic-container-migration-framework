# Source Adapter: Anthos on VMware

**Status:** ✅ v0.8 — stable reference adapter. K8s core + Anthos meta + vSphere CSI PV detection are all collected automatically. govc-based vSphere inventory remains optional (requires read-only vCenter creds).

## Scope

Anthos clusters running on customer-managed VMware vSphere infrastructure (the "Anthos on-prem" / "Anthos clusters on VMware" SKU).

## What this adapter provides

- Discovery prompt: [`prompts/discovery/anthos-vmware.prompt.md`](../../../prompts/discovery/anthos-vmware.prompt.md)
- Self-export script: [`scripts/discovery/anthos-vmware-export.sh`](../../../scripts/discovery/anthos-vmware-export.sh)
- Anthos-specific mapping rules:
  - Config Sync → AWS GitOps (Flux on EKS / Argo CD)
  - Anthos Service Mesh → App Mesh / EKS+Istio / ECS Service Connect
  - Policy Controller → Kyverno (EKS) / AWS Config (ECS)
  - Workload Identity → IRSA (EKS) / Task Role (ECS)
  - vSphere CSI PV → EBS / EFS / FSx (data migration plan required)
- Common gotchas: [`gotchas.md`](gotchas.md)

## Distinguishing signals

| Signal | What we check |
|---|---|
| Anthos meta | `gke-connect-agent` Deployment, `istiod` in istio-system |
| vSphere CSI PVs | PV `.spec.csi.driver == csi.vsphere.vmware.com` count → `.storage.vsphere_csi_pv_count` |
| vSphere infra (optional) | `govc about` + `govc find` if `GOVC_URL` set |
| Config Sync / Service Mesh / Policy Controller | CRDs + ASM `istio-system` deployment |

## Known gotchas (summary — full list in `gotchas.md`)

- vSphere CSI volumes — no direct equivalent; need data migration plan (DMS / fresh load)
- Anthos-injected sidecars (mesh, logging) — strip and replace with AWS-native
- Private container registry (Artifact Registry on-prem mirror) → ECR replication setup needed
- Multi-cluster Service Mesh — usually simplifies on AWS (single VPC per cluster pattern)

## Migration target priority

1. **EKS** — primary. Most Anthos workloads expect K8s-native primitives (CRDs, mesh, GitOps).
2. **ECS Fargate** — selectively, for stateless 12-factor portions.
3. **App Runner** — stateless single-service HTTP only.
