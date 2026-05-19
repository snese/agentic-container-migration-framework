# ACMF Roadmap

Single source of truth for planned-but-not-yet-done work. When you are tempted to write `TBD` in any other file, add the item here instead and link to it.

**Status legend:** 🔜 planned · 🚧 in progress · ✅ shipped · ⛔ deprecated

## Phase 1 — Assess

| Item | Status | Notes / Issue |
|---|---|---|
| GDC-for-VMware discovery prompt + JSON Schema | 🚧 | First reference adapter (formerly Anthos on VMware) |
| Self-export bash script (`scripts/discovery/anthos-vmware-export.sh`) | ✅ | Option 2 of the discovery menu |
| OpenShift discovery prompt | 🔜 | After GDC reference is stable |
| GKE discovery prompt | 🔜 | Formerly "Anthos-on-GCP" — GKE with GKE Enterprise fleet |
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

| Item | Status | Notes / Issue |
|---|---|---|
| EKS Auto Mode vs ECS Fargate cost-model worksheet | 🔜 | Real workload baselines required |
| Right-sizing analysis prompt (Compute Optimizer + Prometheus) | 🔜 | |
| GitOps maturity scorecard | 🔜 | |
| Optional Strands-based ongoing optimization agent recipe | 🔜 | Phase 4 only; opt-in (see CONSTITUTION §1) |

## Phase 5 — Document

| Item | Status | Notes / Issue |
|---|---|---|
| First case study (GDC for VMware → EKS) | 🔜 | Pending real engagement |
| Case-study anonymization checklist | 🔜 | |

## Adapters

### Source adapters

| Item | Status | Notes |
|---|---|---|
| Source: GDC for VMware (formerly Anthos on VMware) | 🚧 | First reference; `adapters/source/anthos-vmware/` |
| Source: GDC for Bare Metal | ✅ | Shares VMware adapter with `--platform=bare-metal` flag (skips vSphere discovery) |
| Source: GKE (formerly "Anthos on GCP") | 🔜 | Standard GKE + GKE Enterprise fleet; `adapters/source/gke/` |
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
| GDC-vs-AWS pricing comparison sheet | 🔜 | |

## Decisions / open questions

| Item | Status | Notes |
|---|---|---|
| Concrete cost models per ECS-vs-EKS pattern | 🔜 | Need real customer baselines |
| EKS Auto Mode vs ECS Fargate cost comparison for equivalent workloads | 🔜 | |
| Multi-region story per target (EKS / ECS) | 🔜 | |
| Live-migration via mesh federation (GDC ↔ EKS) | 🔜 | Advanced pattern |

## Governance

| Item | Status | Notes |
|---|---|---|
| License selection for first public release | 🔜 | Apache-2.0 candidate; not finalized |
| `CODEOWNERS` and review policy | 🔜 | |
| Constitution v0.2 amendment cycle | 🔜 | After first real engagement feedback |

---

**Editing this file:** every item should have a phase, a status emoji, and (when one exists) a GitHub issue link. Items move down (✅) when the work lands and the corresponding doc/code is merged.
