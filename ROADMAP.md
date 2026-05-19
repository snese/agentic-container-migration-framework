# ACMF Roadmap

Single source of truth for planned-but-not-yet-done work. When you are tempted to write `TBD` in any other file, add the item here instead and link to it.

**Status legend:** 🔜 planned · 🚧 in progress · ✅ shipped · ⛔ deprecated

## Phase 1 — Assess

| Item | Status | Notes / Issue |
|---|---|---|
| GKE Enterprise on VMware discovery prompt + JSON Schema | 🚧 | First reference adapter (formerly Anthos on VMware) |
| Self-export bash script (`scripts/discovery/gke-enterprise-vmware-export.sh`) | ✅ | Option 2 of the discovery menu |
| OpenShift discovery prompt | 🔜 | After GKE Enterprise reference is stable |
| GKE discovery prompt | 🔜 | Standard GKE (cloud-native) + GKE Enterprise fleet |
| AKS discovery prompt | 🔜 | Azure AD RBAC, Azure CNI, Azure Disk/File CSI |
| Discovery-bundle JSON Schema (`schemas/discovery-bundle.schema.json`) | ✅ | v0.2.0 shipped |

## Phase 2 — Mobilize

| Item | Status | Notes / Issue |
|---|---|---|
| Workload assessment prompt + per-workload report template | 🔜 | |
| Wave-grouping heuristics doc | 🔜 | |
| Reference landing-zone Terraform module | 🔜 | EKS Auto Mode + ECS Fargate baseline |
| Reference landing-zone CDK alternative | 🔜 | After Terraform reference |

## Phase 3 — Migrate

| Item | Status | Notes / Issue |
|---|---|---|
| Cutover playbook templates (blue/green, canary, dual-running) | 🔜 | |
| Mesh federation pattern (live migration, advanced) | 🔜 | Anthos Service Mesh ↔ Istio on EKS |
| Policy Controller → OPA Gatekeeper / Kyverno migration tooling | 🔜 | Automated ConstraintTemplate validation |
| Private registry replication recipe (Artifact Registry mirror → ECR) | 🔜 | |

## Phase 4 — Modernize

### Wave A — shipped (v0.5)

| Item | Status | Notes / Issue |
|---|---|---|
| IRSA → EKS Pod Identity migration playbook | ✅ | `docs/playbooks/irsa-to-pod-identity.md` |
| Karpenter + right-sizing playbook | ✅ | `docs/playbooks/karpenter-rightsizing.md` |
| Observability uplift playbook (GCP/Anthos → AWS) | ✅ | `docs/playbooks/observability-uplift.md` |
| Right-sizing analysis prompt (Compute Optimizer + Prometheus) | ✅ | `prompts/modernize/right-sizing-analysis.prompt.md` |

### Wave B — planned

| Item | Status | Notes / Issue |
|---|---|---|
| GitOps maturity scorecard prompt | 🔜 | Prompt scaffolded at `prompts/modernize/gitops-maturity-scorecard.prompt.md`; companion playbook + reference scoring fixtures pending |
| Service Mesh simplification playbook | 🔜 | Istio → VPC Lattice / Service Connect simplification paths; App Mesh is deprecated (see ECS-vs-EKS decision) |
| Security hardening playbook | 🔜 | NetworkPolicies, image scanning, admission policies, IMDSv2 enforcement |
| Decision doc: EKS Auto Mode vs ECS Fargate cost-model worksheet | 🔜 | Real workload baselines required |
| Decision doc: when to refactor to Lambda / serverless data pipeline | 🔜 | Deferred Refactor (7 Rs) decision template |
| Templates: optimization-backlog.md, runbook, on-call rotation | 🔜 | Phase 4 outputs |
| Optional Strands-based ongoing optimization agent recipe | 🔜 | Phase 4 only; opt-in (see CONSTITUTION §1) |

## Phase 5 — Document

| Item | Status | Notes / Issue |
|---|---|---|
| First case study (GKE Enterprise on VMware → EKS) | 🔜 | Pending real engagement |
| Case-study anonymization checklist | 🔜 | |

## Adapters

### Source adapters

| Item | Status | Notes |
|---|---|---|
| Source: GKE Enterprise on VMware (formerly Anthos) | 🚧 | First reference; `adapters/source/gke-enterprise-vmware/` |
| Source: GKE Enterprise on Bare Metal (formerly Anthos) | ✅ | Shares VMware adapter with `--platform=bare-metal` flag (skips vSphere discovery) |
| Source: GKE (cloud-native, on GCP) | 🔜 | Standard GKE + GKE Enterprise fleet; `adapters/source/gke/` |
| Source: AKS (Azure) | 🔜 | Azure AD, Azure CNI, Azure Disk/File CSI; `adapters/source/aks/` |
| Source: OpenShift | 🔜 | |
| Source: Rancher / vanilla K8s | 🔜 | |

### Target adapters

| Item | Status | Notes |
|---|---|---|
| Target: EKS — reference Terraform module | 🔜 | |
| Target: EKS — reference Helm umbrella chart | 🔜 | |
| Target: ECS Fargate — reference Terraform module | 🔜 | |
| Target: ECS Fargate — Service Connect migration recipe from Istio | 🔜 | |
| ~~Target: App Runner~~ | ⛔ | Maintenance mode 2026-04-30; no new customers. Use ECS Fargate instead. [#37](https://github.com/snese/agentic-container-migration-framework/issues/37) |

## Customer-facing

| Item | Status | Notes |
|---|---|---|
| 1-pager, pitch guide, FAQ | ✅ | `docs/customer-facing/` |
| AWS Transform vs ACMF positioning | ✅ | `docs/decisions/aws-transform-vs-acmf.md` |
| GKE Enterprise vs AWS pricing comparison sheet | 🔜 | |

## Decisions / open questions

| Item | Status | Notes |
|---|---|---|
| Concrete cost models per ECS-vs-EKS pattern | 🔜 | Need real customer baselines |
| EKS Auto Mode vs ECS Fargate cost comparison for equivalent workloads | 🔜 | |
| Multi-region story per target (EKS / ECS) | 🔜 | |
| Live-migration via mesh federation (GKE Enterprise ↔ EKS) | 🔜 | Advanced pattern |

## Governance

| Item | Status | Notes |
|---|---|---|
| License selection for first public release | 🔜 | Apache-2.0 candidate; not finalized |
| `CODEOWNERS` and review policy | 🔜 | |
| Constitution v0.2 amendment cycle | 🔜 | After first real engagement feedback |

---

**Editing this file:** every item should have a phase, a status emoji, and (when one exists) a GitHub issue link. Items move down (✅) when the work lands and the corresponding doc/code is merged.
