# Cutover Runbook — ACME Corp Wave 2 (Stateless Production)

**Phase:** 3 — Migrate
**Wave:** 2 (30 stateless apps)
**Target window:** Saturday 02:00–06:00 UTC (low traffic)
**Rollback window:** 24h

> Per ACMF Constitution Principle 3 (*reversibility*): every step below has
> an explicit rollback. Do not advance to the next step until the previous
> step's success criteria are met.

## Pre-cutover (T–48h)

| # | Step | Owner | Verify |
|---|---|---|---|
| 1 | EKS cluster green (`kubectl get nodes`, all Ready) | Platform | All nodes Ready ≥ 30 min |
| 2 | AWS LB Controller, EBS CSI, External DNS, Karpenter healthy | Platform | `kubectl -n kube-system get deploy` |
| 3 | ECR pull-through cache primed for all wave-2 images | Platform | `aws ecr list-images` per repo |
| 4 | ArgoCD wave-2 ApplicationSet syncs to EKS in dry-run mode | Platform | All apps Healthy, no diff |
| 5 | Route 53 weighted records pre-staged at 0% to EKS | Platform | `aws route53 list-resource-record-sets` |
| 6 | Synthetic test traffic from EKS → on-prem `inventory-db` succeeds | SRE | `curl` health checks |
| 7 | App owners sign off in #migration-warroom | App owners | Slack acknowledgement |

## Cutover (T–0)

| # | Step | Command / action | Success | Rollback |
|---|---|---|---|---|
| C1 | Freeze writes on Anthos (HPA disabled, deployments scaled-to-current) | `kubectl -n payments scale --replicas=$N` | No new ReplicaSets created | Re-enable HPA |
| C2 | ArgoCD: sync wave-2 ApplicationSet to live | ArgoCD UI / `argocd app sync` per app | All apps Healthy in EKS | `argocd app rollback` |
| C3 | Smoke tests against EKS-internal Service hostnames | `make smoke-wave2` | Exit code 0 | Stop, do not advance |
| C4 | Shift Route 53 weighted records: EKS=10, Anthos=90 | `aws route53 change-resource-record-sets` | DNS resolves; ALB sees traffic | Set EKS weight to 0 |
| C5 | Watch ALB 4xx/5xx + p95 for 15 min | CloudWatch dashboard | Error rate < 0.1%; p95 within 10% of baseline | Step C4 rollback |
| C6 | Shift weights: EKS=50, Anthos=50 | same as C4 | Same as C5 | Set EKS weight to 0 |
| C7 | Watch for 30 min | CloudWatch dashboard | Same as C5 | Step C4 rollback |
| C8 | Shift weights: EKS=100, Anthos=0 | same as C4 | Same as C5 | Set EKS weight to 0 (Anthos still warm) |
| C9 | Watch for 60 min | CloudWatch dashboard | Same as C5 | Step C4 rollback |

For traffic-shifting mechanics see
[`docs/playbooks/traffic-shifting.md`](../../docs/playbooks/traffic-shifting.md).

## Post-cutover (T+24h)

| # | Step | Owner | Verify |
|---|---|---|---|
| P1 | Anthos replicas scaled to 0 (warm-cold) | Platform | `kubectl -n <ns> get deploy` on Anthos |
| P2 | Run validation suite | SRE | See [`07-validation.md`](./07-validation.md) |
| P3 | App owners sign-off | App owners | Slack acknowledgement |
| P4 | Decommission Anthos namespaces (delete, not stop) | Platform | `kubectl delete ns -l acme.io/wave=2` (Anthos cluster) |

## Rollback (any time within 24h)

1. Set Route 53 EKS weight = 0; Anthos weight = 100.
2. Wait 60s for DNS TTL.
3. Re-enable HPA on Anthos.
4. Open postmortem ticket within 24h.

For stateful waves (3, 4) the rollback path is *not* identical — replication
direction must be reversed; see Phase 3 stateful pattern in
[`docs/decisions/data-migration-patterns.md`](../../docs/decisions/data-migration-patterns.md).

## Communication template

```
[ACME Migration] Wave 2 cutover starting at <TIME>.
Status updates every 15 min in #migration-warroom.
Rollback owner: <name>. War-room bridge: <link>.
```
