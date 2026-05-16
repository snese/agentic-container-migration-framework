# Phase 1: Discover

**Goal:** Build a complete, structured picture of the source environment — *without* installing persistent agents.

## Inputs

- Customer access agreement (which discovery option, what scope)
- Network connectivity decision (online vs air-gapped)
- Cluster inventory (rough — names, regions, sizes)

## Discovery Options

Pick one based on customer constraints. See [`docs/discovery/`](../discovery/) for details.

| Option | Intrusiveness | Best for |
|---|---|---|
| 1. Manifest-only | Lowest | Strict policy / IP-sensitive |
| 2. Self-export script | Low | Air-gapped, audit-heavy |
| 3. Read-only creds | Medium | Trusted, online |
| 4. **Kiro CLI ephemeral** | Medium-low | Default recommended |
| 5. Strands Agent | Higher | Ongoing optimization only |

## Activities

### 4a. Kiro CLI ephemeral run (recommended path)

1. Customer installs `kiro` CLI (one-time, can be uninstalled after).
2. We provide:
   - `prompts/discovery/anthos-vmware.prompt.md`
   - Tool allowlist: `kubectl` (read-only), `gcloud` (read-only), `vmware-govc` (read-only)
3. Customer runs:
   ```bash
   kiro \
     --prompt-file prompts/discovery/anthos-vmware.prompt.md \
     --tools-allow kubectl,gcloud,govc \
     --output discovery-bundle.json
   ```
4. Bundle is encrypted and shared via agreed channel.

### Discovery scope (what we collect)

- **Cluster topology** — control plane, node pools, versions
- **Workloads** — Deployments, StatefulSets, DaemonSets, CronJobs
- **Networking** — Services, Ingress, NetworkPolicies, service mesh config
- **Storage** — PVs, PVCs, StorageClasses, CSI drivers
- **Identity** — ServiceAccounts, RBAC, Workload Identity bindings
- **Dependencies** — external services (DBs, queues, APIs), egress patterns
- **Operators / CRDs** — non-standard K8s extensions
- **Anthos-specific** — Config Sync repos, Policy Controller, Service Mesh
- **VMware layer** — vCenter inventory (if relevant for capacity planning)

## Outputs

**`discovery-bundle.json`** — schema in [`schemas/discovery-bundle.schema.json`](../../schemas/discovery-bundle.schema.json).

## Exit Criteria

- [ ] All in-scope clusters inventoried
- [ ] All workloads classified (stateful / stateless / batch / system)
- [ ] All external dependencies enumerated
- [ ] Bundle validates against schema
- [ ] Customer signs off on scope completeness
