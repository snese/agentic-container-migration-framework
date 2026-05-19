# Anthos → AWS Assessment Report

> **Template usage.** Fill every `<placeholder>`. Each section names the
> [discovery bundle](../prompts/discovery/anthos-vmware.prompt.md) field it
> reads from. The bundle is validated against
> `schemas/discovery-bundle.schema.json` (see [#17][issue-17] — landing in v0.3).
> Target length: ≤10 pages printed. If a section overflows, move detail to an
> appendix and keep the body to bullet summaries.
>
> Audience: customer technical lead + AWS account team. The "first reader test"
> applies — anyone who has not seen the project should be able to follow it
> end to end.

| Field | Value |
|---|---|
| Customer | `<customer name>` |
| Author / SA | `<name>` |
| Bundle file | `discovery-bundle.json` |
| Bundle `schema_version` | `<bundle.schema_version>` |
| Bundle `generated_at` | `<bundle.generated_at>` |
| Discovery option used | `<1 manifest-only / 2 self-export / 3 read-only / 4 agent-assisted / 5 …>` |

---

## 1. Executive Summary

**Source fields:** synthesised from all bundle sections. Keep to ½ page.

- **Scope.** `<N>` clusters / `<N>` namespaces / `<N>` workloads.
  *(from `scope.clusters[]`, `scope.namespaces_included[]`, `len(workloads[])`)*
- **Recommended target mix.** `<e.g. EKS Auto Mode for system + ECS Fargate for
  stateless services + App Runner for 2 HTTP APIs>`. Rationale lives in §6.
- **Headline risks.** `<top 3 from §5>`.
- **Indicative cost delta.** `<+/- X% vs current Anthos TCO — see §8>`.
- **Recommended migration window.** `<weeks>`, gated by §6 dispositions.

> **Example.** *3 clusters, 142 workloads, 11 CRD groups. Recommend EKS Auto Mode
> for the platform cluster, ECS Fargate for 2 stateless app clusters. Top risks:
> 1 unmaintained CRD (`tigera-operator` v1.27), Istio mTLS coupling to internal
> CA, Oracle DB on vSphere CSI (no AWS-native equivalent).*

---

## 2. Cluster Inventory

**Source field:** `clusters[]` (cross-ref `scope.clusters[]`).

| Cluster | Platform | K8s ver | Anthos ver | Nodes | HA control plane | Recommended target |
|---|---|---|---|---|---|---|
| `<bundle.clusters[i].name>` | `<…platform>` | `<…version>` | `<…anthos_version>` | `<sum(node_pools[].count)>` | `<…control_plane.ha>` | `<EKS Auto / ECS / App Runner>` |
| **Example: `prod-platform-01`** | `vmware` | `1.28.5-gke.1294` | `1.16.3` | `9 (3 cp + 6 worker)` | `yes` | `EKS Auto Mode` |
| **Example: `prod-apps-01`** | `vmware` | `1.27.9-gke.1000` | `1.16.3` | `12 worker` | `yes` | `ECS Fargate` |

Per-cluster node-pool detail, taints, and labels go in **Appendix A** if needed.

---

## 3. Utilization Analysis

**Source fields:** `utilization.nodes[]`, `utilization.pods[]`, `utilization.summary`.

### 3.1 Cluster-wide

| Metric | Value | Source |
|---|---|---|
| Cluster CPU utilization (actual / allocatable) | `<…summary.cluster_cpu_utilization_pct>%` | `utilization.summary` |
| Cluster memory utilization | `<…summary.cluster_memory_utilization_pct>%` | `utilization.summary` |
| Over-provisioning ratio (requests / actual) | `<…summary.over_provisioning_ratio>x` | `utilization.summary` |
| **Example** | `cpu 18% / mem 34% / over-prov 4.2x` | — |

Over-provisioning ratio > 2x is the primary lever for EKS sizing in §7.

### 3.2 Top-10 over-provisioned workloads

**Source:** sort `utilization.pods[]` by `requests.cpu / actual.cpu` desc, group
by workload, take top 10.

| Workload | Namespace | Replicas | CPU req / actual (p95) | Memory req / actual (p95) | Notes |
|---|---|---|---|---|---|
| `<workload>` | `<ns>` | `<n>` | `<r/a>` | `<r/a>` | `<HPA? restart count?>` |
| **Example: `payments-api`** | `apps` | `8` | `2000m / 220m` | `4Gi / 1.1Gi` | HPA never scaled; safe to right-size |

### 3.3 Stability signals

**Source:** `utilization.pods[].restart_count_24h`, HPA scaling events.

- Pods with > 5 restarts in 24h: `<count>` *(list in Appendix B if > 0)*.
- HPA hot-spots (≥ 10 scale events / 24h): `<count>`.

---

## 4. Network Analysis

**Source fields:** `networking.*`, `traffic.*`, `external_dependencies[]`.

### 4.1 Service inventory

| Object | Count | Source |
|---|---|---|
| Services (ClusterIP / LoadBalancer / NodePort / ExternalName) | `<…>` | `networking.services[]` |
| Ingress / Gateway resources | `<…>` | `networking.ingress[]` |
| NetworkPolicies | `<…>` | `networking.network_policies` |
| Istio VirtualServices / DestinationRules / AuthorizationPolicies | `<…/…/…>` | `networking.service_mesh.*` |

### 4.2 Traffic profile

**Source:** `traffic.summary`, `traffic.pairs[]` (top 50).

| Metric | Value |
|---|---|
| East-west bytes/sec (avg) | `<…traffic.summary.east_west_bytes_per_sec>` |
| North-south bytes/sec (avg) | `<…traffic.summary.north_south_bytes_per_sec>` |
| Total distinct service pairs | `<…traffic.summary.total_service_pairs>` |
| Top pair by volume | `<src → dst, bytes/sec, p95 latency ms>` |
| **Example top pair** | `frontend → payments-api, 14 MB/s, p95 38 ms` |

> If `traffic.summary.*` is `null`, mark as **"telemetry unavailable — assume
> mesh required for cross-cluster shift"** and add to §5.

### 4.3 External dependencies

**Source:** `external_dependencies[]`. Group by destination (DB, queue, SaaS, on-prem).

| Destination | Type | Workloads using | AWS path | Risk |
|---|---|---|---|---|
| `<host>` | `<rdbms / kafka / saas / on-prem>` | `<n>` | `<DX / VPN / VPC endpoint / public>` | `<L/M/H>` |
| **Example: `oracle-db.corp.local:1521`** | `rdbms` | `4` | `Direct Connect required` | `H` |

---

## 5. Risk Register

**Source fields:** synthesised from `crds[]`, `warnings[]`, `skipped[]`,
`networking.service_mesh`, `vmware.*`, `external_dependencies[]`.

| # | Risk | Likelihood | Impact | Source field | Mitigation |
|---|---|---|---|---|---|
| R1 | `<e.g. unmaintained CRD>` | M | H | `crds[].group/version` | `<replace / wrap / accept>` |
| R2 | `<e.g. mesh-coupled mTLS>` | H | M | `networking.service_mesh.*` | `<see §9 traffic-shifting playbook>` |
| R3 | `<e.g. discovery gap>` | — | — | `skipped[]`, `warnings[]` | `<re-run with elevated cred>` |
| **Example R1** | `tigera-operator v1.27 unmaintained` | M | H | `crds[]` | Replace with VPC CNI on EKS |

Likelihood / impact: `L / M / H`. Anything `M+ × M+` must have a mitigation owner.

---

## 6. Recommendations — 7Rs Disposition

**Source fields:** per-workload decision over `workloads[]` cross-referenced
with `utilization`, `networking`, `crds`. See
[`docs/methodology/7rs-for-containers.md`](../docs/methodology/7rs-for-containers.md).

| Workload group | Count | Disposition (7R) | Target | Why |
|---|---|---|---|---|
| `<group>` | `<n>` | `<Retain / Relocate / Rehost / Replatform / Repurchase / Refactor / Retire>` | `<EKS Auto / ECS Fargate / App Runner / RDS / managed SaaS>` | `<one-line reason>` |
| **Example: stateless web APIs** | `38` | `Replatform` | `ECS Fargate` | No K8s API usage; HPA is only feature in use |
| **Example: platform / system pods** | `22` | `Rehost` | `EKS Auto Mode` | Operators + CRDs in active use |
| **Example: legacy on-prem batch** | `4` | `Retire` | `—` | Owner confirmed deprecated |

> Group at the **workload-group** level (namespace + label), not per-pod.
> Target selection rationale: see
> [`docs/decisions/ecs-vs-eks.md`](../docs/decisions/ecs-vs-eks.md).

---

## 7. EKS Sizing Estimate

**Source fields:** `utilization.nodes[]`, `utilization.summary`, `vmware.hosts[]`.

Method:

1. **Right-size**: target requests = max(p95 actual × 1.3, current limit / 2).
   Pull p95 from `utilization.pods[].actual.*.p95`.
2. **Headroom**: 25% on top of right-sized requests.
3. **Translate** to EKS Auto Mode node-equivalent vCPU / memory.

| Cluster | Current allocatable (vCPU / GiB) | Right-sized requests (vCPU / GiB) | Recommended EKS Auto capacity |
|---|---|---|---|
| `<cluster>` | `<…>` | `<…>` | `<vCPU / GiB, instance family hint>` |
| **Example: `prod-apps-01`** | `192 / 768` | `48 / 180` | `~64 vCPU / 240 GiB; m7i / c7i mix via Auto Mode` |

Karpenter / Auto Mode chooses instance types — do not pin SKUs in this report.

---

## 8. Cost Comparison — Anthos TCO vs AWS

**Source fields:** `vmware.hosts[]` (compute baseline), §7 sizing, customer-supplied
license + datacenter costs (out of bundle scope — capture separately).

| Cost line | Current (Anthos / vSphere) | Target (AWS) | Notes |
|---|---|---|---|
| Compute | `<USD/mo>` | `<USD/mo>` | EKS Auto / ECS Fargate from §7 |
| Storage | `<USD/mo>` | `<USD/mo>` | EBS gp3 / EFS / S3 — see migration matrix in [`docs/decisions/data-migration-patterns.md`](../docs/decisions/data-migration-patterns.md) |
| Network egress | `<USD/mo>` | `<USD/mo>` | Direct Connect, NAT, VPC endpoints |
| Anthos license | `<USD/mo>` | `0` | — |
| vSphere / vSAN license | `<USD/mo>` | `0` | If decommissioned |
| EKS / ECS control plane | `0` | `<USD/mo>` | $0.10/h per EKS cluster; ECS free |
| **Total / month** | `<…>` | `<…>` | Δ `<+/-%>` |
| **Example total** | `$48k` | `$31k` | −35% (compute right-sizing dominates) |

> Do **not** invent unit prices. Pull from
> [AWS Pricing Calculator](https://calculator.aws/) and cite the saved estimate URL.
> Anthos / vSphere costs come from the customer; flag any line you had to estimate.

---

## Appendices (optional, do not pad)

- **A.** Per-cluster node-pool detail (`clusters[].node_pools[]`).
- **B.** Pods with > 5 restarts / 24h (`utilization.pods[]`).
- **C.** Full CRD list with maintenance status (`crds[]`).
- **D.** `bundle.skipped[]` and `bundle.warnings[]` — discovery gaps and re-run plan.
- **E.** Pricing-calculator URLs and source notes for §8.

---

## Sign-off

| Role | Name | Date |
|---|---|---|
| Customer technical lead | | |
| AWS SA (author) | | |
| AWS SA (first reader) | | |

[issue-17]: https://github.com/snese/agentic-container-migration-framework/issues/17
