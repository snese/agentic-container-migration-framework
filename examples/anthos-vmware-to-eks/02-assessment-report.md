# Assessment Report — ACME Corp (fictional)

**Engagement:** Anthos-on-VMware → AWS (EKS + ECS Fargate)
**Phase:** 1 — Assess
**Source data:** [`01-discovery-bundle.json`](./01-discovery-bundle.json) (schema v0.2.0)
**Date:** 2026-05-19

> ACMF Constitution Principle 1: *Inventory before strategy.* This report
> contains no recommendations that are not directly traceable to the
> discovery bundle. See [CONSTITUTION.md](../../docs/CONSTITUTION.md).

## 1. Executive summary

ACME Corp operates **1 production Anthos-on-VMware cluster** (`acme-prod-anthos-1`)
hosting ~50 applications across three product domains: payments, checkout,
inventory. The cluster is healthy (avg CPU 42%, p95 78%) but ACME wants to
exit VMware and consolidate on AWS within 12 weeks.

**Recommended target:** Amazon EKS (us-east-1) with the AWS Load Balancer
Controller, EBS CSI (gp3 default, io2 for stateful), Pod Identity, and
Istio (open-source) replacing Anthos Service Mesh. Batch jobs move to ECS
Fargate (see [`docs/decisions/ecs-vs-eks.md`](../../docs/decisions/ecs-vs-eks.md)).

**Confidence:** High for stateless workloads (40 / 50). Medium for
stateful (8 / 50) due to data-migration coupling. Two workloads need
human review (custom CRD `internal.example.com/PaymentRoute`).

## 2. Inventory snapshot

Numbers below come directly from `01-discovery-bundle.json`:

| Dimension | Value | Source path |
|---|---|---|
| Clusters | 1 | `clusters` |
| K8s version | 1.28.5-gke.1217 | `clusters[0].version` |
| Node count (control plane) | 3 | `clusters[0].control_plane.node_count` |
| Default node pool | 6× `vsphere-8vcpu-32gb` | `clusters[0].node_pools[0]` |
| Anthos version | 1.16.3 | `clusters[0].anthos_version` |
| Service mesh | ASM 1.20.2 | `clusters[0].service_mesh` |
| Workloads (all kinds) | 50 (per scope) | `workloads[]` |
| Service accounts | 47 | `identity.service_accounts.total_count` |
| Workload Identity bindings | 1 sampled | `identity.workload_identity_bindings` |
| Ingress / Gateway | 1 (`payment-gateway`) | `networking.ingress` |
| NetworkPolicies | 12 | `networking.network_policies.count` |
| VirtualServices / DestinationRules / AuthZ Policies | 8 / 8 / 5 | `networking.service_mesh` |
| StorageClasses | 1 (`vsphere-csi-fast`) | `storage.storage_classes` |
| PVs / PVCs | 1 / 1 sampled, ~30 estimated full | `storage.persistent_volumes` |
| CRDs needing review | 1 (`PaymentRoute`) | `crds[].needs_human_review` |
| Cluster CPU avg / p95 / max (30d) | 42% / 78% / 91% | `utilization.nodes[0]` |
| Cluster memory avg / p95 / max (30d) | 60% / 80% / 88% | `utilization.nodes[0]` |
| Over-provisioning ratio | 1.8× | `utilization.summary.over_provisioning_ratio` |

## 3. 7R classification

Per [`docs/methodology/7rs-for-containers.md`](../../docs/methodology/7rs-for-containers.md):

| 7R bucket | Count | Examples | Notes |
|---|---|---|---|
| **Replatform** (lift-and-reshape) | 40 | Most stateless `payments/*`, `checkout/*` | Manifest transforms only; same images. |
| **Refactor** (light) | 6 | Anything depending on Workload Identity | SA → Pod Identity rewrite. |
| **Replatform → managed** | 2 | `inventory-db` (Postgres StatefulSet) | Move data to RDS PostgreSQL post-cutover. |
| **Repurchase** | 1 | Internal Redis | → Amazon ElastiCache. |
| **Retire** | 1 | Stale `legacy-batch-importer` (CronJob, not run in 90d) | Confirm with owners, then drop. |
| **Retain** | 0 | — | Full exit from VMware is in scope. |
| **Relocate** | 0 | — | Not applicable for non-VM workloads. |

**Confidence basis:** Counts derived from `workloads[]` classifications and
the assessment of `crds` + `identity` from the bundle. Per-app worksheet
lives in [`03-wave-plan.md`](./03-wave-plan.md).

## 4. Risks and gotchas

Tied to [Anthos source adapter — Known gotchas](../../adapters/source/anthos-vmware/README.md):

1. **vSphere CSI volumes** — no direct EBS equivalent for snapshot lineage.
   Inventory uses Postgres → migrate via logical replication (DMS or pg_dump
   for cutover). See [`docs/decisions/data-migration-patterns.md`](../../docs/decisions/data-migration-patterns.md).
2. **ASM managed dataplane** — strip `mesh.cloud.google.com/*` annotations,
   re-pin `istio.io/rev=default` when Istio is installed on EKS
   (rule `asm_revision_label_strip`).
3. **Workload Identity** — 1 binding observed (likely under-counted; bundle
   only samples `with_non_default_tokens`). All `iam.gke.io/gcp-service-account`
   annotations must be enumerated and mapped to IAM roles before cutover.
4. **Custom CRD `PaymentRoute`** — flagged `needs_human_review`. Verify
   whether the controller is portable or needs reimplementation on EKS.
5. **Over-provisioning** — 1.8× ratio means right-sizing during migration
   can cut node spend; bake into the wave plan.

## 5. Capacity sizing for EKS target

Based on `utilization.summary` and `node_pools`:

- Source allocatable: 6× `vsphere-8vcpu-32gb` ≈ 48 vCPU / 192 GiB
- 30d p95 cluster utilization: 78% CPU / 80% memory
- Target sizing (with 25% headroom on p95):
  - vCPU: `48 × 0.78 / 0.75 ≈ 50` → managed node group, e.g.
    **5× `m6i.2xlarge` (40 vCPU / 160 GiB)** + Karpenter for overflow.
  - For batch (CronJobs): **ECS Fargate** (no idle cost).

Pricing is intentionally not quoted here — per ACMF Constitution
Principle 4 (*no fabricated benchmarks*), customer-specific cost modelling
goes in the engagement-level deliverable, sourced from
[AWS Pricing Calculator](https://calculator.aws/) directly.

## 6. Next phase

Proceed to Phase 2 (Mobilize). Deliverable: [`03-wave-plan.md`](./03-wave-plan.md).
