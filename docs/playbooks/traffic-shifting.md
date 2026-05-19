# Traffic Shifting Playbook — Anthos → AWS Cutover

> **Scope.** Methodology-level guidance: when to shift progressively vs
> big-bang, the numbered cutover sequence, and rollback trigger thresholds.
> **Not** an Istio multi-cluster tutorial — every implementation step links
> to upstream docs. Target length: 1–2 pages.

## 1. Decision — Progressive vs Big-Bang

| Signal | → Progressive (1/5/25/50/100%) | → Big-bang (single switch) |
|---|---|---|
| Stateful workload (DB, queue, sticky session) | ✅ required | ❌ |
| Service mesh already in source cluster (Istio / ASM) | ✅ leverage `VirtualService` weights | — |
| Cross-cluster mesh feasible (mTLS trust bridged) | ✅ | — |
| Read-only / idempotent HTTP API only | acceptable | ✅ acceptable |
| Strict cutover window (regulator, contract) | ❌ | ✅ |
| No telemetry to evaluate rollback triggers (§3) | ❌ — fix telemetry first | ❌ — see "blue-green by DNS" below |
| Customer cannot run two stacks in parallel (cost / quota) | ❌ | ✅ |

**Default:** progressive when telemetry exists, big-bang only when at least
one row in the right column applies and §3 thresholds can still be evaluated
post-cutover.

**Big-bang variant — blue-green by DNS / weighted ALB:** if no mesh, use
[Route 53 weighted routing][r53-weighted] or
[ALB weighted target groups][alb-weighted] for a 0→100 switch with a documented
rollback DNS change. Same §3 thresholds apply.

## 2. Numbered Cutover Sequence

Each gate is **binary**. Failing a gate means rollback per §3, not "investigate
and continue".

1. **Pre-flight.** Confirm:
   - Discovery bundle §10 (traffic) shows top service pairs & p95 latency.
   - SLOs documented (latency, error rate, data-consistency check).
   - Rollback runbook printed and owned by a named on-call.
   - **Gate A:** Source SLOs are green for the last 24h. If not, do not start.
2. **Bridge the data plane.** Stand up the AWS-side stack
   (EKS / ECS) with the workload deployed and warm. Establish cross-cluster
   connectivity:
   - Mesh path → [Istio multi-cluster][istio-multi] (primary-remote or
     multi-primary) with shared trust root, **or**
   - Non-mesh path → [VPC peering / Transit Gateway + Route 53 Private
     Hosted Zone][vpc-r53] for service discovery.
   - **Gate B:** Synthetic probe from AWS-side reaches Anthos-side service
     and vice versa; mTLS handshake (if mesh) succeeds.
3. **Mirror traffic (shadow).** Route 100% to source, mirror a copy to AWS
   target. With Istio: `VirtualService.http.mirror`
   ([upstream docs][istio-mirror]). With ALB: dual-write at the client
   (out of scope — only when mesh is unavailable).
   - **Gate C:** Mirrored AWS-side request rate ≈ source rate (±5%);
     AWS-side error rate ≤ source + 0.1pp; logs sampled and reviewed.
4. **Shift 1%.** Flip 1% of live traffic to AWS via weighted routing.
   - Mesh: `VirtualService` `weight` field
     ([traffic shifting task][istio-shift]).
   - DNS: [Route 53 weighted records][r53-weighted].
   - ALB: [weighted target groups][alb-weighted].
   - **Gate D:** Hold ≥ 15 min. Evaluate §3 thresholds.
5. **Shift 5% → 25% → 50% → 100%.** Same evaluation each step. Hold time
   per step ≥ max(15 min, 1 full traffic-pattern cycle, e.g. one batch run).
   - **Gate E (each step):** §3 thresholds met for the full hold window.
6. **Drain source.** Once at 100% AWS for one full business day, set source
   weight to 0 but keep capacity warm (rollback budget).
   - **Gate F:** No rollback events in the soak window.
7. **Decommission source.** Scale source workload to zero; keep manifests
   in Git for ≥ 14 days (rollback insurance).
   - **Gate G:** No incidents linked to the migrated service in soak window.

For stateful services, perform §2 only after the data plane is consistent
per [`docs/decisions/data-migration-patterns.md`](../decisions/data-migration-patterns.md).

## 3. Rollback Trigger Criteria

Roll back **immediately** (revert weight to previous step) if **any** trigger
fires during a hold window. Do not "wait and see".

| Signal | Threshold | Source |
|---|---|---|
| HTTP 5xx error rate (AWS-side) | > source baseline + **1.0pp**, sustained 5 min | mesh / ALB metrics |
| p95 request latency (AWS-side) | > source p95 × **1.3** for any service in top-10 by volume | mesh / APM |
| p99 request latency (AWS-side) | > source p99 × **1.5** for any top-10 service | mesh / APM |
| Saturation (CPU or memory) | > **80%** sustained 5 min on AWS-side workload | container metrics |
| Data-consistency check (stateful only) | dual-read diff rate > **0.1%** of sampled reads, or replication lag > agreed RPO | app-level checksum / DMS / replica lag |
| Dependency error budget | any downstream dependency burns > **2%** of its monthly budget in the hold window | dependency SLO |
| Customer-impact alert | any user-visible incident page | on-call |

Thresholds are defaults — tune per workload during pre-flight and record
them in the change ticket. Do **not** loosen thresholds mid-cutover.

**Rollback action:** revert the weight (Istio `VirtualService` /
Route 53 record / ALB target-group weight) to the previous successful step,
then stop. Investigate before retrying. If at step 4 (1%), revert to 0 and
re-enter shadow (step 3).

## 4. References

- Istio: [traffic management concepts][istio-tm] ·
  [traffic shifting task][istio-shift] · [mirroring][istio-mirror] ·
  [multi-cluster install][istio-multi]
- AWS: [Route 53 weighted routing][r53-weighted] ·
  [ALB weighted target groups][alb-weighted] ·
  [App Mesh is deprecated][app-mesh-deprecation] (do not adopt) ·
  [VPC Lattice service-to-service][vpc-lattice]
- AWS blog: [Multi-cluster service mesh on EKS with Istio][aws-blog-istio]
- ACMF: [`docs/decisions/data-migration-patterns.md`](../decisions/data-migration-patterns.md)
  for the stateful side · [`docs/decisions/ecs-vs-eks.md`](../decisions/ecs-vs-eks.md)
  notes that App Mesh is deprecated.

[istio-tm]: https://istio.io/latest/docs/concepts/traffic-management/
[istio-shift]: https://istio.io/latest/docs/tasks/traffic-management/traffic-shifting/
[istio-mirror]: https://istio.io/latest/docs/tasks/traffic-management/mirroring/
[istio-multi]: https://istio.io/latest/docs/setup/install/multicluster/
[r53-weighted]: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-weighted.html
[alb-weighted]: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html#target-group-weights
[vpc-r53]: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-private.html
[vpc-lattice]: https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html
[app-mesh-deprecation]: https://docs.aws.amazon.com/app-mesh/latest/userguide/what-is-app-mesh.html
[aws-blog-istio]: https://aws.amazon.com/blogs/containers/multi-cluster-service-mesh-with-istio-on-amazon-eks/
