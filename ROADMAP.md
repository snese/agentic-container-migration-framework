# ACMF Roadmap

Single source of truth for planned-but-not-yet-done work. When you are tempted to write `TBD` in any other file, add the item here instead and link to it.

**Status legend:** 🔜 planned · 🚧 in progress · ✅ shipped

## Phase 1 — Assess

| Item | Status | Notes / Issue |
|---|---|---|
| Anthos-on-VMware discovery prompt + JSON Schema | 🚧 | First reference adapter |
| Self-export bash script (`scripts/discovery/anthos-vmware-export.sh`) | 🔜 | Option 2 of the discovery menu |
| OpenShift discovery prompt | 🔜 | After Anthos reference is stable |
| Anthos-on-GCP discovery prompt | 🔜 | |
| Discovery-bundle JSON Schema (`schemas/discovery-bundle.schema.json`) | 🔜 | |

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
| First case study (Anthos on VMware → EKS) | 🔜 | Pending real engagement |
| Case-study anonymization checklist | 🔜 | |

## Adapters

| Item | Status | Notes |
|---|---|---|
| Source: Anthos on VMware | 🚧 | First reference |
| Source: Anthos on GCP | 🔜 | |
| Source: OpenShift | 🔜 | |
| Source: Rancher / vanilla K8s | 🔜 | |
| Target: EKS — reference Terraform module | 🔜 | |
| Target: EKS — reference Helm umbrella chart | 🔜 | |
| Target: ECS Fargate — reference Terraform module | 🔜 | |
| Target: ECS Fargate — Service Connect migration recipe from Istio | 🔜 | |
| Target: App Runner — IaC sample | 🔜 | |
| Target: App Runner — Anthos → App Runner migration pattern | 🔜 | Rare but real |

## Customer-facing

| Item | Status | Notes |
|---|---|---|
| 1-pager, pitch guide, FAQ | ✅ | `docs/customer-facing/` |
| AWS Transform vs ACMF positioning | ✅ | `docs/decisions/aws-transform-vs-acmf.md` |
| Anthos-vs-AWS pricing comparison sheet | 🔜 | |

## Decisions / open questions

| Item | Status | Notes |
|---|---|---|
| Concrete cost models per ECS-vs-EKS pattern | 🔜 | Need real customer baselines |
| EKS Auto Mode vs ECS Fargate cost comparison for equivalent workloads | 🔜 | |
| Multi-region story per target (EKS / ECS / App Runner) | 🔜 | |
| Live-migration via mesh federation (Anthos ↔ EKS) | 🔜 | Advanced pattern |

## Governance

| Item | Status | Notes |
|---|---|---|
| License selection for first public release | 🔜 | Apache-2.0 candidate; not finalized |
| `CODEOWNERS` and review policy | 🔜 | |
| Constitution v0.2 amendment cycle | 🔜 | After first real engagement feedback |

---

**Editing this file:** every item should have a phase, a status emoji, and (when one exists) a GitHub issue link. Items move down (✅) when the work lands and the corresponding doc/code is merged.
