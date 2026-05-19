# Source Adapter: Anthos on VMware

Status: 🚧 In progress — first reference adapter.

## Scope

Anthos clusters running on customer-managed VMware vSphere infrastructure (the "Anthos on-prem" / "Anthos clusters on VMware" SKU).

## What this adapter provides

- Discovery prompt: [prompts/discovery/anthos-vmware.prompt.md](../../prompts/discovery/anthos-vmware.prompt.md)
- Self-export script: `scripts/discovery/anthos-vmware-export.sh`
- Anthos-specific mapping rules:
  - Config Sync → ArgoCD on EKS (primary) / Flux CD (alternative)
  - Anthos Service Mesh → Istio on EKS (full mesh) / ECS Service Connect (lightweight) / Amazon VPC Lattice (service-to-service)
  - Policy Controller → OPA Gatekeeper (EKS, direct ConstraintTemplate migration) / Kyverno (EKS, simpler policy syntax) / AWS Config + SCPs (ECS)
  - Workload Identity → IRSA / EKS Pod Identity (EKS) / Task Role (ECS)
- Common gotchas (see below)

> **Policy Controller migration guidance:**
>
> | Customer situation | Recommended target | Rationale |
> |---|---|---|
> | Many custom ConstraintTemplates | OPA Gatekeeper | Direct Rego policy migration, minimal rewrite |
> | Simple/bundled policies only | Kyverno | Simpler YAML-native syntax, easier to maintain |
> | ECS target (no K8s) | AWS Config + SCPs | Cloud-native compliance, no cluster add-on needed |
> | Mixed EKS + ECS fleet | Kyverno (EKS) + AWS Config (ECS) | Consistent intent, platform-native enforcement |

> **Why ArgoCD as default over Flux?**
> ArgoCD has higher market adoption, more mature multi-cluster support (ApplicationSets), and built-in UI for migration validation.

> ⚠️ **AWS App Mesh is deprecated** (EOL announced 2024, no new features). Do not recommend for new migrations.

## Known gotchas

- vSphere CSI volumes — no direct equivalent; need data migration plan (DMS / fresh load)
- Anthos-injected sidecars (mesh, logging) — strip and replace with AWS-native
- Private container registry (Artifact Registry on-prem mirror) → ECR replication setup needed
- Multi-cluster Service Mesh — usually simplifies on AWS (single VPC per cluster pattern)
- Policy Controller ConstraintTemplates using `inventory` data — Gatekeeper supports this but requires audit controller setup on EKS

## TBD

- Concrete IaC patterns
- Pricing comparison Anthos vs AWS targets
- Live migration via mesh federation (advanced pattern)
- Policy migration tooling (automated ConstraintTemplate validation on target)
