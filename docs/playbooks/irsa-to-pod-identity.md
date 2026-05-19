# IRSA → EKS Pod Identity Migration Playbook

> **Scope.** Methodology-level guidance: when to migrate from IAM Roles for
> Service Accounts (IRSA) to [EKS Pod Identity][eks-pi], the numbered
> sequence with go/no-go gates, and rollback criteria. **Not** a tutorial —
> every step links to upstream AWS docs for the actual configuration.
> Target length: 1–2 pages.
>
> **Both are valid in 2026.** IRSA continues to be a supported, fully
> documented mechanism ([IRSA docs][irsa]). Pod Identity is the newer
> abstraction ([Pod Identities concepts][pi-concepts]). Migrate when the
> ergonomics or operational benefits clear the bar in §1 — not by default.

## 1. Decision — When to Migrate

| Signal | → Migrate to Pod Identity | → Stay on IRSA |
|---|---|---|
| Many roles reused across multiple clusters / accounts | ✅ — Pod Identity decouples role from cluster OIDC issuer ([docs][pi-concepts]) | — |
| Frequent service-account ↔ role rotation | ✅ — association is a separate API call, no trust-policy edit | — |
| Existing IRSA works, no operational pain | — | ✅ — leave it |
| AWS service / SDK does not yet support Pod Identity | ❌ | ✅ — see [supported services list][pi-setup] |
| Region not yet supported by Pod Identity | ❌ | ✅ — verify in [pod-identity-agent-setup][pi-setup] |
| EKS version **< 1.24** | ❌ | ✅ — Pod Identity requires Kubernetes ≥ 1.24 ([prereqs][pi-setup]) |
| Cross-account role assumption pattern | check carefully — review [cross-account behaviour][pi-concepts] | acceptable on IRSA |
| Workload uses Fargate **only** | ❌ at time of writing — verify [supported compute types][pi-setup] | ✅ |

**Default:** if any "stay" row applies and no "migrate" row gives a clear
operational win, do not migrate. Coexistence (§4) lets you migrate
selectively, workload by workload.

## 2. Eligibility Check (binary — do this first)

- [ ] EKS cluster Kubernetes version ≥ **1.24** ([Pod Identity prereqs][pi-setup]).
- [ ] Cluster region is in the [Pod Identity supported regions list][pi-setup].
- [ ] Compute type is supported (managed node groups / self-managed nodes;
      verify Fargate / Auto Mode status in [pi-setup][pi-setup]).
- [ ] Every AWS SDK in scope is at a version that supports the
      `AssumeRoleForPodIdentity` credential provider — see the
      "Setup the EKS Pod Identity Agent" section of [pi-setup][pi-setup]
      for the SDK matrix.
- [ ] `eks-pod-identity-agent` add-on can be installed (cluster IAM role has
      the required permissions per [pi-setup][pi-setup]).

If any box is unchecked, fix it or stop here.

## 3. Concept Mapping (minimal)

| IRSA | Pod Identity | Notes |
|---|---|---|
| OIDC issuer per cluster | Pod Identity Agent DaemonSet + EKS API association | No OIDC provider needed for new roles. |
| `eks.amazonaws.com/role-arn` annotation on `ServiceAccount` | `CreatePodIdentityAssociation` (cluster + namespace + service account → role ARN) | Annotation is **ignored** when an association exists for the same SA — see §4. |
| Trust policy with `StringEquals` on OIDC `sub` | Trust policy with `pods.eks.amazonaws.com` principal + session tags | Use the trust-policy template in [Pod Identities concepts][pi-concepts]. |

Minimal trust-policy mapping example (full schema in [Pod Identities
concepts][pi-concepts]):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "pods.eks.amazonaws.com" },
    "Action": ["sts:AssumeRole", "sts:TagSession"]
  }]
}
```

For everything beyond this skeleton (cross-account, condition keys,
session tags), follow [Pod Identities concepts][pi-concepts].

## 4. Coexistence Period — How EKS Resolves Identity

Per the [Pod Identities concepts doc][pi-concepts], when **both** an IRSA
service-account annotation **and** a Pod Identity association exist for the
same `(cluster, namespace, service account)`:

> Pod Identity takes precedence; the IRSA annotation is ignored at
> credential-resolution time.

This means you can:

1. Create the Pod Identity association for a single workload.
2. Restart its pods.
3. Verify it now uses the new credential chain (§6).
4. Only then remove the IRSA annotation and (eventually) the OIDC trust
   policy on the IAM role.

Do not delete IRSA artefacts before Pod Identity is verified — the override
behaviour is what makes a per-workload migration safe.

## 5. Migration Sequence

Each gate is **binary**. If a gate fails, stop and remediate before
proceeding (or roll back per §7).

1. **Inventory.** List every `ServiceAccount` carrying the
   `eks.amazonaws.com/role-arn` annotation, the role ARN it maps to, and
   the workloads consuming it.
   - **Gate A:** Inventory matches the live IAM trust policies (no orphan
     trust statements, no orphan annotations).
2. **Install the Pod Identity Agent add-on** on the target cluster
   following [pi-setup][pi-setup]. Confirm the DaemonSet is `Ready` on
   every node.
   - **Gate B:** `kubectl -n kube-system get ds eks-pod-identity-agent`
     reports desired = ready on all nodes.
3. **Pick a low-risk pilot workload** (stateless, non-critical, has clear
   IAM-call telemetry — e.g. CloudTrail entries for `AssumeRoleWithWebIdentity`).
4. **Update the IAM role's trust policy** to additionally trust the
   `pods.eks.amazonaws.com` service principal (template in §3 / [Pod
   Identities concepts][pi-concepts]). Keep the OIDC trust statement.
   - **Gate C:** IAM trust policy validates; existing IRSA pods still get
     credentials (CloudTrail shows `AssumeRoleWithWebIdentity` succeeding).
5. **Create the Pod Identity association** for the pilot
   `(cluster, namespace, service account)` → role ARN. See
   [Pod Identity association docs][pi-association].
   - **Gate D:** `aws eks list-pod-identity-associations` lists the new
     association; the IRSA annotation is still present (intentional).
6. **Restart the pilot workload** (rolling restart). The agent injects
   the new credential provider.
   - **Gate E:** CloudTrail for the workload shows
     `AssumeRoleForPodIdentity` events; no `AccessDenied` errors during
     a full traffic-pattern cycle (≥ 1h or one batch run, whichever is
     longer).
7. **Soak.** Hold for a documented soak window (default: 1 business day
   for stateless, longer for stateful). Monitor IAM error rate and
   workload SLOs.
   - **Gate F:** Error rate within baseline; no rollback events.
8. **Remove the IRSA annotation** on the pilot service account. Restart
   pods to confirm Pod Identity is the only path now.
   - **Gate G:** Pods start cleanly; CloudTrail still shows
     `AssumeRoleForPodIdentity`; no `AssumeRoleWithWebIdentity` calls
     remain for this role.
9. **Roll forward** workload by workload, repeating steps 4–8.
10. **Decommission OIDC trust statements** only after every consumer of
    a given role is on Pod Identity. Leave the cluster OIDC provider in
    place if any other role still relies on it.
    - **Gate H:** No active IRSA service accounts remain for migrated
      roles; trust policies cleaned of OIDC statements where safe.

## 6. Validation Checklist (binary — per workload)

- [ ] **Pod Identity Agent reachable:** the workload's pod can resolve
      `169.254.170.23` (the agent endpoint described in [pi-setup][pi-setup]).
- [ ] **Credentials populated:** the SDK reports a credential provider of
      `ContainerProvider` / `AssumeRoleForPodIdentity`, not
      `WebIdentityCredentialsProvider`.
- [ ] **CloudTrail:** at least one `AssumeRoleForPodIdentity` event in the
      last hour for the workload's role; zero `AccessDenied`.
- [ ] **No regression:** workload SLOs (error rate, p95 latency) within
      baseline.
- [ ] **Annotation cleaned:** `eks.amazonaws.com/role-arn` removed once
      §5 Gate G has passed.

## 7. Rollback

Roll back **immediately** (do not "wait and see") if any of the following
fire during the soak window:

| Trigger | Action |
|---|---|
| `AccessDenied` on the migrated role, sustained > 5 min | Delete the Pod Identity association; pods fall back to IRSA on next restart (annotation still present per §4). |
| Pod Identity Agent DaemonSet unhealthy on > 1 node | Halt the rollout; do not migrate further workloads. |
| Workload SLO breach correlated with cutover | Delete the association; restart pods; investigate before retry. |
| Any cross-account role behaviour differs from IRSA expectation | Stop, review [pi-concepts][pi-concepts], retry only after re-validating trust policy. |

**Rollback action (any trigger):**
`aws eks delete-pod-identity-association --cluster-name … --association-id …`,
then restart pods. Because the IRSA annotation is still on the service
account during steps 5–7, credential resolution falls back to IRSA
automatically per §4.

Do not remove the OIDC trust statement (§5 step 10) until you are
certain you will not need to roll back.

## 8. References

- AWS docs: [Pod Identities (concepts)][pi-concepts] ·
  [Pod Identity Agent setup][pi-setup] ·
  [Pod Identity associations][pi-association] ·
  [IAM Roles for Service Accounts (IRSA)][irsa] ·
  [IAM roles — terms and concepts][iam-roles]
- AWS blog: [Amazon EKS Pod Identity — a new way for applications on EKS to obtain IAM credentials][pi-blog]
- ACMF: [`docs/phases/04-modernize.md`](../phases/04-modernize.md)

[eks-pi]: https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html
[pi-concepts]: https://docs.aws.amazon.com/eks/latest/userguide/pod-id-abstract.html
[pi-setup]: https://docs.aws.amazon.com/eks/latest/userguide/pod-identity-agent-setup.html
[pi-association]: https://docs.aws.amazon.com/eks/latest/userguide/pod-id-association.html
[irsa]: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
[iam-roles]: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_terms-and-concepts.html
[pi-blog]: https://aws.amazon.com/blogs/containers/amazon-eks-pod-identity-a-new-way-for-applications-on-eks-to-obtain-iam-credentials/
