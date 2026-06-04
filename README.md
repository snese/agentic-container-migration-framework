# Agentic Container Migration Framework (ACMF)

> Compress Kubernetes-to-AWS migration discovery from days to hours — with ephemeral AI agents that run read-only in your environment.

ACMF is an open methodology for migrating container workloads from GKE Enterprise, OpenShift, Rancher, or vanilla Kubernetes to AWS (EKS / ECS). You get structured prompts, schema-validated outputs, and decision frameworks — not another IaC library.

**Status:** v0.6 draft · GKE Enterprise on VMware → EKS is the reference scenario · [ROADMAP.md](./ROADMAP.md)

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

Visual overview of the full flow: [`docs/architecture/diagrams.md`](docs/architecture/diagrams.md).

Detailed methodology (MAP/CAF alignment, container-native 7 Rs): [`docs/methodology/`](docs/methodology/).

---

## Source / Target Matrix

| Source platform | → EKS | → ECS |
|---|---|---|
| **GKE Enterprise on VMware** (formerly Anthos) | ✅ Reference | ✅ Selective |
| **GKE Enterprise on Bare Metal** (formerly Anthos) | ✅ Shipped | ✅ Selective |
| **GKE Enterprise on GCP** | ✅ Shipped | ✅ Selective |
| **OpenShift** (incl. ROSA detection) | ✅ Shipped | ✅ Selective |
| **Rancher** (k3s / RKE2 / Fleet) | ✅ Shipped | ✅ Selective |
| **Vanilla K8s** (kubeadm / CAPI) | ✅ Shipped | ✅ Selective |
| **AKS** (Azure) | 🔜 Planned | 🔜 Planned |

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
│   ├── CONSTITUTION.md              # Non-negotiable principles
│   ├── prerequisites.md             # Tool requirements per adapter
│   ├── methodology/                 # MAP/CAF alignment
│   ├── phases/                      # Phase 1–5 playbooks
│   ├── discovery/                   # Discovery option details
│   ├── decisions/                   # ECS vs EKS, compute models, data migration
│   │   ├── ecs-vs-eks.md            # 3-level decision tree
│   │   ├── eks-compute-model.md     # Auto Mode vs Karpenter vs MNG
│   │   ├── ecs-compute-model.md     # Fargate vs EC2 vs Spot
│   │   ├── aws-transform-vs-acmf.md # Complementary positioning
│   │   └── data-migration-patterns.md
│   ├── playbooks/                   # Modernize-phase playbooks
│   │   ├── config-sync-to-argocd.md
│   │   ├── irsa-to-pod-identity.md
│   │   ├── karpenter-rightsizing.md
│   │   ├── observability-uplift.md
│   │   └── traffic-shifting.md
│   ├── architecture/                # Reference diagrams (Mermaid)
│   └── customer-facing/             # 1-pager, pitch guide, FAQ
├── adapters/
│   ├── source/
│   │   ├── gke-enterprise-vmware/   # Reference adapter (most complete)
│   │   ├── gke-enterprise-baremetal/
│   │   ├── gke-enterprise-gcp/
│   │   ├── openshift/
│   │   ├── rancher/
│   │   ├── vanilla-k8s/
│   │   └── _template/              # Add your own
│   └── target/
│       ├── eks/
│       └── ecs/
├── prompts/                         # Agent prompts (discovery + modernize)
├── schemas/                         # JSON Schema for artifacts
├── scripts/                         # Self-export scripts per source
├── templates/                       # Engagement document templates
└── examples/                        # End-to-end walkthroughs
```

---

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md). This project uses the [Apache License, Version 2.0](./LICENSE).
