# End-to-End Walkthrough: GKE Enterprise on VMware (formerly Anthos on VMware) → EKS

> **Customer:** ACME Corp (fictional)
> **Source:** 5× GKE Enterprise on VMware clusters (4× VMware + 1× baremetal edge), 80 workloads across 13 namespaces, ASM-enabled
> **Target:** Amazon EKS (us-east-1 + ap-east-2) + ECS Fargate for batch jobs + EKS Hybrid Nodes for edge
> **Timeline:** 16 weeks (Phase 1 → Phase 5 per ACMF Constitution)
> **Status:** Reference example — **not** a real customer engagement.

This directory walks through every artifact a real ACMF v0.3 engagement
produces, end-to-end, for one anonymized fictional customer.

| Artifact | File | ACMF Phase |
|---|---|---|
| 0. Executive summary | [`00-executive-summary.md`](./00-executive-summary.md) | Phase 1 — Assess (customer leadership) |
| 1. Discovery bundle | [`01-discovery-bundle.json`](./01-discovery-bundle.json) | Phase 1 — Assess |
| 2. Assessment report | [`02-assessment-report.md`](./02-assessment-report.md) | Phase 1 — Assess |
| 3. Wave plan | [`03-wave-plan.md`](./03-wave-plan.md) | Phase 2 — Mobilize |
| 4. Manifest before/after | [`04-manifest-translation.md`](./04-manifest-translation.md) | Phase 3 — Migrate |
| 5. ArgoCD config | [`05-argocd-config.yaml`](./05-argocd-config.yaml) | Phase 3 — Migrate |
| 6. Cutover runbook | [`06-cutover-runbook.md`](./06-cutover-runbook.md) | Phase 3 — Migrate |
| 7. Post-migration validation | [`07-validation.md`](./07-validation.md) | Phase 4 — Modernize |

## How to use this example

- **Customers:** Read in order. Substitute your numbers / names.
- **AWS field teams:** Use as a customer-deliverable template. The wave plan
  and cutover runbook are the artifacts most often replicated.
- **Kiro/Q agents:** Use the discovery bundle as a few-shot example when
  asked to produce assessment output.

## Cross-references

- [ACMF Constitution](../../docs/CONSTITUTION.md) — the four non-negotiables
- [Phases overview](../../docs/phases/README.md)
- [7Rs for containers](../../docs/methodology/7rs-for-containers.md)
- [CAF perspectives](../../docs/methodology/caf-perspectives/) — business / governance / operations / people / platform / security
- [Config Sync → ArgoCD playbook](../../docs/playbooks/config-sync-to-argocd.md)
- [Traffic shifting playbook](../../docs/playbooks/traffic-shifting.md)
- [ECS vs EKS decision](../../docs/decisions/ecs-vs-eks.md)
- [Data migration patterns](../../docs/decisions/data-migration-patterns.md)
- [GKE Enterprise on VMware source adapter](../../adapters/source/gke-enterprise-vmware/)
- [EKS target adapter](../../adapters/target/eks/)

## Source data

Every quantified claim in this walkthrough cites either:

- **The ACME discovery bundle** in this folder (fictional but schema-valid)
- **AWS / GDC public docs** — linked inline

No external benchmarks are fabricated. Where ACMF would normally cite a
customer-specific finding (e.g. "p95 latency 18 ms"), the value is taken
from the bundle's `traffic.pairs` and is consistent with itself across
documents.
