# Phase 4: Modernize

**MAP alignment:** AWS MAP — *Migrate & Modernize* (modernize portion).

**Goal:** Post-migration modernization — cost, reliability, security, and the architectural improvements that were deferred from cutover.

For container workloads, modernization is rarely optional. Right-sizing, Karpenter tuning, IRSA cleanup, and GitOps maturity all live here. Refactor decisions deferred from Phase 2 (e.g. moving a service to App Runner or Lambda) are scheduled and executed in this phase.

## Inputs
- Running workloads on AWS
- 30 days of CloudWatch / Prometheus data

## Activities
- Right-sizing (Compute Optimizer + custom analysis)
- Spot / Savings Plan adoption
- Karpenter / Fargate split tuning
- Security hardening (IRSA review, network policies, image scanning)
- SRE: SLOs, runbooks, on-call rotation
- Deferred Refactor / Replatform work from the 7 Rs decisions (see [`7rs-for-containers.md`](../methodology/7rs-for-containers.md))
- GitOps maturity — promotion pipelines, drift detection, policy-as-code

## Outputs
- `optimization-backlog.md`
- Updated IaC

## Exit Criteria
- [ ] Cost target hit (or variance explained)
- [ ] All Sev-1 security findings closed
- [ ] On-call team trained and signed off
