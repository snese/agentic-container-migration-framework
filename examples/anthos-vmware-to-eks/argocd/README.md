# ArgoCD bootstrap for the migration target

> Drop-in starter that follows the layout from
> [`docs/playbooks/config-sync-to-argocd.md`](../../../docs/playbooks/config-sync-to-argocd.md) §2.
> Each Anthos `RootSync` becomes an Application; each per-team `RepoSync`
> becomes an `AppProject`. The single example below uses an `ApplicationSet`
> with a list generator — appropriate when the namespace tree is small.

## `appproject.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: acme-prod
  namespace: argocd
spec:
  description: Acme prod migration scope (payments / checkout / inventory)
  sourceRepos:
    - https://github.com/acme/migration-target.git
  destinations:
    - { server: https://kubernetes.default.svc, namespace: payments }
    - { server: https://kubernetes.default.svc, namespace: checkout }
    - { server: https://kubernetes.default.svc, namespace: inventory }
  clusterResourceWhitelist:
    - { group: '',                     kind: Namespace }
    - { group: storage.k8s.io,         kind: StorageClass }
    - { group: networking.k8s.io,      kind: NetworkPolicy }
  namespaceResourceWhitelist:
    - { group: '*', kind: '*' }
```

## `applicationset.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: acme-migration
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - { ns: payments,  path: examples/anthos-vmware-to-eks/manifests/after/payments }
          - { ns: checkout,  path: examples/anthos-vmware-to-eks/manifests/after/checkout }
          - { ns: inventory, path: examples/anthos-vmware-to-eks/manifests/after/inventory }
  template:
    metadata:
      name: '{{ns}}-app'
    spec:
      project: acme-prod
      source:
        repoURL: https://github.com/acme/migration-target.git
        targetRevision: main
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{ns}}'
      # IMPORTANT — start with automated sync OFF until shadow / diff is clean.
      # Flip to `automated: { prune: true, selfHeal: true }` per §3 step 8 in
      # config-sync-to-argocd.md, app by app, after Gate G.
      syncPolicy:
        automated: null
        syncOptions:
          - CreateNamespace=true
          - ApplyOutOfSyncOnly=true
```

## Sync wave order (recommended)

ArgoCD `argocd.argoproj.io/sync-wave` annotations on the manifests:

| Wave | Resource type | Why |
|---|---|---|
| -2 | Namespaces, ConstraintTemplates, StorageClasses | Cluster scaffolding first |
| -1 | ServiceAccounts (with IRSA / Pod Identity association ready) | Identity before workloads |
| 0  | Services, ConfigMaps | Plumbing for workloads |
| 1  | Deployments, StatefulSets | Workloads |
| 2  | Ingresses, Istio VirtualServices | Traffic surface last |

## Validation

After the ApplicationSet is created with `automated: null`, every Application
should report `OutOfSync / Missing` — that is the expected state per
config-sync-to-argocd.md §3 Gate E. Run `argocd app diff <app>` and confirm
diffs only contain ArgoCD-managed annotations / `last-applied` metadata
before flipping to `automated`.
