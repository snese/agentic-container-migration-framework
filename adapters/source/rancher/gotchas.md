# Rancher — Known Gotchas

## You are usually pointed at the wrong cluster

Customers run `kubectl` against a *downstream* cluster but Rancher's value-add (Fleet bundles,
cluster templates, RBAC, monitoring) lives on the *management* cluster. Discovery from the
downstream cluster will miss:

- Fleet bundles deployed to *this* cluster (need management-cluster context to enumerate)
- Cluster template (the IaC that defined this cluster's shape)
- Rancher Project membership (downstream sees flat namespaces; Rancher groups them)
- Centralized monitoring data (often shipped to management-cluster Prometheus)

**Detection:** if `cattle-system` exists but no Fleet CRDs, you're on a downstream-only context.

**Fix:** rerun discovery against the management cluster too. Surface this as a `warnings[]` entry.

## RKE → RKE2 migration is its own project

If the customer is on RKE (Docker-based), they should migrate to RKE2 *first*, then to EKS.
Skipping straight from RKE to EKS doubles the change surface. Rancher 2.6+ has tools to
migrate RKE → RKE2 in place; do that first if time allows.

## Longhorn snapshots ≠ EBS snapshots

Longhorn snapshots are stored in-cluster (replicated across nodes). On EKS, EBS snapshots are
stored in S3 (managed by AWS). The retention, restore, and cross-AZ semantics differ:

- Longhorn: snapshot is local to the cluster. Cluster gone = snapshot gone (unless backed up to S3).
- EBS: snapshot survives cluster deletion. Restore to a different AZ is built-in.

**Migration impact:** if customer relies on Longhorn snapshots for DR, the equivalent on AWS is
EBS Snapshot + AWS Backup (cross-region, immutable). Different cost + restore-time-objective
characteristics.

## RKE2's hardened defaults aren't free

RKE2 ships with PSPs / PSA `restricted` enforced + audit logging on. EKS *can* match this but
doesn't by default. If you don't replicate the hardening explicitly, the migrated cluster is
*less* secure than the source.

**Action:** capture RKE2 `--profile=cis-1.23` and similar flags during discovery; mirror to
EKS via Pod Security Admission + audit policy + Karpenter security defaults.

## Fleet's bundle layout is hierarchical

A Fleet `Bundle` deploys to multiple clusters via `targets` selectors. Translating to ArgoCD or
Flux:

- ArgoCD: use `ApplicationSets` with cluster generators — closest fit
- Flux: use `Kustomization` per cluster + `GitRepository` shared — flatter, more files

Translation is mostly mechanical but the cluster-targeting expression must be rewritten.

## RBAC: Project → Namespace

Rancher Projects map multiple namespaces under one RBAC umbrella. EKS doesn't have Projects.
Migration options:

- Flatten — give each namespace its own RBAC (more YAML, simpler model)
- Use Hierarchical Namespace Controller (HNC) — replicates Project-like grouping
- Use a tool like Capsule for multi-tenancy

Most customers flatten. 🚧 Re-evaluate during Phase 2 design.

## K3s embedded etcd vs external datastore

K3s defaults to embedded etcd, but can also use external (PostgreSQL, MySQL, etcd). On EKS the
control plane is fully managed — you don't pick a datastore. Surface the K3s datastore choice
in `warnings[]` so the team knows whether the migration breaks any external-DB-based DR setup.

## Beyond v0.8 scope (true SME items)

- Cluster Template → Terraform/CDK auto-translation (re-author IaC during migration)
- Harvester (HCI) workload extraction (separate from K8s migration scope)
- Rancher Monitoring (Project-scoped Prometheus) → AMP namespace mapping
- Cattle agent + impersonation TLS chain replacement (per-engagement)
