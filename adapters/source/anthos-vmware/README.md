# Source Adapter: Anthos on VMware

**Status:** 🚧 In progress — first reference adapter.

## Scope

Anthos clusters running on customer-managed VMware vSphere infrastructure (the "Anthos on-prem" / "Anthos clusters on VMware" SKU).

## What this adapter provides

- Discovery prompt: [`prompts/discovery/anthos-vmware.prompt.md`](../../../prompts/discovery/anthos-vmware.prompt.md)
- Self-export script: `scripts/discovery/anthos-vmware-export.sh` *(TBD)*
- Anthos-specific mapping rules:
  - Config Sync → AWS GitOps (Flux on EKS)
  - Anthos Service Mesh → App Mesh / EKS+Istio / ECS Service Connect
  - Policy Controller → Kyverno (EKS) / AWS Config (ECS)
  - Workload Identity → IRSA (EKS) / Task Role (ECS)
- Common gotchas (TBD)

## Known gotchas

- vSphere CSI volumes — no direct equivalent; need data migration plan (DMS / fresh load)
- Anthos-injected sidecars (mesh, logging) — strip and replace with AWS-native
- Private container registry (Artifact Registry on-prem mirror) → ECR replication setup needed
- Multi-cluster Service Mesh — usually simplifies on AWS (single VPC per cluster pattern)

## TBD

- Concrete IaC patterns
- Pricing comparison Anthos vs AWS targets
- Live migration via mesh federation (advanced pattern)
