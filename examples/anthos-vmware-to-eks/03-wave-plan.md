# Wave Plan — ACME Corp

**Engagement:** Anthos-on-VMware → AWS (EKS + ECS Fargate)
**Phase:** 2 — Mobilize
**Inputs:** [`02-assessment-report.md`](./02-assessment-report.md)

## Strategy

50 applications split into **4 waves** of increasing risk. Each wave runs
2–3 weeks; the entire plan completes inside the 12-week target.

Wave selection criteria (in priority order):
1. **Statelessness first** — no data migration required.
2. **No custom CRD dependencies** — defer `PaymentRoute` consumers to wave 4.
3. **Owner availability** — wave order coordinated with owning teams.
4. **Blast radius** — non-customer-facing first; payments last.

## Wave 1 — Sandbox / pilot (week 1–2)

| App count | Domain | Pattern | Notes |
|---|---|---|---|
| 5 | internal tooling | stateless Deployment | low-traffic; validates platform |

- Goal: prove EKS + ArgoCD + ALB Ingress + Pod Identity end-to-end on
  non-critical workloads.
- Cutover style: blue/green via DNS, 24h soak.
- Exit criteria: zero rollbacks, p95 latency parity with Anthos baseline.

## Wave 2 — Stateless production (week 3–6)

| App count | Domain | Pattern | Notes |
|---|---|---|---|
| 30 | checkout, frontend | stateless Deployment + HPA | bulk of the catalogue |

- Cutover style: traffic shifting via Route 53 weighted records (10% → 50%
  → 100%). See [traffic-shifting playbook](../../docs/playbooks/traffic-shifting.md).
- ASM → Istio (open source) installed at start of wave. ASM remains
  authoritative on Anthos until shift complete.
- Image registry: ECR pull-through cache pointed at GCR; no image rebuilds.
- Exit criteria: ALB error rate < 0.1%, no HPA thrash, ECR replication caught up.

## Wave 3 — Stateful (week 7–9)

| App count | Domain | Pattern | Notes |
|---|---|---|---|
| 8 | inventory, orders | StatefulSet + RWO PVC | data migration on critical path |

- Pattern per [`docs/decisions/data-migration-patterns.md`](../../docs/decisions/data-migration-patterns.md):
  - **Postgres** (`inventory-db`): logical replication with DMS, cutover
    during low-traffic window, RDS as long-term target.
  - **Redis** (`session-cache`): warm via dual-write at app layer for 48h,
    cutover, repurchase as ElastiCache later.
- StatefulSet identity preserved (same pod-name, same DNS via Headless Service).
- Exit criteria: replication lag < 1s before cutover, dry-run failover
  rehearsed twice.

## Wave 4 — Payments + custom CRDs (week 10–12)

| App count | Domain | Pattern | Notes |
|---|---|---|---|
| 7 | payments, `PaymentRoute` consumers | mix | highest scrutiny |

- `PaymentRoute` controller decision required before wave starts (refactor
  or replace).
- Cutover style: dark traffic + per-merchant feature flag, 14-day soak.
- Exit criteria: zero customer-impacting incidents in soak, parity on
  reconciliation reports, formal sign-off from Risk + Compliance.

## Dependencies

Captured per [`adapters/target/eks/`](../../adapters/target/eks/) prerequisites:

- AWS account vended with VPC (3 AZ), private subnets, transit gateway to
  on-prem.
- IAM roles for: cluster, node groups, AWS LB Controller, ALB, EBS CSI,
  EFS CSI, External DNS, Cluster Autoscaler / Karpenter, ArgoCD.
- Route 53 hosted zone delegated for `*.acme.io` migration namespace.
- ECR repositories created per source registry path.

## RACI

Per [`docs/methodology/caf-perspectives/people.md`](../../docs/methodology/caf-perspectives/people.md):

| Activity | Platform | App owners | SRE | Security | AWS field |
|---|---|---|---|---|---|
| EKS cluster build | R | I | C | C | A |
| Manifest translation | A | R | C | I | C |
| Data migration (DMS) | C | C | R | C | A |
| Cutover execution | A | R | R | C | C |
| Post-migration validation | C | C | R | C | A |

## Rollback budget

- Each wave has a **24h rollback window** during which DNS can be flipped
  back to Anthos with no data loss for stateless waves.
- Stateful waves use staged DMS replication; rollback is supported up to the
  point at which the source DB is taken out of replication.
