# Agentic Container Migration Framework (ACMF)

> Agent-driven methodology for migrating container workloads from on-premises / hybrid platforms (Anthos, OpenShift, Rancher, vanilla K8s) to AWS (EKS, ECS, App Runner).

**Status:** v0.8 — Phase 1 (Assess) discovery scripts complete for all 6 source platforms. Anthos on VMware → AWS remains the reference scenario for end-to-end Phase 2/3 work.

## Why "Agentic"?

Traditional migration frameworks (AWS MAP, App2Container, MGN) assume:
- You can install a long-running agent in the customer environment, **or**
- The workload is VM-based, **or**
- A consultant runs scripts manually.

Container workloads — especially in regulated, air-gapped, or customer-sensitive environments — need a different shape:

| Traditional | ACMF |
|---|---|
| Persistent agent (App2Container, ATX) | Ephemeral agent run (Kiro CLI) |
| VM-centric tooling | Container/K8s-native |
| Manual discovery scripts | LLM-assisted analysis with auditable prompts |
| One-shot lift-and-shift | Decision-tree-based target selection (EKS vs ECS vs App Runner) |

ACMF uses **agents as the execution layer** — but agents that are *short-lived, customer-controlled, and auditable*.

## AWS MAP & CAF alignment

ACMF is designed to plug into customer engagements that already speak AWS [Migration Acceleration Program (MAP)](https://aws.amazon.com/migration-acceleration-program/) and [Cloud Adoption Framework (CAF)](https://aws.amazon.com/cloud-adoption-framework/) — not to replace them.

- **Phases** map to MAP's *Assess / Mobilize / Migrate & Modernize*.
- **Deliverables** cover all six AWS CAF perspectives (Business / People / Governance / Platform / Security / Operations).
- **Where ACMF extends MAP:** container-native 7 Rs, agentic discovery for hybrid / air-gapped sources, first-class support for non-AWS source platforms (Anthos, OpenShift, Rancher).

Full mapping: [`docs/methodology/00-overview.md`](docs/methodology/00-overview.md). Non-negotiable principles: [`docs/CONSTITUTION.md`](docs/CONSTITUTION.md).

## Framework Phases

```
Phase 1: Assess     →  Phase 2: Mobilize  →  Phase 3: Migrate
  (discovery + MRA)     (plan + landing zone)   (wave cutovers)
        ↓                       ↓                     ↓
                       Phase 4: Modernize  →  Phase 5: Document
                       (optimize + refactor)   (case study)
```

Detailed phase docs: see [`docs/phases/`](docs/phases/). Methodology layer (CAF perspectives, 7 Rs for containers): see [`docs/methodology/`](docs/methodology/).

## Source / Target Matrix

| Source ↓ / Target → | EKS | ECS (Fargate) | App Runner |
|---|---|---|---|
| **Anthos on VMware** ⭐ | ✅ Primary | ✅ Selective | ⚠️ Stateless only |
| **Anthos on GCP** (GKE) | ✅ Primary | ✅ Selective | ⚠️ Stateless only |
| **Anthos on Bare Metal** | ✅ v0.8 (HW workloads need SME) | ⚠️ Stateless only | ⚠️ Single-service only |
| **OpenShift** (OCP 4.x) | ✅ v0.8 (operator rating built-in) | ⚠️ Stateless only | — |
| **Rancher** (RKE / RKE2 / K3s) | ✅ v0.8 | ⚠️ Stateless only | ⚠️ Stateless only |
| **Vanilla / self-managed K8s** | ✅ v0.8 | ⚠️ Stateless only | ⚠️ Stateless only |

✅ = Phase 1 (Assess) discovery complete · ⚠️ = with caveats · "needs SME" = some sub-domain still requires expert review (KubeVirt extraction, BMC inventory, custom Operator rating)

Each source has a dedicated adapter under [`adapters/source/<platform>/`](adapters/source/) with
README + mapping table + gotchas + Kiro CLI discovery prompt + offline fixtures.

## Non-Intrusive Discovery Options

ACMF deliberately avoids deploying long-running agents. Discovery options, ordered by intrusiveness:

1. **Manifest-only** — customer ships Helm charts / Anthos Config Sync repo; we analyze offline.
2. **Self-export script** — pure bash + `kubectl` / `gcloud` read-only commands, output JSON bundle.
3. **Read-only credentials** — short-lived ServiceAccount, we run discovery from our env.
4. **Kiro CLI ephemeral run** ⭐ — customer runs `kiro` with our prompt + read-only tool allowlist; produces structured output bundle.
5. **Strands Agent (opt-in)** — only for ongoing optimization phase, not discovery.

See [`docs/discovery/`](docs/discovery/) for each option's prompts, scripts, and threat model.

## ECS vs EKS Decision Tree

```
Anthos workload characteristics
├─ Heavy K8s API usage (CRDs, operators, service mesh)? ─→ EKS
├─ Stateful + complex networking? ───────────────────────→ EKS
├─ Stateless + minimize ops + cost-sensitive? ───────────→ ECS (Fargate)
├─ Single-service HTTP app? ─────────────────────────────→ App Runner
└─ Mixed portfolio? ─────────────────────────────────────→ Hybrid (EKS + ECS by namespace)
```

Full decision matrix in [`docs/decisions/ecs-vs-eks.md`](docs/decisions/ecs-vs-eks.md).

## Repository Structure

```
.
├── README.md                       # This file
├── docs/
│   ├── CONSTITUTION.md             # Framework principles (amendment process)
│   ├── methodology/                # MAP/CAF alignment, 7Rs for containers
│   ├── phases/                     # MAP-aligned 5-phase playbooks
│   ├── discovery/                  # Discovery option specs
│   ├── decisions/                  # Decision trees / ADRs
│   └── case-studies/               # Real customer stories (anonymized)
├── adapters/
│   ├── source/
│   │   ├── anthos-vmware/          # ✅ v0.8 Reference
│   │   ├── anthos-gcp/             # ✅ v0.8
│   │   ├── anthos-baremetal/       # ✅ v0.8
│   │   ├── openshift/              # ✅ v0.8
│   │   ├── rancher/                # ✅ v0.8
│   │   ├── vanilla-k8s/            # ✅ v0.8 (catch-all)
│   │   └── _template/              # How to add a new source
│   └── target/
│       ├── eks/
│       ├── ecs-fargate/
│       └── app-runner/
├── prompts/
│   └── discovery/                  # Kiro CLI discovery prompts (one per source)
├── schemas/
│   └── discovery-bundle.schema.json  # Phase 1 output schema (v1.1.0)
├── scripts/
│   └── discovery/                  # Self-export scripts + simulator + validator
└── examples/                       # End-to-end walkthroughs
```

## Phase 1 testing — discovery scripts & fixtures

Every source adapter ships with **two fixtures** under
`adapters/source/<platform>/fixtures/`:

| Fixture | Shape |
|---|---|
| `<platform>-small.json` | 1 cluster, ~10 services, monolithic-ish |
| `<platform>-realistic.json` | 2 clusters, 50+ services, mesh + stateful + custom CRDs |

You can exercise the Phase 1 layer end-to-end without touching a real cluster:

```bash
# 1. Dry-run any platform's export script — produces a schema-valid stub
scripts/discovery/anthos-vmware-export.sh --dry-run --output /tmp/v.json

# 2. Generate a fake-but-realistic bundle from a fixture
scripts/discovery/simulate-discovery.sh openshift --size realistic \
    --output /tmp/openshift.json

# 3. Validate against the schema
scripts/discovery/validate-bundle.sh /tmp/v.json /tmp/openshift.json

# 4. Or validate ALL committed fixtures at once
scripts/discovery/validate-bundle.sh --all-fixtures
```

Validator dependency: `python3` + `jsonschema` (Debian/Ubuntu:
`sudo apt-get install python3-jsonschema`; pip: `pip install jsonschema`).

## Getting Started

**Phase 1 (Assess) tooling is ready** for all 6 source platforms — run the self-export script for your platform (see the Quick Start above), validate the bundle against the schema, then follow [`docs/phases/01-assess.md`](docs/phases/01-assess.md) to interpret the results. Phases 2–5 (Mobilize → Document) currently follow the manual playbooks under [`docs/phases/`](docs/phases/); target-adapter tooling (EKS / ECS Fargate) is on the roadmap below.

## Roadmap

- [x] Repo skeleton
- [x] Anthos-on-VMware discovery prompt + schema
- [x] All 6 source adapters (anthos-vmware ⭐, anthos-gcp, anthos-baremetal, openshift, rancher, vanilla-k8s)
- [x] Self-export scripts + dry-run mode + simulator + validator (v0.7)
- [x] **v0.8: Phase 1 Assess complete for all 6 platforms** — schema 1.1.0, OpenShift Operator→AWS rating table (easy/hard/blocker), SCC effective bindings, ROSA detection, Workload Identity bindings, Config Connector probe, hardware-bound workload mining, Rancher distro/server-version + management-cluster classification, vanilla-k8s CNI + admission webhooks + kubelet skew, vSphere CSI PV count
- [ ] EKS target adapter (ADRs, IaC patterns)
- [ ] ECS Fargate target adapter
- [ ] First case study (Anthos → EKS)
- [ ] Kiro CLI integration guide
- [ ] SME tasks remaining (per-engagement): KubeVirt extraction, BMC/Redfish inventory, Operators not in rating table, GKE Sandbox triage, Cluster Templates → IaC re-author

## License

TBD (private during development).

## Contact

Hung-Che Lo · `hclo@snese.net`
