# End-to-End Example: Anthos-on-VMware → EKS

> **Customer:** Acme Retail Group (fictional but realistic)
> **Source:** 1 Anthos-on-VMware cluster, 3 production namespaces
> **Target:** EKS (managed) in `us-east-1`, ECS Fargate considered for stateless tier
> **Audience:** customer technical lead + AWS account team — usable as a demo

This walkthrough is the canonical worked example for ACMF v0.3. Every artifact
is anonymized but realistic; numbers are illustrative, not benchmarks.

## Phase map

| Phase | Artifact in this folder | ACMF doc reference |
|---|---|---|
| 1 — Assess | [`discovery/discovery-bundle.json`](discovery/discovery-bundle.json) · [`assessment/assessment-report.md`](assessment/assessment-report.md) | [phases/01-assess.md](../../docs/phases/01-assess.md) |
| 2 — Mobilize | [`wave-plan/wave-plan.md`](wave-plan/wave-plan.md) | [phases/02-mobilize.md](../../docs/phases/02-mobilize.md) |
| 3 — Migrate | [`manifests/`](manifests/) · [`argocd/`](argocd/) | [phases/03-migrate.md](../../docs/phases/03-migrate.md) · [playbooks/config-sync-to-argocd.md](../../docs/playbooks/config-sync-to-argocd.md) |
| 4 — Modernize | (out of scope for this walkthrough — see post-migration validation) | [phases/04-modernize.md](../../docs/phases/04-modernize.md) |
| 5 — Document | [`cutover/cutover-runbook.md`](cutover/cutover-runbook.md) · [`validation/post-migration-validation.md`](validation/post-migration-validation.md) | [phases/05-document.md](../../docs/phases/05-document.md) |

## Scenario

Acme Retail runs 3 production namespaces on a single Anthos-on-VMware cluster
(`prod-anthos-1`):

- `payments` — stateless HTTP APIs, ASM-meshed, Workload Identity → GCP-side
  IAM for Stripe and internal billing
- `checkout` — stateless HTTP APIs, GCE Ingress + BackendConfig
- `inventory` — stateful PostgreSQL StatefulSet on vSphere CSI

Cluster sits at ~42% CPU / ~60% memory on a 6-node default pool. Anthos
Config Sync points at one root repo. Policy Controller has 12 constraints,
all upstream Gatekeeper templates.

## Decisions captured upfront

| Question | Decision | Source |
|---|---|---|
| EKS vs ECS Fargate? | **EKS Auto Mode** — ASM + Policy Controller + 11 CRDs in active use | [decisions/ecs-vs-eks.md](../../docs/decisions/ecs-vs-eks.md) |
| GitOps tool? | **ArgoCD** (1:1 RootSync → Application; RepoSyncs → AppProjects) | [playbooks/config-sync-to-argocd.md](../../docs/playbooks/config-sync-to-argocd.md) |
| Cutover style? | **Progressive** for `payments` (mesh + telemetry), **big-bang DNS** for `checkout`, **dual-write** for `inventory` | [playbooks/traffic-shifting.md](../../docs/playbooks/traffic-shifting.md) |
| Data migration for `inventory`? | DMS continuous replication → cutover on weight=100% | [decisions/data-migration-patterns.md](../../docs/decisions/data-migration-patterns.md) |

## Reading order

1. Start with [`discovery/discovery-bundle.json`](discovery/discovery-bundle.json) — the inputs.
2. Read [`assessment/assessment-report.md`](assessment/assessment-report.md) — what we'd present back to the customer.
3. Skim [`wave-plan/wave-plan.md`](wave-plan/wave-plan.md) for sequencing.
4. Inspect [`manifests/before`](manifests/before) vs [`manifests/after`](manifests/after) — concrete transforms.
5. Look at [`argocd/`](argocd/) for the GitOps deployment surface.
6. Walk through [`cutover/cutover-runbook.md`](cutover/cutover-runbook.md) — the actual day-of plan.
7. Finish at [`validation/post-migration-validation.md`](validation/post-migration-validation.md).

All artifacts are checked in as text — diff-friendly, demoable, ready to fork
for a real customer engagement.
