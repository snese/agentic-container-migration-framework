# Config Sync → ArgoCD Migration Playbook

> **Scope.** Methodology-level guidance: when to migrate 1:1, how Anthos Config
> Sync concepts map to ArgoCD, and a numbered sequence with go/no-go gates.
> **Not** a tutorial — every step links to upstream docs for the actual YAML.
> Target length: 1–2 pages.

## 1. Decision — 1:1 migration vs restructure

| Signal in current Config Sync | Recommendation |
|---|---|
| Single root repo, ≤ 3 clusters, no overlays | **1:1** map RootSync → Application |
| RepoSyncs per team / namespace, clear ownership | **1:1** map RepoSync → AppProject + Application(s) |
| ClusterSelector used to fan out across many clusters | **Restructure** to ApplicationSet (cluster generator) |
| Heavy Kustomize overlay tree, env-per-branch | **Restructure** — flatten to ApplicationSet (Git/list generator) |
| Policy Controller constraints in same repo as workload manifests | **Restructure** — split policy repo from app repo |

If two or more "restructure" rows apply, do not attempt a 1:1 migration —
re-design the GitOps repo layout first, then migrate.

## 2. Concept Mapping

| Anthos Config Sync | ArgoCD equivalent | Notes |
|---|---|---|
| `RootSync` (cluster-scoped, syncs whole repo) | `Application` targeting the cluster, or one per top-level dir | Use [Application][argo-app] in `argocd` namespace; `destination.server: https://kubernetes.default.svc` for in-cluster. |
| `RepoSync` (namespace-scoped, syncs subset for a team) | `AppProject` (boundary) + `Application` (workload) | [AppProject][argo-proj] enforces source repo / destination namespace allow-lists, mirroring RepoSync's tenancy guarantees. |
| `ClusterSelector` / `NamespaceSelector` | `ApplicationSet` with cluster or list generator | [ApplicationSet][argo-appset] generators replace selector-driven fan-out. |
| `Policy Controller` (Constraint / ConstraintTemplate, Gatekeeper-based) | OPA Gatekeeper (same CRDs) **or** Kyverno | Constraint/ConstraintTemplate CRDs are upstream Gatekeeper — re-applicable as-is on EKS. See [OPA Gatekeeper][gatekeeper]. |
| Hierarchy Controller (`HierarchyConfiguration`) | Not 1:1 — use ApplicationSet + AppProject + RBAC | Drop unless the hierarchy is load-bearing; most teams over-use it. |
| Sync status (`status.sync.lastUpdate`) | `Application.status.sync.status` + `health.status` | Bind alerts to both fields, not just sync. |

Minimal RootSync → Application sketch (full schema in upstream docs):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: platform-root, namespace: argocd }
spec:
  project: default
  source: { repoURL: <git>, path: <root>, targetRevision: <ref> }
  destination: { server: https://kubernetes.default.svc, namespace: <ns> }
  syncPolicy: { automated: { prune: true, selfHeal: true } }
```

For everything beyond this skeleton (Helm, Kustomize, sync waves, hooks),
follow [ArgoCD Application docs][argo-app] and
[EKS Blueprints add-on for ArgoCD][eks-blueprints].

## 3. Migration Sequence

Each gate is **binary**. If a gate fails, stop and remediate before proceeding.

1. **Inventory.** Export every `RootSync`, `RepoSync`, `ClusterSelector`,
   `Constraint`, `ConstraintTemplate` from the source cluster.
   - **Gate A:** Inventory diff against the source Git repo is empty
     (no drift between live state and Git). If not empty, fix drift in
     Config Sync first — do not migrate drifted state.
2. **Decide layout.** Apply §1 to pick 1:1 vs restructure. Produce a
   target tree (`apps/`, `projects/`, `appsets/`, `policy/`) in a new branch.
   - **Gate B:** Layout reviewed by one engineer who has not seen the
     source repo ("first reader test").
3. **Stand up ArgoCD on the target EKS cluster.** Use
   [EKS Blueprints add-on][eks-blueprints] or the upstream
   [ArgoCD install][argo-install]. Configure SSO, RBAC, and the
   `argocd` AppProject default deny.
   - **Gate C:** `argocd app list` returns empty; SSO login works for
     at least one non-admin role.
4. **Import AppProjects.** Translate each `RepoSync` boundary into an
   [`AppProject`][argo-proj] with `sourceRepos`, `destinations`, and
   `clusterResourceWhitelist` filled from the inventory.
   - **Gate D:** Every project denies a deliberately wrong source repo
     in a dry-run (`argocd app create --dry-run`).
5. **Import Applications / ApplicationSets.** Map per §2. Start with
   `syncPolicy.automated: false` so nothing reconciles yet.
   - **Gate E:** All Applications report `OutOfSync` (expected — nothing
     applied yet) and `Healthy: Missing`. No `Unknown` errors.
6. **Policy migration.** Re-apply existing `ConstraintTemplate` /
   `Constraint` CRDs on EKS via [OPA Gatekeeper][gatekeeper]. If moving
   to Kyverno, translate constraints (manual; out of scope here).
   - **Gate F:** Same constraint count enforced; a known-bad manifest
     is rejected by the new policy engine in a dry-run namespace.
7. **Shadow run.** Point ArgoCD at the same Git repo Config Sync uses,
   but keep `automated: false`. Run `argocd app diff` for every app.
   - **Gate G:** Diffs are empty or only contain ArgoCD-managed
     annotations / `last-applied` metadata. Any real diff means the
     mapping is wrong — return to step 4.
8. **Cutover, app by app.** For each Application:
   1. Pause Config Sync for the namespace (`spec.pause: true` on the
      RootSync/RepoSync).
   2. Enable ArgoCD `automated: { prune: true, selfHeal: true }`.
   3. Verify §4 checklist for that app before moving to the next.
   - **Gate H (per app):** §4 passes.
9. **Decommission Config Sync.** Once all apps pass Gate H and have
   soaked for at least one business day, remove Config Sync operator.
   - **Gate I:** `kubectl get rootsync,reposync -A` returns nothing;
     no controller pods remain.

## 4. Validation Checklist (binary)

- [ ] **Sync status:** `Application.status.sync.status == Synced` for every app.
- [ ] **Health:** `Application.status.health.status == Healthy` for every app.
- [ ] **Drift detection:** modify a managed resource by hand → ArgoCD
      reverts within one self-heal interval.
- [ ] **Policy enforcement:** a manifest violating a migrated Constraint
      is rejected at admission (Gatekeeper denial event observed).
- [ ] **RBAC:** non-admin user cannot create an Application outside their
      AppProject's allow-list (verify with a deliberately wrong source).
- [ ] **Observability:** alerts bound to both `sync.status` and
      `health.status`, not just sync.
- [ ] **No Config Sync remnants:** Gate I above.

## 5. References

- ArgoCD [Application][argo-app] · [AppProject][argo-proj] ·
  [ApplicationSet][argo-appset] · [install][argo-install] ·
  [getting started][argo-getstarted]
- [OPA Gatekeeper][gatekeeper]
- [EKS Blueprints — ArgoCD add-on][eks-blueprints]
- ACMF: [`docs/decisions/ecs-vs-eks.md`](../decisions/ecs-vs-eks.md) — when EKS
  is even the right target for a Config-Sync-managed cluster.

[argo-app]: https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#applications
[argo-proj]: https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#projects
[argo-appset]: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
[argo-install]: https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/
[argo-getstarted]: https://argo-cd.readthedocs.io/en/stable/getting_started/
[gatekeeper]: https://open-policy-agent.github.io/gatekeeper/website/docs/
[eks-blueprints]: https://aws-quickstart.github.io/cdk-eks-blueprints/addons/argo-cd/
