# Executive Summary — ACME Corp GKE Enterprise on VMware (formerly Anthos on VMware) → AWS Migration

**Audience:** ACME Corp executive sponsor (VP Eng / CIO)
**Engagement window:** 16 weeks
**Prepared by:** ACMF delivery team
**Source artifacts:** [`01-discovery-bundle.json`](./01-discovery-bundle.json) · [`02-assessment-report.md`](./02-assessment-report.md)
**Status:** Reference example — *not* a real customer engagement.

---

## What we found

ACME runs **5 GKE Enterprise on VMware clusters** spread across two Taipei data centres, one
Hsinchu DR site, and a Kaohsiung edge POP — 80 production workloads, 247
service accounts, 11 stateful systems, and 38 service-mesh routes. The estate
is **healthy** (28% avg CPU, 1.9× over-provisioned) but **stuck on VMware**:
contracts renew in Q1, ASM is on a managed-dataplane track that ACME wants to
exit, and the DR cluster is one GKE Enterprise minor version behind prod.

In one ACMF discovery run we produced a schema-validated inventory of every
workload, every external dependency, every CRD, and every Workload-Identity
binding — without installing a persistent agent, without long-lived
credentials, and without anything leaving ACME's perimeter.

## What we recommend

| Concern | Recommendation |
|---|---|
| Primary target | **Amazon EKS** in us-east-1 (prod) + ap-east-2 (DR), one cluster per region with multi-AZ node groups |
| Stateful data | **RDS PostgreSQL Multi-AZ** (4 instances), **ElastiCache** (Redis), **OpenSearch Serverless** (search) |
| Batch jobs | **ECS Fargate** for the 12 CronJobs/Jobs — no idle cost |
| Edge POP | **EKS Hybrid Nodes** on existing baremetal at KHH (data-plane stays local) |
| Service mesh | Open-source **Istio on EKS** — drop ASM, keep VirtualServices/AuthZ portable |
| Identity | **EKS Pod Identity** (replaces Workload Identity, 7 bindings to migrate) |
| Right-sizing | Cut node spend ~30% by removing the 1.9× over-provision during cutover |
| GitOps | Replace Anthos Config Sync with **ArgoCD** (single repo per cluster) |

## What we'll deliver, by week

```
W1-2     Phase 1 — Assess        ← discovery bundle + this report (DONE in <2h of agent runtime)
W3-6     Phase 2 — Mobilize      ← landing zone IaC, wave plan, ArgoCD bootstrap
W7-13    Phase 3 — Migrate       ← 5 cutover waves, blue/green per wave, rollback verified
W14-15   Phase 4 — Modernize     ← Karpenter, Pod Identity cleanup, RDS proxy, observability
W16      Phase 5 — Document      ← runbook, anonymized case study (with ACME approval)
```

## Why this is credible

1. **Every number traces back** to a path in the discovery bundle. There are
   no fabricated benchmarks, no "industry-average" claims. If the report says
   p95 latency is 18 ms, it's because `traffic.pairs[0].p95_latency_ms` says
   18 ms.
2. **Every prompt the agent ran is in the public ACMF repo.** ACME can read,
   diff, or fork them before authorising another run.
3. **Humans own the decisions.** The agent classified workloads and sized
   targets; the wave plan, cutover go/no-go, and ProServe vs partner choice
   stay with named ACME and AWS leads.
4. **MAP-aligned.** Phases map 1:1 to MAP Assess / Mobilize / Migrate &
   Modernize. Deliverables cover all six AWS CAF perspectives. If ACME has a
   MAP funding agreement, this engagement plugs into it cleanly.

## What we're asking for

- **One sponsor decision** by end of week 2: confirm primary region pair, DR
  posture, and whether the edge POP migrates with the rest or as a follow-on.
- **One ACME platform lead** to co-own the wave plan from week 3 onward.
- **Read-only access** to the staging cluster for cutover-rehearsal validation
  (Discovery Option 3 credentials suffice — same scope as the assessment).
- **Approval to anonymise** the engagement as a public case study post-cutover.

## What's at risk if we delay

VMware contract renewal in Q1 + ASM managed-dataplane sunset = forced
re-platform either way. ACMF compresses Assess + Mobilize from a typical
~10-week SA-led grind into ~6 weeks; every week of slip pushes the prod
cutover into the Q1 freeze window.

---

*Questions, dissent, or "I want to see the receipts": every claim above is
backed by `01-discovery-bundle.json` (schema-valid against
[`schemas/discovery-bundle.schema.json`](../../schemas/discovery-bundle.schema.json))
and the line-by-line breakdown in [`02-assessment-report.md`](./02-assessment-report.md).*
