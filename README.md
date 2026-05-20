# Agentic Container Migration Framework (ACMF)

> Compress Kubernetes-to-AWS migration discovery from days to hours — with ephemeral AI agents that run read-only in your environment.

ACMF is an open methodology for migrating container workloads from GKE Enterprise, AKS, OpenShift, or Rancher to AWS (EKS / ECS). You get structured prompts, schema-validated outputs, and decision frameworks — not another IaC library.

**Status:** v0.6 draft · GKE Enterprise on VMware → EKS is the first reference scenario · [ROADMAP.md](./ROADMAP.md)

---

## Get Started

ACMF is a methodology, not a CLI. Three steps to your first engagement:

1. **Understand the boundaries** — read [`docs/CONSTITUTION.md`](docs/CONSTITUTION.md) (5 min). This tells you what ACMF will and won't do.
2. **Pick your discovery option** — read [`docs/prerequisites.md`](docs/prerequisites.md). Choose how you'll collect data from the source cluster (from zero-install to agent-assisted).
3. **Run Phase 1 (Assess)** — follow [`docs/phases/01-assess.md`](docs/phases/01-assess.md). You'll produce a `discovery-bundle.json` that feeds all downstream phases.

Already familiar? Jump to the [end-to-end example](examples/gke-enterprise-vmware-to-eks/) — a fictional 5-cluster / 80-workload walkthrough with an [executive summary](examples/gke-enterprise-vmware-to-eks/00-executive-summary.md) you can hand to a sponsor.

---

## What ACMF Does

ACMF walks you through five phases, aligned to [AWS MAP](https://aws.amazon.com/migration-acceleration-program/):

```
Assess  →  Mobilize  →  Migrate  →  Modernize  →  Document
```

| Phase | You produce | Key docs |
|-------|-------------|----------|
| 1. Assess | `discovery-bundle.json` + assessment report | [`docs/phases/01-assess.md`](docs/phases/01-assess.md) |
| 2. Mobilize | Wave plan + landing zone design | [`docs/phases/02-mobilize.md`](docs/phases/02-mobilize.md) |
| 3. Migrate | Per-wave cutover + validation | [`docs/phases/03-migrate.md`](docs/phases/03-migrate.md) |
| 4. Modernize | Right-sizing, Pod Identity, observability | [`docs/phases/04-modernize.md`](docs/phases/04-modernize.md) |
| 5. Document | Case study + lessons learned | [`docs/phases/05-document.md`](docs/phases/05-document.md) |

Detailed methodology (MAP/CAF alignment, container-native 7 Rs): [`docs/methodology/`](docs/methodology/).

---

## Source / Target Matrix

| Source platform | → EKS | → ECS |
|---|---|---|
| **GKE Enterprise on VMware** (formerly Anthos) | ✅ Primary | ✅ Selective |
| **GKE Enterprise on Bare Metal** (formerly Anthos) | ✅ Shares VMware adapter | ✅ Selective |
| **GKE** (cloud-native) | 🔜 Planned | 🔜 Planned |
| **AKS** (Azure) | 🔜 Planned | 🔜 Planned |
| **OpenShift** | 🔜 Planned | 🔜 Planned |
| **Rancher / vanilla K8s** | 🔜 Planned | 🔜 Planned |

ACMF complements [AWS Transform](https://aws.amazon.com/transform/) — Transform containerizes individual apps from source code; ACMF migrates workloads that are *already* on Kubernetes. Details: [`docs/decisions/aws-transform-vs-acmf.md`](docs/decisions/aws-transform-vs-acmf.md).

---

## How Discovery Works

You choose your discovery approach based on what you can install in the source environment. Options, from least to most intrusive:

| # | Option | What you need | Output |
|---|--------|---------------|--------|
| 1 | Manifest-only | Helm charts or GitOps repo | Offline analysis |
| 2 | Self-export script | `bash` + `kubectl` + `jq` | `discovery-bundle.json` |
| 3 | Read-only credentials | Short-lived ServiceAccount | Same bundle, we run it |
| 4 | Agent-assisted ⭐ | [Kiro CLI](https://kiro.dev/docs/cli/) (or any agent runtime) | Same bundle, faster |
| 5 | Persistent runtime | [Strands SDK](https://strandsagents.com/) (opt-in, Phase 4 only) | Ongoing optimization |

**Can't install an agent?** Option 4 degrades to Option 2 — the same prompt works as a bash runbook. See [`docs/discovery/`](docs/discovery/) for each option's scripts and threat model.

---

## Target Selection: EKS vs ECS

One question decides your target: **does the workload use the Kubernetes API?**

- CRDs, operators, Helm, service mesh, DaemonSets → **EKS**
- Stateless HTTP, queue consumers, batch jobs → **ECS**
- Mixed portfolio → **Both** (split by namespace)

Full decision tree with compute-model selection: [`docs/decisions/ecs-vs-eks.md`](docs/decisions/ecs-vs-eks.md).

---

## Repository Layout

```
.
├── docs/
│   ├── CONSTITUTION.md          # Non-negotiable principles
│   ├── prerequisites.md         # Tool requirements per adapter
│   ├── methodology/             # MAP/CAF alignment
│   ├── phases/                  # Phase 1–5 playbooks
│   ├── discovery/               # Discovery option details
│   ├── decisions/               # ECS vs EKS, compute models, AWS Transform
│   ├── playbooks/               # Modernize-phase playbooks
│   └── customer-facing/         # 1-pager, pitch guide, FAQ
├── adapters/
│   ├── source/
│   │   ├── gke-enterprise-vmware/   # Reference adapter
│   │   └── _template/               # Add your own
│   └── target/
│       ├── eks/
│       └── ecs-fargate/
├── prompts/                     # Agent prompts (discovery + modernize)
├── schemas/                     # JSON Schema for artifacts
├── scripts/                     # Self-export scripts per source
├── templates/                   # Engagement document templates
└── examples/                    # End-to-end walkthroughs
```

---

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md). This project uses the [Apache License, Version 2.0](./LICENSE).
