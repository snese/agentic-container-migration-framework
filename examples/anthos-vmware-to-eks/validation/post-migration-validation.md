# Post-Migration Validation — Acme Retail

> Run after every wave's soak period and again 14 days after full
> decommission. Each check is binary; failures block the next wave or
> trigger a rollback per [`../cutover/cutover-runbook.md`](../cutover/cutover-runbook.md).

## 1. Functional parity

- [ ] Synthetic transactions for `payments`, `checkout`, `inventory` pass
      at the same rate as pre-migration baseline (±2%).
- [ ] Stripe egress sample (1h): zero 401/403 from IRSA-authenticated pods.
- [ ] DB read query checksum (last 1h of writes) matches between source
      and target (Wave 3 only).

## 2. Performance parity

| Service | p95 source | p95 target | Pass criteria |
|---|---|---|---|
| `payments/payment-api`  | ~18ms baseline | <observed> | ≤ source p95 × 1.3 |
| `checkout/checkout-web` | <observed>     | <observed> | ≤ source p95 × 1.3 |
| `inventory/inventory-db` (read) | <observed> | <observed> | ≤ source p95 × 1.5 (data path) |

## 3. GitOps invariants

(Per [`docs/playbooks/config-sync-to-argocd.md`](../../../docs/playbooks/config-sync-to-argocd.md#4-validation-checklist-binary).)

- [ ] All ArgoCD `Application`s: `sync.status == Synced`.
- [ ] All ArgoCD `Application`s: `health.status == Healthy`.
- [ ] Drift detection: hand-edit a managed resource → ArgoCD reverts within
      one self-heal interval.
- [ ] Policy enforcement: a manifest violating a migrated Gatekeeper
      Constraint is rejected at admission.
- [ ] RBAC: non-admin user cannot create an Application outside their
      AppProject's allow-list.
- [ ] Observability alerts bound to **both** `sync.status` and
      `health.status` (not sync alone).
- [ ] No Config Sync remnants: `kubectl get rootsync,reposync -A` returns
      nothing.

## 4. Security & identity

- [ ] No pod uses the default ServiceAccount (per migrated `K8sRequiredLabels`
      Gatekeeper constraint).
- [ ] All Workload Identity bindings replaced; `iam.gke.io/gcp-service-account`
      annotation absent on every SA in scope.
- [ ] IRSA / Pod Identity association exists for every SA that needs AWS
      API access.
- [ ] mTLS enforced (Istio `PeerAuthentication: STRICT`) in `payments` and
      `inventory` namespaces.

## 5. Observability

- [ ] Prometheus scrape from `payments`, `checkout`, `inventory` returns
      non-zero metrics (last 5 min).
- [ ] Logs from all three namespaces visible in CloudWatch Logs / chosen
      logging stack.
- [ ] Alert routing matches pre-migration owners (no orphaned PagerDuty
      services).

## 6. Cost & utilization

- [ ] EKS Auto Mode capacity matches §7 sizing estimate (±20%).
- [ ] No node sits at <10% utilization for 24h (over-provisioning sanity).
- [ ] Cost report for the migration window matches the Phase 1 §8 estimate
      (±20%); flag anything outside the band for finance review.

## 7. Rollback insurance

- [ ] Anthos-side manifests retained in Git for 14 days post-decommission.
- [ ] DNS TTL on `pay.acme.example` restored to original value.
- [ ] DMS replication (Wave 3) kept in opposite direction (target → source)
      for 7 days as fallback.

## Sign-off

| Role | Name | Date |
|---|---|---|
| AWS-side on-call | | |
| Customer technical lead | | |
| Customer business owner | | |
