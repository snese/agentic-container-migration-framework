# Cutover Runbook — Acme Retail (Wave 2: `payments`)

> Worked example for the **most demanding wave** — mesh + Workload Identity +
> external SaaS. Other waves follow the same shape; see
> [`../wave-plan/wave-plan.md`](../wave-plan/wave-plan.md) for entry/exit gates.
>
> Methodology references: [traffic-shifting.md](../../../docs/playbooks/traffic-shifting.md)
> · [config-sync-to-argocd.md](../../../docs/playbooks/config-sync-to-argocd.md)

## Roles

| Role | Owner | Backup |
|---|---|---|
| Cutover commander | <name> | <name> |
| AWS-side on-call | <name> | <name> |
| Anthos-side on-call | <name> | <name> |
| Customer business owner | <name> | <name> |

Conference bridge: `<link>`. Ticket: `CHG-<id>`.

## T-7 days — pre-flight

- [ ] Wave 0 + Wave 1 exit gates green and signed.
- [ ] IRSA role `payment-api-sa` created with Stripe-egress trust policy.
- [ ] ServiceAccount annotation swap PR merged to migration-target repo
      (Workload Identity → IRSA).
- [ ] `PaymentRoute` CRD usage replaced by `VirtualService` rules; PR merged.
- [ ] DNS TTL on `pay.acme.example` lowered to 60s (≥ 24h before cutover).
- [ ] Synthetic transactions for `payments` running on AWS-side, last 24h
      green.
- [ ] Source SLOs (latency, error rate) green for last 24h
      (**traffic-shifting.md §2 Gate A**).
- [ ] Rollback runbook printed; on-call has access.

## T-1 hour — go/no-go

- [ ] All checks above re-confirmed.
- [ ] No active production incidents in either environment.
- [ ] Cutover commander, AWS-side on-call, Anthos-side on-call, customer
      business owner all on bridge.
- [ ] Decision logged: **GO** / **NO-GO**. NO-GO → reschedule, no further
      steps.

## T-0 — cutover sequence (progressive 1/5/25/50/100%)

Each step holds **≥ 15 min** and evaluates the rollback triggers in
[traffic-shifting.md §3](../../../docs/playbooks/traffic-shifting.md#3-rollback-trigger-criteria).
A single trigger fire = **rollback**, not "wait and see".

1. **Bridge confirmed.** mTLS handshake succeeds in both directions
   (synthetic probe). **Gate B.**
2. **Shadow at 100% source / 100% mirror to AWS.** AWS-side request rate
   ≈ source ±5%; AWS-side error rate ≤ source + 0.1pp. **Gate C.**
3. **Shift 1%.** Apply Istio `VirtualService` weight `(source: 99, aws: 1)`.
   Hold ≥ 15 min. **Gate D.**
4. **Shift 5%.** Hold ≥ 15 min. **Gate E.**
5. **Shift 25%.** Hold ≥ 15 min. **Gate E.**
6. **Shift 50%.** Hold ≥ 15 min. **Gate E.**
7. **Shift 100%.** Hold ≥ 1 business day. **Gate F.**

Sample `VirtualService` weight change (full schema in upstream Istio docs):

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata: { name: payment-api, namespace: payments }
spec:
  hosts: [payment-api.payments.svc.cluster.local]
  http:
    - route:
        - destination: { host: payment-api-source.payments.svc.cluster.local }
          weight: 95
        - destination: { host: payment-api-aws.payments.svc.cluster.local }
          weight: 5
```

## Rollback procedure

Triggered by any §3 threshold or any user-visible incident page:

1. Cutover commander declares **ROLLBACK**.
2. AWS-side on-call reverts the `VirtualService` weight to the **previous
   successful step** (one git commit, one `kubectl apply`).
3. Anthos-side on-call confirms source workload absorbs full load
   (CPU/mem headroom, no error spike).
4. After 15 min stable: incident write-up started; do **not** retry the same
   weight in the same change window — investigate first.

If at step 3 (1%): roll back to **0%** and re-enter shadow mode.

## T+24h — soak

- [ ] No rollback events.
- [ ] No §3 threshold breaches.
- [ ] Stripe egress: zero 401/403 from IRSA-authenticated pods (1h sample).
- [ ] Customer business owner confirms business KPIs (orders/min, payment
      success rate) within ±2% of baseline.

## T+1 business day — drain source

- [ ] Set `payment-api-source` weight to 0 (kept warm for 14d).
- [ ] Pause Config Sync for `payments` namespace.
- [ ] Flip ArgoCD `automated: { prune: true, selfHeal: true }` per
      [config-sync-to-argocd.md §3 step 8](../../../docs/playbooks/config-sync-to-argocd.md#3-migration-sequence). **Gate H.**

## T+14 days — decommission

- [ ] Anthos-side `payments` workload scaled to zero.
- [ ] Manifests preserved in Git for 14 more days (rollback insurance).
- [ ] DNS TTL on `pay.acme.example` restored to original value.
- [ ] Cutover post-mortem complete; lessons folded into Wave 3 plan.
