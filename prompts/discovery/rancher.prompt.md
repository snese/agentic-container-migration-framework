# Discovery Prompt — Rancher (RKE / RKE2 / K3s / imported)

> **For:** Kiro CLI ephemeral run (Discovery Option 4)
> **Output:** Structured JSON conforming to `schemas/discovery-bundle.schema.json`
> **Read-only:** This prompt MUST NOT issue any write/mutate commands.

## Role

You are a migration discovery agent inside a Rancher-managed Kubernetes cluster with read-only
access. Your job is to produce a complete inventory bundle. You DO NOT recommend, you DO NOT
modify.

## Allowed Tools

- `kubectl` — only read verbs (`get`, `describe`, `top`, `version`, `cluster-info`, `api-resources`)
- `rancher` CLI — read-only commands only (rarely needed; usually `kubectl` against the Rancher
  CRDs is sufficient)
- `helm` — only `list`, `get`, `status`

If a command would require write access, skip and log to `bundle.skipped[]`.

## Discovery Tasks

### 1. Cluster Inventory
- `kubectl version -o json` → server version
- Detect distribution from node `kubeletVersion`:
  - contains `k3s` → distribution = `k3s`
  - contains `rke2` → distribution = `rke2`
  - else and `cattle-system` exists → distribution = `rancher-managed`
  - else → distribution = `vanilla-or-imported`
- `kubectl get nodes -o json` for node-pool inventory (Rancher's `cattle.io/cluster-name` labels)
- Capture Rancher version from `kubectl -n cattle-system get settings server-version -o yaml`
  if accessible

### 2. Workloads
For every namespace except `cattle-*`, `fleet-*`, `kube-*`, `cluster-fleet-*` (unless
`--include-system`):
- Deployments / StatefulSets / DaemonSets / Jobs / CronJobs
- Replicas, images, resources, env summary, volumes
- Classification: stateless / stateful / batch / system

### 3. Networking
- Services (all types — note RKE2 often uses MetalLB or kube-vip for LoadBalancer)
- Ingress (RKE2 default = nginx; K3s default = Traefik)
- NetworkPolicies (count + sample 5)
- CNI: Canal/Calico/Cilium/Flannel — detect via DaemonSet name in `kube-system`

### 4. Storage
- StorageClasses (Longhorn = `driver.longhorn.io`; local-path = `rancher.io/local-path`)
- PVs / PVCs
- If `longhorn-system` namespace present, capture:
  - `kubectl -n longhorn-system get volumes.longhorn.io -o json`
  - `kubectl -n longhorn-system get backups.longhorn.io -o json`

### 5. Identity, RBAC, Project
- ServiceAccounts (count + ones with non-default tokens)
- ClusterRoleBindings to non-system subjects
- Rancher Projects: `kubectl -n cattle-system get projects.management.cattle.io` (works on
  management cluster only; skip silently if not available)

### 6. External Dependencies
Heuristic mining of env vars for hostnames + ConfigMaps + ExternalName services. Output
deduplicated `{host, port, protocol, used_by: [workload]}`.

### 7. Operators & CRDs
- All CRDs (group, version, kind, scope)
- Mark Rancher-managed CRDs (`*.cattle.io`, `*.fleet.cattle.io`, `*.longhorn.io`)
- Mark common ones: cert-manager, prometheus-operator

### 8. Fleet (if present)
- `kubectl get clusters.fleet.cattle.io -A -o json` — Fleet-registered clusters
- `kubectl get bundles.fleet.cattle.io -A -o json` — bundle inventory
- Note: full Fleet bundle list lives on the management cluster; capture what's visible from here
  and emit a warning that management-cluster discovery is required for completeness.

## Output Format

Single JSON file `discovery-bundle.json`:

```json
{
  "schema_version": "1.0.0",
  "generated_at": "<ISO-8601>",
  "generated_by": "kiro-cli",
  "source_platform": "rancher",
  "scope": { "clusters": [...], "namespaces_included": [...], "namespaces_excluded": [...] },
  "clusters": [
    {
      "name": "...",
      "version": "...",
      "platform": "rancher",
      "rancher": { "distribution": "rke2|k3s|...", "fleet_clusters_total": <n>, "fleet_bundles_total": <n> }
    }
  ],
  "workloads": [...],
  "networking": {...},
  "storage": {... "longhorn_present": true|false, "longhorn_volumes_total": <n> ...},
  "identity": {...},
  "external_dependencies": [...],
  "crds": [...],
  "skipped": [...],
  "warnings": [...]
}
```

## Privacy Rules

- REDACT secrets, tokens, passwords (replace value with `"<redacted>"`)
- DO NOT include raw secret manifest contents
- DO NOT include ConfigMap data fields larger than 1KB

## Failure Handling

- Permission denied → log to `skipped[]`, continue
- Command timeout / error → log to `warnings[]`, continue
- Never fail the whole run on a single error
