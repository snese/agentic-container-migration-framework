# Source Adapter: GKE Enterprise on VMware (formerly Anthos)

Status: ✅ v0.3 — first reference adapter.

> **Naming.** Google rebranded "Anthos on VMware" → **GKE Enterprise on VMware** and "Anthos on Bare Metal" → **GKE Enterprise on Bare Metal** (pure-software platform, customer owns hardware). **GDC** (Google Distributed Cloud) is a different product (Google-supplied hardware, air-gapped/sovereignty). Some technical components (Anthos Config Sync, Anthos Service Mesh, Anthos Policy Controller) retain the legacy `Anthos` prefix in Google docs and are kept as-is in this adapter. The directory name `gke-enterprise-vmware/` reflects the current product naming.

## Artifacts in this adapter

- [`manifest-transforms.yaml`](./manifest-transforms.yaml) — machine-readable rule set (annotations, identity, ingress, storage, mesh, registry).
- Self-export script: [`../../../scripts/discovery/gke-enterprise-vmware-export.sh`](../../../scripts/discovery/gke-enterprise-vmware-export.sh) — bundles output into the v0.2.0 [discovery schema](../../../schemas/discovery-bundle.schema.json).
- Sample manifests for fixture testing: [`../../../examples/gke-enterprise-manifests/`](../../../examples/gke-enterprise-manifests/).
- End-to-end walkthrough: [`../../../examples/gke-enterprise-vmware-to-eks/`](../../../examples/gke-enterprise-vmware-to-eks/).

## Scope

GKE Enterprise on VMware clusters (formerly "Anthos on-prem" / "Anthos clusters on VMware") running on customer-managed VMware vSphere infrastructure.

## What this adapter provides

- Discovery prompt: [prompts/discovery/gke-enterprise-vmware.prompt.md](../../../prompts/discovery/gke-enterprise-vmware.prompt.md)
- Self-export script: `scripts/discovery/gke-enterprise-vmware-export.sh`
- GKE Enterprise-specific mapping rules:
  - Anthos Config Sync → ArgoCD on EKS (primary) / Flux CD (alternative)
  - Anthos Service Mesh → Istio on EKS (full mesh) / ECS Service Connect (lightweight) / Amazon VPC Lattice (service-to-service)
  - Anthos Policy Controller → OPA Gatekeeper (EKS, direct ConstraintTemplate migration) / Kyverno (EKS, simpler policy syntax) / AWS Config + SCPs (ECS)
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


## Known gotchas

- vSphere CSI volumes — no direct equivalent; need data migration plan (DMS / fresh load)
- GKE Enterprise-injected sidecars (mesh, logging) — strip and replace with AWS-native
- Private container registry (Artifact Registry on-prem mirror) → ECR replication setup needed
- Multi-cluster Service Mesh — usually simplifies on AWS (single VPC per cluster pattern)
- Policy Controller ConstraintTemplates using `inventory` data — Gatekeeper supports this but requires audit controller setup on EKS

## Planned additions

All items previously listed here are tracked in [`ROADMAP.md`](../../../ROADMAP.md) — concrete IaC patterns, GKE Enterprise-vs-AWS pricing comparison, mesh-federation live-migration pattern, and Anthos Policy Controller migration tooling.
