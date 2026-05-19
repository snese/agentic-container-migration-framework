# Assessment Report — ACME Corp (fictional)

**Engagement:** GDC for VMware (formerly Anthos on VMware) → AWS (EKS + ECS Fargate)
**Phase:** 1 — Assess
**Source data:** [`01-discovery-bundle.json`](./01-discovery-bundle.json) (schema v0.2.0)
**Date:** 2026-05-19

> ACMF Constitution Principle 1: *Inventory before strategy.* This report
> contains no recommendations that are not directly traceable to the
> discovery bundle. See [CONSTITUTION.md](../../docs/CONSTITUTION.md).

## 1. Executive summary

ACME Corp operates **5 GDC for VMware clusters** (`acme-prod-anthos-1`, `acme-prod-anthos-2`,
`acme-stg-anthos-1`, `acme-dr-anthos-1`, `acme-edge-anthos-1`) hosting **80 workloads**
across 13 namespaces and four product domains: payments, checkout, inventory,
orders/fulfillment/search/recs. Two production clusters sit in TPE-DC1 and TPE-DC2,
one warm-DR cluster in HSQ-DC1, one staging cluster, and a 3-node baremetal edge
fleet at the KHH POP. The estate is healthy (cluster-avg CPU 28%, p95 78% in prod)
but ACME wants to exit VMware and consolidate on AWS within 16 weeks.

**Recommended target:** Amazon EKS (us-east-1 primary, ap-east-2 DR) with the AWS
Load Balancer Controller, EBS CSI (gp3 default, io2 for stateful), Pod Identity,
and Istio (open-source) replacing Anthos Service Mesh. Batch CronJobs/Jobs move
to ECS Fargate (see [`docs/decisions/ecs-vs-eks.md`](../../docs/decisions/ecs-vs-eks.md)).
Edge cluster is a candidate for **EKS Hybrid Nodes** or AWS Outposts — keep
local-path storage, replace ASM with App Mesh-lite or single-cluster Istio.

**Confidence:** High for stateless workloads (54 / 80). Medium for stateful
(13 / 80) due to data-migration coupling. Three workloads need human review
(custom CRDs `internal.acme.io/PaymentRoute`, `EdgePolicy`, `FeatureFlag`).

## 2. Inventory snapshot

Numbers below come directly from `01-discovery-bundle.json`:

| Dimension | Value | Source path |
|---|---|---|
| Clusters | 5 | `clusters` |
| K8s versions | 1.28.5 (3 clusters), 1.27.10 (2 clusters) | `clusters[].version` |
| Total worker nodes | 23 | `clusters[].node_pools[].count` |
| GDC versions | 1.16.3 / 1.16.2 | `clusters[].anthos_version` |
| Service mesh | ASM 1.20.2 (all clusters) | `clusters[].service_mesh` |
| Workloads (all kinds) | 80 | `workloads[]` |
| — Stateless | 54 | `workloads[?classification=='stateless']` |
| — Stateful | 13 | `workloads[?classification=='stateful']` |
| — Batch (Jobs/CronJobs) | 12 | `workloads[?classification=='batch']` |
| — System (DaemonSets/operators) | 1 (per scope; cluster operators excluded) | derived |
| Service accounts (total) | 247 | `identity.service_accounts.total_count` |
| Workload Identity bindings (sampled) | 7 | `identity.workload_identity_bindings` |
| Ingress / Gateway | 5 | `networking.ingress` |
| NetworkPolicies | 64 | `networking.network_policies.count` |
| VirtualServices / DestinationRules / AuthZ Policies | 38 / 38 / 22 | `networking.service_mesh` |
| StorageClasses | 2 (`vsphere-csi-fast`, `local-path`) | `storage.storage_classes` |
| PVs / PVCs | 11 / 11 sampled | `storage.persistent_volumes` |
| CRDs needing review | 3 (`PaymentRoute`, `EdgePolicy`, `FeatureFlag`) | `crds[].needs_human_review` |
| Cluster CPU avg / p95 / max (30d, prod) | 42% / 78% / 91% | `utilization.nodes[?cluster~prod]` |
| Cluster memory avg / p95 / max (30d, prod) | 60% / 80% / 88% | `utilization.nodes[?cluster~prod]` |
| Over-provisioning ratio (estate-wide) | 1.9× | `utilization.summary.over_provisioning_ratio` |
| External dependencies (deduped) | 9 hosts | `external_dependencies` |

## 3. 7R classification

Per [`docs/methodology/7rs-for-containers.md`](../../docs/methodology/7rs-for-containers.md):

| 7R bucket | Count | Examples | Notes |
|---|---|---|---|
| **Replatform** (lift-and-reshape) | 54 | Most stateless `payments/*`, `checkout/*`, `orders/*`, `fulfillment/*`, `search-api`, `edge-gateway/*` | Manifest transforms only; same images. |
| **Refactor** (light) | 9 | Anything depending on Workload Identity (7 bindings) + cert-manager wiring | SA → Pod Identity rewrite. |
| **Replatform → managed** | 6 | `inventory-db`, `orders-db`, `payment-replica` (Postgres) | Move data to RDS PostgreSQL post-cutover. |
| **Repurchase** | 4 | `inventory-cache` (Redis ×3), `search-elastic` | → ElastiCache, OpenSearch Serverless. |
| **Retire** | 2 | `legacy-batch-importer` (CronJob, last run > 90d), one staging duplicate | Confirm with owners, then drop. |
| **Retain** | 0 | — | Full exit from VMware is in scope. |
| **Relocate** | 5 | Edge fleet (`edge-cache-node` DaemonSet etc.) | EKS Hybrid Nodes / Outposts — same hardware footprint. |

**Confidence basis:** Counts derived from `workloads[]` classifications and the
assessment of `crds` + `identity` from the bundle. Per-app worksheet lives in
[`03-wave-plan.md`](./03-wave-plan.md).

## 4. Risks and gotchas

Tied to [GDC for VMware source adapter — Known gotchas](../../adapters/source/anthos-vmware/README.md):

1. **vSphere CSI volumes** — no direct EBS equivalent for snapshot lineage.
   13 stateful workloads (Postgres ×4, Redis ×3, Elasticsearch ×1, plus edge
   caches) need data-migration plans. Postgres workloads migrate via logical
   replication (DMS or pg_dump); Redis via warm-cache backfill; Elasticsearch
   via cross-cluster restore. See [`docs/decisions/data-migration-patterns.md`](../../docs/decisions/data-migration-patterns.md).
2. **ASM managed dataplane** — strip `mesh.cloud.google.com/*` annotations,
   re-pin `istio.io/rev=default` when Istio is installed on EKS
   (rule `asm_revision_label_strip`). 38 VirtualServices + 22 AuthZ Policies
   to translate.
3. **Workload Identity** — 7 bindings observed across 5 clusters (likely
   under-counted; bundle only samples `with_non_default_tokens`). All
   `iam.gke.io/gcp-service-account` annotations must be enumerated and mapped
   to IAM roles before cutover.
4. **Custom CRDs** — 3 CRDs flagged `needs_human_review` (`PaymentRoute`,
   `EdgePolicy`, `FeatureFlag`). Verify whether the controllers are portable
   or need reimplementation on EKS.
5. **Over-provisioning** — 1.9× ratio means right-sizing during migration
   can cut node spend ~30%; bake into the wave plan.
6. **Mixed K8s versions** — DR + edge clusters are on 1.27. EKS target version
   should be a 1.28 (matches prod) and DR/edge re-baselined during cutover.
7. **Edge cluster (baremetal)** — `acme-edge-anthos-1` runs on baremetal hosts
   at the KHH POP, not VMware. Target is EKS Hybrid Nodes or AWS Outposts;
   data-plane stays local for latency.

## 5. Capacity sizing for EKS target

Based on `utilization.summary` and `node_pools`:

- Source allocatable (prod-1 + prod-2): 12× `vsphere-8vcpu-32gb` ≈ 96 vCPU / 384 GiB
- 30d p95 prod cluster utilization: 78% CPU / 80% memory
- Target sizing (with 25% headroom on p95):
  - vCPU: `96 × 0.78 / 0.75 ≈ 100` → **2× managed node group** (one per AZ pair),
    e.g. **10× `m6i.2xlarge` (80 vCPU / 320 GiB)** + Karpenter for overflow.
  - For batch (12 CronJobs/Jobs): **ECS Fargate** (no idle cost).
  - For DR (us-west-2): **3× `m6i.2xlarge`** warm-pool, scale on cutover.
  - For edge (KHH POP): **EKS Hybrid Nodes**, 3× existing baremetal hosts.
  - For stateful: **RDS PostgreSQL Multi-AZ** (4 instances), **ElastiCache**
    (Redis cluster mode), **OpenSearch Serverless** (search collection).

Pricing is intentionally not quoted here — per ACMF Constitution
Principle 4 (*no fabricated benchmarks*), customer-specific cost modelling
goes in the engagement-level deliverable, sourced from
[AWS Pricing Calculator](https://calculator.aws/) directly.

## 6. Next phase

Proceed to Phase 2 (Mobilize). Deliverable: [`03-wave-plan.md`](./03-wave-plan.md).
