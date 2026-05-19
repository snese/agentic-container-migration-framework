# Karpenter Right-Sizing Playbook

> **Scope.** Methodology-level guidance: when to pick [Karpenter][karpenter]
> over Cluster Autoscaler, NodePool design principles, and the right-sizing
> loop. **Not** a NodePool YAML tutorial — every implementation step links
> to upstream docs ([karpenter.sh/docs][karpenter]). Target length: 1–2
> pages.
>
> **Cost-claim policy.** Public AWS materials (Karpenter blog, Compute
> Optimizer, Graviton page, Savings Plans) are cited where they exist.
> Specific percentage savings for a given customer are marked
> `[INTERNAL-REVIEW-NEEDED]` so the AWS-internal reviewer can validate
> against actual benchmark data.

## 1. Decision — Karpenter vs Cluster Autoscaler

| Signal | → Keep Cluster Autoscaler (CA) | → Switch to Karpenter |
|---|---|---|
| Single, narrow instance family across the cluster | ✅ — CA is sufficient | — |
| Strict regulatory or operational requirement to use ASG (e.g. existing capacity-reservation tooling) | ✅ | — |
| Heterogeneous workloads (CPU-/memory-/GPU-bound mixed) | — | ✅ — Karpenter selects per-pod ([NodePools][nodepools]) |
| Frequent burst / batch workloads, second-scale provisioning matters | — | ✅ — Karpenter provisions without an ASG round-trip ([Karpenter intro][karpenter-blog]) |
| Spot adoption is a goal, want diversification across many instance types | — | ✅ — NodePool requirements drive diversification |
| Want consolidation (bin-packing across underutilized nodes) | — | ✅ — see [Disruption / consolidation][disruption] |
| Team has no capacity to learn another controller | ✅ — until it does | — |

**Default:** new EKS clusters in 2026 default to Karpenter unless a row in
the left column applies. Coexistence (CA managing one node group while
Karpenter manages others) is supported but adds operational surface — pick
one as the primary scaler.

## 2. NodePool Design Principles

NodePool YAML lives in [karpenter.sh/docs/concepts/nodepools][nodepools] —
do not duplicate it here. The principles below tell you **what** to put in
a NodePool, not how to spell it.

### 2.1 Multi-architecture (arm64 + amd64)

- Add `kubernetes.io/arch` requirements covering both `arm64` and `amd64`
  unless a specific workload binary blocks Graviton.
- Build images multi-arch (manifest list) so Karpenter is free to schedule
  on whichever the bin-packer prefers.
- Cost angle: AWS Graviton is documented as offering "up to 40% better
  price-performance over comparable x86-based instances" on the
  [Graviton page][graviton]; the **actual** $/workload delta depends on
  workload mix and is `[INTERNAL-REVIEW-NEEDED]` for any specific
  customer estimate.

### 2.2 Spot / On-Demand mix

- Default split: **stateless tier on Spot** with broad instance-type
  diversification; **control-plane / stateful / latency-critical tier on
  On-Demand**.
- Use a separate NodePool per capacity type — do not mix Spot and
  On-Demand requirements in one NodePool unless you have a clear reason
  ([NodePools][nodepools]).
- For long-lived On-Demand baselines, layer a [Compute Savings
  Plan][savings-plans] over the predictable floor; mark the workload-
  specific Savings Plan recommendation as `[INTERNAL-REVIEW-NEEDED]`
  (depends on commitment tolerance).
- Spot-interruption handling is the workload's responsibility (graceful
  shutdown, PDBs). Do not adopt Spot for a workload that cannot tolerate
  a 2-minute notice.

### 2.3 Consolidation policy

[Karpenter consolidation][disruption] supports two policies:
`WhenEmpty` and `WhenEmptyOrUnderutilized`.

| Workload type | Recommended policy |
|---|---|
| Long-running, stateful (StatefulSet, DB) | `WhenEmpty` only — avoid disruption |
| Stateless, well-defined PDBs, restart-safe | `WhenEmptyOrUnderutilized` |
| Latency-sensitive APIs in a hot path | `WhenEmpty`; revisit after telemetry justifies otherwise |
| Batch / Job workloads | `WhenEmptyOrUnderutilized` |

Always pair consolidation with `disruption.budgets` to cap the blast
radius. Specific budget numbers are workload-specific; see
[Disruption][disruption].

### 2.4 Other principles

- Set `expireAfter` to force periodic node rotation (security patching).
- Use `taints` + `nodeSelector` to keep large/expensive instance families
  available only to workloads that justify them.
- Limit per-NodePool with `limits.cpu` / `limits.memory` so a runaway
  HPA cannot blow the budget.

## 3. Workload Requests Calibration — The 30-Day Loop

This is the right-sizing process. It is iterative, not one-shot.

1. **Baseline (read-only, no changes).**
   - Pull 30-day [Compute Optimizer][compute-optimizer] findings for the
     EKS-backing EC2 instances and for the workloads themselves.
   - Pull Prometheus / CloudWatch metrics: container CPU/memory `usage`
     vs `requests` p50, p95, p99 over 30 days.
   - Pull HPA scale events and OOMKill counts.
2. **Classify.** Bucket workloads into:
   - **Over-provisioned**: p95 usage < 30% of requests, no OOMKills.
   - **Right-sized**: p95 usage 30–80% of requests, low OOMKill rate.
   - **Under-provisioned**: p95 usage > 80% of requests, recurring
     OOMKills, or HPA pegged at max.
3. **Adjust requests, not limits.**
   - Lower requests on over-provisioned workloads first — this is where
     bin-packing wins land. Move limits only if they are clearly wrong.
   - Raise requests (and likely limits) on under-provisioned workloads
     **before** Karpenter consolidates them onto smaller nodes.
   - Use the prompt in `prompts/modernize/right-sizing-analysis.prompt.md`
     to produce a structured per-workload recommendation with confidence
     scoring.
4. **Roll out behind a canary.** Apply the new requests to one Deployment
   replica or one canary namespace; observe for one full traffic-pattern
   cycle.
5. **Measure.** Re-pull the metrics from step 1 a week after rollout.
   Recompute the §5 KPIs.
6. **Repeat.** Right-sizing is a quarterly cadence at minimum.

Customer-specific savings from this loop are
`[INTERNAL-REVIEW-NEEDED]`; the public Karpenter consolidation blog
([Optimizing your Kubernetes compute costs with Karpenter
consolidation][karpenter-consolidation-blog]) describes the mechanism but
does not publish a universal % saving.

## 4. Anti-patterns

- **Blindly enabling `WhenEmptyOrUnderutilized` on a latency-sensitive
  namespace.** Consolidation = disruption. Use `WhenEmpty` first; promote
  only when telemetry shows the workload tolerates eviction.
- **Setting `limits == requests` everywhere "for safety".** This destroys
  bin-packing headroom and inflates node count.
- **One giant NodePool with every instance type and both Spot/On-Demand.**
  Hard to reason about; hard to attribute cost. Split by capacity type
  and by workload tier.
- **Right-sizing from a single day of metrics.** Weekly traffic cycles
  and monthly batch jobs will be missed; minimum window is 30 days.
- **Migrating to Karpenter before fixing requests.** You will
  consolidate over-provisioned pods onto fewer over-provisioned nodes —
  the bill barely moves. Calibrate requests first or in lock-step.
- **Adopting Spot without PDBs and graceful-shutdown handlers.** A
  Spot-interruption storm becomes a customer-visible outage.
- **Skipping `disruption.budgets`.** Without budgets, consolidation can
  evict every replica of a Deployment in a single round.

## 5. Validation — KPIs That Should Move

After a right-sizing cycle, the following should improve. Targets are
workload-dependent and `[INTERNAL-REVIEW-NEEDED]` for customer-specific
numbers; the **direction** is universal.

| Metric | Direction | Source |
|---|---|---|
| Cluster node count at steady state | ↓ | EKS / Karpenter metrics |
| `requests / actual usage` ratio (p95) | ↓ toward ~1.3–1.7 | Prometheus / CloudWatch |
| `$ / cluster / month` (or per-tenant equivalent) | ↓ | Cost Explorer / CUR |
| Spot share of compute hours (if Spot adopted) | ↑ | Cost Explorer |
| OOMKill rate | flat or ↓ | kube-state-metrics |
| HPA pegged-at-max event count | flat or ↓ | HPA events |
| p95 / p99 request latency on migrated workloads | flat (no regression) | mesh / APM |

Cost reduction percentage from a Karpenter + right-sizing program varies
materially by starting state. Internal benchmarks suggest
`[INTERNAL-REVIEW-NEEDED]` potential cost reduction in the 20–50% range
for clusters with significant prior over-provisioning; HC team to
validate against actual customer data.

## 6. References

- Karpenter: [docs home][karpenter] · [NodePools][nodepools] ·
  [Disruption / consolidation][disruption] ·
  [karpenter-provider-aws (GitHub)][karpenter-aws]
- AWS: [Compute Optimizer][compute-optimizer] ·
  [Graviton processors][graviton] ·
  [Compute Savings Plans][savings-plans]
- AWS blog: [Introducing Karpenter — an open-source Kubernetes cluster
  autoscaler][karpenter-blog] ·
  [Optimizing your Kubernetes compute costs with Karpenter
  consolidation][karpenter-consolidation-blog]
- Kubernetes: [autoscaling concepts][k8s-autoscaling]
- ACMF: [`docs/phases/04-modernize.md`](../phases/04-modernize.md) ·
  prompt: `prompts/modernize/right-sizing-analysis.prompt.md`

[karpenter]: https://karpenter.sh/docs/
[nodepools]: https://karpenter.sh/docs/concepts/nodepools/
[disruption]: https://karpenter.sh/docs/concepts/disruption/
[karpenter-aws]: https://github.com/aws/karpenter-provider-aws
[compute-optimizer]: https://aws.amazon.com/compute-optimizer/
[graviton]: https://aws.amazon.com/ec2/graviton/
[savings-plans]: https://aws.amazon.com/savingsplans/compute-pricing/
[karpenter-blog]: https://aws.amazon.com/blogs/aws/introducing-karpenter-an-open-source-high-performance-kubernetes-cluster-autoscaler/
[karpenter-consolidation-blog]: https://aws.amazon.com/blogs/containers/optimizing-your-kubernetes-compute-costs-with-karpenter-consolidation/
[k8s-autoscaling]: https://kubernetes.io/docs/concepts/workloads/autoscaling/
