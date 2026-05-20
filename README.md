# Agentic Container Migration Framework (ACMF)

> Cut the repetitive parts of a Kubernetes-to-AWS migration — discovery, manifest analysis, wave planning — from days to hours, with auditable AI agents that run in the customer’s environment under the customer’s control.

**Container migrations don’t have to be quarter-long swamps.** ACMF is a methodology that uses *ephemeral* AI agents (not persistent collectors) to compress the assessment-and-planning grind that historically takes a senior architect 5–10 days into a 1–2 hour structured run, with every prompt, tool call, and output under version control[^1].

It is opinionated about three things: **non-intrusive by default**, **agent-driven but human-judged**, and **MAP/CAF-aligned** — so it slots into AWS engagements that already speak the standard language.

[^1]: Internal benchmark on multi-cluster GKE Enterprise on VMware engagements (≈100–200 workloads). Manual, SA-led discovery and manifest analysis runs 5–10 working days; the same scope on Discovery Option 4 (agent-assisted, see below) typically completes in 1–2 hours of agent runtime plus human review. Customer-specific results vary; ACMF surfaces a per-engagement baseline as an Assess-phase artifact rather than a marketing claim.

**Status:** 🚧 v0.6 draft — GKE Enterprise on VMware → AWS as the first reference scenario. See [ROADMAP.md](./ROADMAP.md).

## Why “Agentic”?

**Traditional AWS migration tooling — App2Container, AWS MGN, and Migration Evaluator** — assumes one of:
- You can install a long-running agent in the customer environment, **or**
- The workload is VM-based, **or**
- A consultant runs scripts manually.

These work well for VM-shaped estates. They are a poor fit for K8s-native, regulated, or customer-controlled container workloads.

Container workloads — especially in regulated, air-gapped, or customer-sensitive environments — need a different shape:

| Traditional | ACMF |
|---|---|
| Persistent agent (App2Container, MGN replication agent) | Ephemeral agent run |
| VM-centric tooling | Container/K8s-native |
| Manual discovery scripts | LLM-assisted analysis with auditable prompts |
| One-shot lift-and-shift | Decision-tree-based target selection (EKS vs ECS) |

ACMF uses **agents as the execution layer** — but agents that are *short-lived, customer-controlled, and auditable*.

## AWS MAP & CAF alignment

ACMF is designed to plug into customer engagements that already speak AWS [Migration Acceleration Program (MAP)](https://aws.amazon.com/migration-acceleration-program/) and [Cloud Adoption Framework (CAF)](https://aws.amazon.com/cloud-adoption-framework/) — not to replace them.

- **Phases** map to MAP’s *Assess / Mobilize / Migrate & Modernize*.
- **Deliverables** cover all six AWS CAF perspectives (Business / People / Governance / Platform / Security / Operations).
- **Where ACMF extends MAP:** container-native 7 Rs, agentic discovery for hybrid / air-gapped sources, **first-class target adapters for EKS and ECS Fargate**. Non-AWS source adapters currently include GKE Enterprise on VMware (reference implementation); GKE, AKS, OpenShift, and Rancher / vanilla K8s are on the [roadmap](./ROADMAP.md).
- **Relationship to MAP's bundled discovery tooling:** ACMF complements (does not replace) [App2Container](https://docs.aws.amazon.com/app2container/latest/UserGuide/what-is-a2c.html), [AWS MGN](https://docs.aws.amazon.com/mgn/latest/ug/what-is-application-migration-service.html), and [AWS Migration Evaluator](https://aws.amazon.com/migration-evaluator/) — each of which is an AWS-native service rather than a partner tool. ACMF picks up where these stop: container/Kubernetes-native discovery for sources those tools don't cover (GKE Enterprise, GKE, AKS, OpenShift, Rancher).

Full mapping: [`docs/methodology/00-overview.md`](docs/methodology/00-overview.md). Non-negotiable principles: [`docs/CONSTITUTION.md`](docs/CONSTITUTION.md). For the relationship with [AWS Transform](https://aws.amazon.com/transform/), see [`docs/decisions/aws-transform-vs-acmf.md`](docs/decisions/aws-transform-vs-acmf.md).

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

| Source ↓ / Target → | EKS | ECS (Fargate) |
|---|---|---|
| **GKE Enterprise on VMware** (formerly Anthos) | ✅ Primary | ✅ Selective |
| **GKE Enterprise on Bare Metal** (formerly Anthos) | ✅ Shares VMware adapter | ✅ Selective |
| **GKE** (cloud-native, on GCP) | 🔜 | 🔜 |
| **AKS** (Azure Kubernetes Service) | 🔜 | 🔜 |
| **OpenShift** | 🔜 | 🔜 |
| **Rancher / vanilla K8s** | 🔜 | 🔜 |

✅ = supported · 🔜 = planned (see [ROADMAP.md](./ROADMAP.md))

> **Google product family clarification:**
> - **GKE** = Cloud-native managed Kubernetes on GCP (standard or Autopilot mode)
> - **GKE Enterprise** = Pure-software multi-cluster/hybrid management platform (formerly Anthos). Runs on VMware, Bare Metal, AWS, or Azure — customer owns hardware
> - **GDC (Google Distributed Cloud)** = Hardware + software bundle; Google ships and maintains physical racks at customer site. Air-gapped/sovereignty/edge use cases
>
> ACMF primarily targets **GKE Enterprise** (on VMware/Bare Metal) migrations, which represent the vast majority of “Anthos to AWS” customer scenarios.

> Deprecated targets (e.g. AWS App Runner — maintenance mode 2026-04-30) are tracked in [ROADMAP.md](./ROADMAP.md).

## Non-Intrusive Discovery Options

ACMF deliberately avoids deploying long-running agents. Discovery options, ordered by intrusiveness:

1. **Manifest-only** — customer ships Helm charts / Config Sync repo; we analyze offline.
2. **Self-export script** — pure bash + `kubectl` / `gcloud` read-only commands, output JSON bundle.
3. **Read-only credentials** — short-lived ServiceAccount, we run discovery from our env.
4. **Agent-assisted ephemeral run** ⭐ — customer runs a coding-agent CLI ([Kiro CLI](https://kiro.dev/docs/cli/installation/), in [headless mode](https://kiro.dev/docs/cli/headless/), is the reference) with our prompt + read-only tool allowlist; produces a structured JSON output bundle.
5. **Persistent agent runtime (opt-in)** — only for ongoing Phase 4 (Modernize) optimization, not discovery. *Placeholder — no reference recipe ships in ACMF today;* see [ROADMAP.md](./ROADMAP.md) Phase 4. Reference runtime: [Strands Agents SDK](https://strandsagents.com/) (open source, [GitHub](https://github.com/strands-agents/sdk-python)).

If the agent CLI cannot be installed in the customer environment, **Option 4 degrades cleanly to Option 2** — the same prompt is consumable as a Bash/Python runbook with no agent runtime required. See [`docs/prerequisites.md`](docs/prerequisites.md) for tool versions, install paths, and fallback procedures.

See [`docs/discovery/`](docs/discovery/) for each option’s prompts, scripts, and threat model.

## ECS vs EKS Decision Tree

The top-level question is binary: **do you need the Kubernetes API?**

```
Does the workload depend on the Kubernetes API
(CRDs, operators, admission webhooks, service mesh CRs)?
├─ Yes ─────────────────────────────────────────────────→ EKS
├─ No, and ops simplicity / cost > flexibility ─────────→ ECS
└─ Mixed portfolio? ────────────────────────────────────→ Hybrid (EKS + ECS, split by namespace)
```

Compute-model selection (Fargate vs EC2 vs Auto Mode vs Karpenter vs Managed Node Groups vs Fargate profiles) is a separate, target-specific decision. See:

- High-level ECS vs EKS: [`docs/decisions/ecs-vs-eks.md`](docs/decisions/ecs-vs-eks.md)
- ECS compute model (Fargate vs EC2 vs Fargate Spot): [`docs/decisions/ecs-compute-model.md`](docs/decisions/ecs-compute-model.md)
- EKS compute model (Auto Mode vs Karpenter vs Managed NG vs Fargate profiles): [`docs/decisions/eks-compute-model.md`](docs/decisions/eks-compute-model.md)

## Repository Structure

```
.
├── README.md                              # This file
├── ROADMAP.md                             # Planned items, by phase
├── CONTRIBUTING.md                        # How to contribute
├── docs/
│   ├── CONSTITUTION.md                    # Framework principles (amendment process)
│   ├── prerequisites.md                   # Tool versions, install paths, fallbacks
│   ├── methodology/                       # MAP/CAF alignment, 7Rs for containers
│   ├── phases/                            # MAP-aligned 5-phase playbooks
│   ├── discovery/                         # Discovery option specs (incl. MCP augmentation)
│   ├── decisions/                         # Decision trees / ADRs
│   ├── playbooks/                         # Phase 4 modernize playbooks
│   ├── architecture/                      # Reference diagrams
│   ├── customer-facing/                   # 1-pager, pitch guide, FAQ
│   └── case-studies/                      # Real customer stories (anonymized)
├── adapters/
│   ├── source/
│   │   ├── gke-enterprise-vmware/         # First reference adapter (formerly Anthos)
│   │   └── _template/                     # How to add a new source
│   └── target/
│       ├── eks/
│       └── ecs-fargate/
├── prompts/                               # Discovery / analysis / planning prompts
├── schemas/                               # JSON schemas for inter-phase artifacts
├── scripts/                               # Self-export bash scripts (per source adapter)
├── tests/                                 # Schema-contract and smoke tests
├── templates/                             # Engagement document templates
└── examples/                              # End-to-end walkthroughs
```

Planned source adapters (see [ROADMAP.md](./ROADMAP.md)) will land under `adapters/source/` with these directory names: `gke/`, `aks/`, `openshift/`, `rancher/`. Deprecated adapters (e.g. App Runner, see ROADMAP) live under `adapters/target/_deprecated/` and are not part of the supported public structure.

## Getting Started

ACMF is a **methodology**, not a CLI. To run an engagement today:

1. Read [`docs/CONSTITUTION.md`](docs/CONSTITUTION.md) — what ACMF will and won’t do.
2. Read [`docs/prerequisites.md`](docs/prerequisites.md) — pick the discovery option your customer can support.
3. Walk [`docs/phases/01-assess.md`](docs/phases/01-assess.md) → 05.
4. Going to a customer? Start with [`docs/customer-facing/acmf-overview-1pager.md`](docs/customer-facing/acmf-overview-1pager.md).

Tooling and reference Terraform/CDK modules are tracked in [`ROADMAP.md`](./ROADMAP.md).

## Reference architecture diagrams

Visual reference for the methodology, source/target adapter model, discovery flow, and Phase 3 traffic shift: [`docs/architecture/diagrams.md`](docs/architecture/diagrams.md). All diagrams are Mermaid and render natively on GitHub.

## End-to-end example

See [`examples/gke-enterprise-vmware-to-eks/`](examples/gke-enterprise-vmware-to-eks/) for a fictional but schema-valid 5-cluster / 80-workload walkthrough, including a one-page [executive summary](examples/gke-enterprise-vmware-to-eks/00-executive-summary.md) you can hand to a sponsor.

## License

This project is licensed under the [Apache License, Version 2.0](./LICENSE). See [`NOTICE`](./NOTICE) for attribution. Contributions are accepted under the same license — see [`CONTRIBUTING.md`](./CONTRIBUTING.md).

## Contact

Hung-Che Lo · `hclo@snese.net`
