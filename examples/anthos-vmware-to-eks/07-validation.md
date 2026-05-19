# Post-Migration Validation — ACME Corp

**Phase:** 4 — Modernize (entry gate)
**Inputs:** Cutover signed off per [`06-cutover-runbook.md`](./06-cutover-runbook.md)

This is the checklist ACME runs **after** the wave is fully on EKS, before
moving on to modernization (managed services swap, right-sizing, etc.).
ACMF Constitution Principle 2 (*observability before mutation*) applies:
do not start optimization until parity is proven.

## 1. Functional parity

| Area | Probe | Pass criteria |
|---|---|---|
| HTTP path coverage | `make api-contract-tests` (all wave apps) | 100% pass |
| gRPC path coverage | `grpcurl` smoke against each Service | 100% pass |
| Event-driven | Kafka consumer lag (Anthos vs EKS, same topic) | EKS lag ≤ Anthos lag (24h window) |
| Cron / batch | Compare last 7 daily-run outputs | Byte-for-byte match (or doc'd intentional drift) |

## 2. Non-functional parity

Compare 7-day rolling windows pre- and post-cutover. Use Bundle's
`utilization.summary` as the pre-cut baseline.

| Metric | Source on Anthos | Source on EKS | Pass criteria |
|---|---|---|---|
| p50 latency | Istio (ASM) telemetry | Istio (OSS) on EKS / ALB CloudWatch | EKS within ±10% |
| p95 latency | same | same | EKS within ±15% |
| Error rate (5xx + gRPC ≥ 13) | same | same | EKS ≤ Anthos baseline |
| CPU usage / pod | metrics-server | metrics-server | EKS ≤ 110% of Anthos |
| Memory usage / pod | metrics-server | metrics-server | EKS ≤ 110% of Anthos |
| HPA scale-up time | `kube-state-metrics` | same | EKS ≤ 60s for stateless |

## 3. Security & compliance

| Check | Tool | Pass criteria |
|---|---|---|
| All Pod Identity associations resolve | `aws eks describe-pod-identity-association` | Every wave SA mapped to a role |
| No `iam.gke.io/gcp-service-account` annotations remain | `kubectl get sa -A -o yaml \| grep iam.gke.io` | Zero matches |
| ECR images signed (Notation/Cosign) | `cosign verify` | All prod images verified |
| NetworkPolicy denies default-allow | `kubectl get netpol -A` | At least one default-deny per ns |
| AWS Config rules green | Config dashboard | No CRITICAL findings |
| GuardDuty / Security Hub | Console | Zero HIGH findings tied to migrated workloads |

Per [`docs/methodology/caf-perspectives/security.md`](../../docs/methodology/caf-perspectives/security.md).

## 4. Cost / right-sizing readiness (informational, not gating)

After 14 days of EKS-only operation:

- Compute Optimizer recommendations exported.
- Karpenter consolidation enabled (only after stability proven).
- Bundle's `utilization.summary.over_provisioning_ratio = 1.8` is the
  upper bound on right-sizing savings; do not promise more.

## 5. Documentation & handover

| Artifact | Owner | Acceptance |
|---|---|---|
| Updated platform runbooks | Platform | Reviewed by SRE on-call rota |
| ArgoCD ownership transferred to ACME | Platform | ACME admins log in, deploy a no-op app |
| AWS field "as-built" diagram | AWS field | Submitted to engagement record |
| Decommission ticket for Anthos namespace(s) | Platform | Filed, scheduled |

## Sign-off

| Role | Name | Date | Notes |
|---|---|---|---|
| App owner |  |  |  |
| Platform lead |  |  |  |
| SRE on-call |  |  |  |
| Security |  |  |  |
| AWS field |  |  |  |

Sign-off advances the wave to Phase 5 — Document. See
[`docs/phases/05-document.md`](../../docs/phases/05-document.md).
