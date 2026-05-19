# CAF Perspective: Business

The Business perspective answers *why migrate, why now, and how do we know it worked*. For container workloads, this is a different conversation than VM migration: the savings story is rarely "shut down the data center" — it's modernization velocity, platform consolidation, and engineer productivity.

## Stakeholders

- Executive sponsor (CIO / CTO / VP Engineering)
- Finance / FinOps lead
- Product / business unit owners whose workloads are in scope
- Procurement (existing GDC / OpenShift contracts, support agreements)

## Container-specific capabilities

- **Platform consolidation TCO.** Modeling the cost of running on GDC for VMware / OpenShift / Rancher (license + infra + ops) versus EKS / ECS (note: AWS App Runner entered maintenance mode 2026-04-30 and is no longer recommended). Container TCO is dominated by control-plane fees, support contracts, and ops headcount — not VM hours.
- **Modernization velocity as a KPI.** Time-to-deploy, lead time for changes, change failure rate (DORA metrics). Containerized customers care about *speed of shipping* more than raw infra cost.
- **Per-workload unit economics.** Cost per request / per tenant / per active user, surfaced via Kubecost or AWS Cost Allocation tags — not just per-cluster cost.
- **Exit-cost modeling.** Honest accounting of cross-cloud egress, image registry duplication, dual-running during waves, and write-off of in-flight GDC/OpenShift commitments.

## Key deliverables

- Business case with three-year TCO comparison (current platform vs target AWS pattern)
- Value-tracking KPI dashboard spec — DORA metrics + unit economics + reliability
- Modernization ROI model — incremental value of replatform/refactor decisions on top of straight rehost
- Migration funding plan, including any AWS MAP funding mapping

## Anti-patterns to avoid

- Selling a container migration on "shut down the data center" savings — the data center usually stays.
- Comparing list-price GDC to discounted EKS; always normalize to effective rate after credits.
- Promising 30%+ infra savings without a right-sizing or Spot/Karpenter assumption made explicit.
- Treating modernization spend as free; refactor work has real engineering cost that must be in the model.

## How agentic discovery contributes

Agent-driven manifest analysis surfaces evidence the business case actually needs: how many workloads are stateless and Fargate-eligible, how many use CRDs that block Repurchase to managed runtimes, what percentage of CPU/memory is over-allocated, which namespaces dominate cost. Without this, business cases are built on assumptions; with it, every TCO number traces back to a manifest path or a metric.
