# Agentic Container Migration Framework (ACMF)

> Agent-driven methodology for migrating container workloads from on-premises / hybrid platforms (Anthos, OpenShift, Rancher, vanilla K8s) to AWS (EKS, ECS, App Runner).

**Status:** 🚧 Early draft — Anthos on VMware → AWS as the first reference scenario.

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

## Framework Phases

```
Phase 1: Discover    →  Phase 2: Assess    →  Phase 3: Plan
   (agent-driven)        (LLM analysis)        (target mapping)
       ↓                       ↓                     ↓
Phase 4: Migrate     →  Phase 5: Optimize  →  Phase 6: Document
   (IaC + cutover)       (cost / SRE)          (case study)
```

Detailed phase docs: see [`docs/phases/`](docs/phases/).

## Source / Target Matrix

| Source ↓ / Target → | EKS | ECS (Fargate) | App Runner |
|---|---|---|---|
| **Anthos on VMware** | ✅ Primary | ✅ Selective | ⚠️ Stateless only |
| **Anthos on GCP** | 🔜 | 🔜 | 🔜 |
| **OpenShift** | 🔜 | 🔜 | — |
| **Rancher / vanilla K8s** | 🔜 | 🔜 | 🔜 |

✅ = supported · 🔜 = planned · ⚠️ = with caveats

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
│   ├── phases/                     # Phase 1-6 detailed playbooks
│   ├── discovery/                  # Discovery option specs
│   ├── decisions/                  # Decision trees / ADRs
│   └── case-studies/               # Real customer stories (anonymized)
├── adapters/
│   ├── source/
│   │   ├── anthos-vmware/          # First reference adapter
│   │   ├── anthos-gcp/             # Planned
│   │   ├── openshift/              # Planned
│   │   └── _template/              # How to add a new source
│   └── target/
│       ├── eks/
│       ├── ecs-fargate/
│       └── app-runner/
├── prompts/                        # Kiro CLI prompts (discovery, analysis, planning)
├── schemas/                        # JSON schemas for inter-phase artifacts
├── scripts/                        # Self-export bash scripts
└── examples/                       # End-to-end walkthroughs
```

## Getting Started

> 🚧 Tooling is still being built. For now, see [`docs/phases/01-discover.md`](docs/phases/01-discover.md) for the manual flow.

## Roadmap

- [x] Repo skeleton
- [ ] Anthos-on-VMware discovery prompt + schema
- [ ] EKS target adapter (ADRs, IaC patterns)
- [ ] ECS Fargate target adapter
- [ ] First case study (Anthos → EKS)
- [ ] Kiro CLI integration guide
- [ ] OpenShift adapter

## License

TBD (private during development).

## Contact

Hung-Che Lo · `hclo@snese.net`
