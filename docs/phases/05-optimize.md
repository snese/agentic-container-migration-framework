# Phase 5: Optimize

**Goal:** Post-migration tuning — cost, reliability, security.

## Inputs
- Running workloads on AWS
- 30 days of CloudWatch / Prometheus data

## Activities
- Right-sizing (Compute Optimizer + custom analysis)
- Spot / Savings Plan adoption
- Karpenter / Fargate split tuning
- Security hardening (IRSA review, network policies, image scanning)
- SRE: SLOs, runbooks, on-call rotation

## Outputs
- `optimization-backlog.md`
- Updated IaC

## Exit Criteria
- [ ] Cost target hit (or variance explained)
- [ ] All Sev-1 security findings closed
- [ ] On-call team trained and signed off
