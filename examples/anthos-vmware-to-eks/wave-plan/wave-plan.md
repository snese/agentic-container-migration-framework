# Wave Plan — Acme Retail Anthos → EKS

> Output of Phase 2 (Mobilize). Each wave has explicit entry criteria, scope,
> and exit gates. Gates reference [`docs/playbooks/traffic-shifting.md`](../../../docs/playbooks/traffic-shifting.md)
> §3 thresholds and [`docs/playbooks/config-sync-to-argocd.md`](../../../docs/playbooks/config-sync-to-argocd.md) §3 gates.

## Wave 0 — Landing zone (week 0–1)

**Scope (no production traffic):**
- VPC, subnets, IAM baseline (PrincipalAccess for SAs)
- EKS cluster `acme-prod-1` in `us-east-1` (Auto Mode)
- ECR repos mirrored from `registry.acme.local`
- ArgoCD installed via EKS Blueprints add-on; SSO wired
- Istio installed (revision `1-22-3`) with shared root CA bridged to ASM
- Gatekeeper installed; 12 ConstraintTemplates re-applied 1:1

**Entry criteria:** assessment report signed off; AWS account + Direct Connect
to TPE-DC1 ready.

**Exit gates (binary):**
- G0.A: `kubectl get nodes` returns ready Auto Mode nodes.
- G0.B: ArgoCD `app list` returns empty; SSO works for non-admin role.
- G0.C: Istio `istioctl proxy-status` clean across both clusters; mTLS handshake
  succeeds in both directions (synthetic probe).
- G0.D: All 12 Gatekeeper constraints enforced; deliberately bad manifest
  rejected in dry-run.

## Wave 1 — `checkout` namespace (week 2–3)

**Why first:** stateless, no mesh, single GCE Ingress → ALB swap.
**Cutover style:** big-bang DNS (Route 53 weighted) — see traffic-shifting.md §1
"big-bang variant — blue-green by DNS".

**Steps:**
1. Apply transformed manifests under [`../manifests/after/checkout/`](../manifests/after) via ArgoCD `automated: false`.
2. Run shadow / synthetic — confirm AWS-side health.
3. Flip Route 53 weight 0 → 100 in one step (during change window).
4. Soak 24h. Decommission Anthos-side after no incidents.

**Exit gates:**
- G1.A: ArgoCD `Application.checkout-web.status` is Synced + Healthy.
- G1.B: ALB target group healthy host count = pod count.
- G1.C: Synthetic transactions pass for 30 min pre-flip.
- G1.D: Post-flip 24h soak: no §3 threshold breach (5xx rate, p95, p99).
- G1.E: Anthos `checkout` namespace scaled to 0 replicas; manifests preserved
  in Git for rollback.

## Wave 2 — `payments` namespace (week 3–5)

**Why second:** mesh-attached, Workload Identity, external SaaS (Stripe).
**Cutover style:** progressive 1/5/25/50/100% via Istio `VirtualService`
weights — see traffic-shifting.md §2.

**Pre-reqs:**
- IAM role `payment-api-sa` created with Stripe-API egress trust policy.
- ServiceAccount annotation swapped (Workload Identity → IRSA) per the
  [`workload-identity-to-pod-identity`](../../anthos-manifests/README.md) rule.
- `internal.acme.example/PaymentRoute` CRD usage replaced with explicit
  Istio `VirtualService` rules (R1 mitigation).

**Steps:** 1 → 5 → 25 → 50 → 100% with ≥15 min hold per step.
Rollback: revert `VirtualService` weight to last successful step.

**Exit gates:**
- G2.A (each step): all rollback triggers in traffic-shifting.md §3 green.
- G2.B (at 100%): p95 latency on AWS-side ≤ source p95 × 1.3 sustained 1h.
- G2.C: Stripe egress requests succeed from IRSA-authenticated pods (zero
  401/403 in 1h sample).
- G2.D: 1 business day at 100% AWS with no rollbacks.

## Wave 3 — `inventory` namespace (week 5–6)

**Why last:** stateful PostgreSQL on vSphere CSI; data plane dominates.
**Cutover style:** AWS DMS continuous replication → flip read traffic at 99%
replica catchup → flip write at maintenance window.

**Pre-reqs:**
- DMS replication instance + endpoints provisioned.
- Target Postgres on EKS uses `ebs-gp3-fast` StorageClass (per
  [`vsphere-csi-to-ebs-or-efs`](../../anthos-manifests/README.md) rule).
- Application connection string indirection (DNS or env) is in place so
  the read path can be flipped without code changes.

**Steps:**
1. Initial DMS load + ongoing CDC. Hold until lag < 5s for 24h.
2. Mirror reads to EKS-side replica; verify dual-read diff < 0.1%.
3. Maintenance window: pause writers, drain CDC queue, flip primary DNS,
   resume writers on EKS-side.
4. Soak 1 business day before decommissioning Anthos-side StatefulSet.

**Exit gates:**
- G3.A: dual-read diff rate ≤ 0.1% sustained 24h.
- G3.B: Replication lag < 5s for 24h pre-cutover.
- G3.C: At cutover: zero data loss confirmed via app-level checksum on
  the last 1h of writes (replayed from app log).
- G3.D: 1 business day post-cutover with no §3 threshold breaches.

## Decommission (week 6+)

After all three waves pass their exit gates and soak windows:
- Remove Config Sync RootSync (per playbooks/config-sync-to-argocd.md §3 step 9).
- Scale Anthos-side workloads to zero, retain manifests in Git for 14 days.
- Power down node pool after 14d quiet period.

## Dependency map

```
Wave 0 ──► Wave 1 (checkout, big-bang)
        └► Wave 2 (payments, progressive — needs IRSA + PaymentRoute → VS rewrite)
        └► Wave 3 (inventory, DMS — needs ebs-gp3-fast SC)
```

Waves 1 → 3 can run in parallel only if operations capacity supports
two concurrent cutovers. Default plan is sequential.
