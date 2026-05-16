# Phase 1: Assess

**MAP alignment:** AWS MAP — *Assess*.

**Goal:** Build a complete, structured picture of the source environment *and* the customer's organizational readiness — without installing persistent agents.

This phase combines what v0.1 called "Discover" with the Migration Readiness Assessment (MRA) dimensions from MAP. Discovery without readiness is a manifest dump; readiness without discovery is a survey nobody trusts.

## Inputs

- Customer access agreement (which discovery option, what scope)
- Network connectivity decision (online vs air-gapped)
- Cluster inventory (rough — names, regions, sizes)
- Stakeholder list (sponsor, platform lead, app owners, security, finance)

## A. Technical discovery

### Discovery options

Pick one based on customer constraints. See [`docs/discovery/`](../discovery/) for details.

| Option | Intrusiveness | Best for |
|---|---|---|
| 1. Manifest-only | Lowest | Strict policy / IP-sensitive |
| 2. Self-export script | Low | Air-gapped, audit-heavy |
| 3. Read-only creds | Medium | Trusted, online |
| 4. **Kiro CLI ephemeral** | Medium-low | Default recommended |
| 5. Strands Agent | Higher | Ongoing optimization only |

### Kiro CLI ephemeral run (recommended path)

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

## B. Migration Readiness Assessment (MRA)

The MRA captures readiness across the dimensions MAP cares about. ACMF scores each on a 1–4 scale (Initial / Developing / Defined / Optimized) with concrete evidence per score.

### Business readiness

- Executive sponsorship in place and active
- Business case drafted, with TCO + value KPIs
- Funding model agreed (incl. AWS MAP funding mapping if applicable)
- Success criteria explicit and measurable
- Cross-references → [`caf-perspectives/business.md`](../methodology/caf-perspectives/business.md)

### People readiness

- Skills gap matrix completed for platform & app teams
- Training plan exists and is funded
- On-call / operating model for the AWS target named
- Cross-references → [`caf-perspectives/people.md`](../methodology/caf-perspectives/people.md)

### Governance readiness

- CCoE / migration program structure exists
- Tagging / labeling standard agreed
- Risk register and change-control process defined
- Cost guardrails (budgets, anomaly detection) planned
- Cross-references → [`caf-perspectives/governance.md`](../methodology/caf-perspectives/governance.md)

### Platform / Security / Operations readiness

Captured here at a high level; deepened in Phase 2 (Mobilize). At Assess we just want to know if there are *blockers* (e.g. no AWS landing zone exists at all, security team hasn't approved a target pattern, no observability strategy).

## Outputs

- **`discovery-bundle.json`** — schema in [`schemas/discovery-bundle.schema.json`](../../schemas/discovery-bundle.schema.json).
- **`readiness-scorecard.md`** — MRA scores with evidence per dimension.
- **`readiness-gaps.md`** — list of must-close gaps before Mobilize can start.

## Exit Criteria

- [ ] All in-scope clusters inventoried
- [ ] All workloads classified (stateful / stateless / batch / system)
- [ ] All external dependencies enumerated
- [ ] Bundle validates against schema
- [ ] MRA scorecard completed across business / people / governance / platform / security / operations
- [ ] Top readiness gaps have named owners and target close dates
- [ ] Customer signs off on scope completeness and readiness baseline
