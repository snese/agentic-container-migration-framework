# Anthos → AWS Assessment Report — Acme Retail Group

> Generated from [`../discovery/discovery-bundle.json`](../discovery/discovery-bundle.json)
> against `schemas/discovery-bundle.schema.json` (v0.2.0). Walk-through example
> filled in from the assessment template at `templates/assessment-report.md`.

| Field | Value |
|---|---|
| Customer | Acme Retail Group (fictional) |
| Author / SA | ACMF reference engagement |
| Bundle file | `discovery-bundle.json` |
| Bundle `schema_version` | 0.2.0 |
| Bundle `generated_at` | 2026-05-15T09:30:00Z |
| Discovery option used | 2 — self-export script (`scripts/discovery/anthos-vmware-export.sh`) |

---

## 1. Executive Summary

- **Scope.** 1 cluster (`prod-anthos-1`) / 3 namespaces (`payments`, `checkout`,
  `inventory`) / 3 production workloads + their supporting Services and PVCs.
- **Recommended target mix.** **EKS Auto Mode** for everything: ASM, Policy
  Controller, and 7 CRDs (one custom `PaymentRoute`) make ECS Fargate a poor
  fit. Stateless tier could move to ECS later, but Phase 3 stays on EKS.
- **Headline risks.**
  1. `internal.acme.example/PaymentRoute` CRD has no AWS-side equivalent —
     needs human review (R1).
  2. Stateful `inventory-db` on vSphere CSI Retain PV — data plane migration
     dominates the timeline (R2).
  3. ASM ↔ Istio revision swap on cutover requires bridged trust during
     traffic shift (R3).
- **Indicative cost delta.** Compute right-sizing alone (over-prov 1.8x →
  ~1.2x) is the dominant lever. Detailed numbers are customer-supplied; this
  example does not invent unit prices.
- **Recommended migration window.** **3 waves over ~6 weeks**, gated by §6.

---

## 2. Cluster Inventory

| Cluster | Platform | K8s ver | Anthos ver | Nodes | HA control plane | Recommended target |
|---|---|---|---|---|---|---|
| `prod-anthos-1` | vmware | 1.28.5-gke.1217 | 1.16.3 | 6 worker (default-pool, 8vCPU/32GiB) + 3 cp | yes (stacked-ha) | EKS Auto Mode |

Service mesh: ASM 1.20.2 enabled. Config Sync 1.17.1 active (RootSync only,
single repo).

---

## 3. Utilization Analysis

### 3.1 Cluster-wide

| Metric | Value | Source |
|---|---|---|
| Cluster CPU utilization | 42.0% | `utilization.summary.cluster_cpu_utilization_pct` |
| Cluster memory utilization | 60.0% | `utilization.summary.cluster_memory_utilization_pct` |
| Over-provisioning ratio | 1.8x | `utilization.summary.over_provisioning_ratio` |

### 3.2 Top over-provisioned workloads

| Workload | Namespace | Replicas | CPU req / actual (p95) | Memory req / actual (p95) | Notes |
|---|---|---|---|---|---|
| `payment-api` | payments | 4 | 500m / 320m | 512Mi / 410Mi | mild over-prov, leave as-is |
| `inventory-db` | inventory | 3 | 2 / 1.1 | 8Gi / 6Gi | safe at current sizing; right-size at modernize |

### 3.3 Stability signals

- Pods with > 5 restarts / 24h: 0
- HPA hot-spots (≥ 10 scale events / 24h): 0

---

## 4. Network Analysis

### 4.1 Service inventory

| Object | Count |
|---|---|
| Services | 2 (both ClusterIP) |
| Ingress / Gateway | 2 (1 GCE Ingress, 1 ASM Gateway) |
| NetworkPolicies | 12 |
| Istio VS / DR / AP | 8 / 8 / 5 |

### 4.2 Traffic profile

| Metric | Value |
|---|---|
| East-west bytes/sec | ~5 MB/s |
| North-south bytes/sec | ~1 MB/s |
| Total service pairs | 23 |
| Top pair | `payments/payment-api → inventory/inventory-db`, 240 RPS, p95 18ms |

Telemetry source is Istio — progressive shifting feasible for `payments`.

### 4.3 External dependencies

| Destination | Type | Workloads using | AWS path | Risk |
|---|---|---|---|---|
| `api.stripe.com:443` | SaaS | 1 (payment-api) | Public egress + NAT | L |
| `kafka.shared.svc:9092` | queue | 1 (inventory-db) | MSK or self-managed Kafka — out of scope | M |

---

## 5. Risk Register

| # | Risk | L | I | Source | Mitigation |
|---|---|---|---|---|---|
| R1 | `PaymentRoute` CRD has no AWS equivalent | M | H | `crds[6]` | Replace with VirtualService rules in cutover wave 2; owner: payments team |
| R2 | `inventory-db` on vSphere CSI Retain PV | H | H | `storage.persistent_volumes` | DMS continuous replication; see [data-migration-patterns.md](../../../docs/decisions/data-migration-patterns.md) |
| R3 | ASM mTLS trust bridge on cutover | M | M | `clusters[0].service_mesh` | Multi-primary Istio setup with shared root CA; see [traffic-shifting.md](../../../docs/playbooks/traffic-shifting.md) §2 |
| R4 | Workload Identity → IRSA cutover | L | M | `identity.workload_identity_bindings` | Pre-create IAM role `payment-api-sa`, swap SA annotation per the [`workload-identity-to-pod-identity`](../../anthos-manifests/README.md) rule |
| R5 | Discovery gap: vCenter perf history <30d | L | L | `skipped[0]` | Use 7d window for sizing; flag in cutover review |

---

## 6. 7Rs Disposition

| Workload group | Count | Disposition | Target | Why |
|---|---|---|---|---|
| `payments/payment-api` | 1 Deployment | Replatform | EKS Auto Mode | Mesh + WI; minimal code change |
| `checkout/checkout-web` | 1 Deployment | Rehost | EKS Auto Mode | GCE Ingress → ALB; no mesh dependency |
| `inventory/inventory-db` | 1 StatefulSet (3 replicas) | Replatform | EKS Auto Mode + DMS to RDS PostgreSQL **OR** in-cluster on EBS | Customer choice; default = in-cluster on EBS for parity |

See [`docs/methodology/7rs-for-containers.md`](../../../docs/methodology/7rs-for-containers.md).

---

## 7. EKS Sizing Estimate

| Cluster | Current allocatable (vCPU / GiB) | Right-sized requests (vCPU / GiB) | Recommended EKS Auto capacity |
|---|---|---|---|
| `prod-anthos-1` | 48 / 192 | ~20 / ~110 | ~32 vCPU / ~144 GiB; m7i / c7i mix via Auto Mode |

Method: requests = max(p95 actual × 1.3, current limit / 2). Auto Mode picks
SKUs — do not pin instance types.

---

## 8. Cost Comparison

> Customer-supplied baseline. Numbers below are placeholders to demonstrate
> the structure — replace with [AWS Pricing Calculator](https://calculator.aws/)
> output for the real engagement.

| Cost line | Current (Anthos / vSphere) | Target (AWS) | Notes |
|---|---|---|---|
| Compute | TBD | TBD | EKS Auto, right-sized per §7 |
| Storage | TBD | TBD | EBS gp3 100Gi × 3 + snapshots |
| Network egress | TBD | TBD | NAT for Stripe; VPC endpoints for AWS APIs |
| Anthos license | TBD | 0 | — |
| vSphere / vSAN license | TBD | 0 | If decommissioned |
| EKS control plane | 0 | $0.10/h | 1 cluster |
| **Total / month** | TBD | TBD | Δ TBD |

---

## Sign-off

| Role | Name | Date |
|---|---|---|
| Customer technical lead | | |
| AWS SA (author) | | |
| AWS SA (first reader) | | |
