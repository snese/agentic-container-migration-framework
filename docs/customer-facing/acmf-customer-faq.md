# ACMF Customer FAQ

Questions customers actually ask in the first three meetings, with the answers we are willing to commit to in writing.

If a question here drifts from what the framework currently does, that's a bug — open a PR.

---

## What ACMF is

### What is ACMF, in one sentence?

A methodology for migrating Kubernetes workloads from on-prem and hybrid platforms (Anthos, OpenShift, Rancher, vanilla K8s) to AWS, using ephemeral AI agents that run under your control rather than persistent collectors.

### Is ACMF a product I buy?

No. It is an open methodology — prompts, schemas, decision trees, and playbooks tracked in a public GitHub repository. There is no per-seat license, no SaaS endpoint, and no runtime to install on your infrastructure. The cost of an ACMF engagement is the delivery effort plus your AWS consumption.

### How does this relate to AWS MAP and CAF?

ACMF plugs into AWS MAP and CAF. Phases map 1:1 to MAP (Assess / Mobilize / Migrate & Modernize). Deliverables cover all six AWS CAF perspectives (Business, People, Governance, Platform, Security, Operations). Where ACMF extends MAP is in three places: container-native 7 Rs, agentic discovery for hybrid/air-gapped sources, and first-class support for non-AWS sources like Anthos and OpenShift.

### How does this relate to AWS Transform?

Complementary. AWS Transform handles per-application containerization (Dockerfile, image build, ECR, CI/CD). ACMF handles the layer above: which workloads, in what order, on which AWS service, with what landing zone. Transform is one of the tools we may invoke inside ACMF's Migrate phase. See [`docs/decisions/aws-transform-vs-acmf.md`](../decisions/aws-transform-vs-acmf.md).

---

## Security & data handling

### What does the agent see?

Only what you allow it to see. ACMF discovery uses a **tool allowlist** — `kubectl` (read-only), `gcloud` (read-only), `govc` (read-only), and so on. The allowlist is part of the run command; you can read it before you run it. The agent does not have shell access, cannot mutate cluster state, and cannot reach the internet outside the LLM endpoint you choose.

### What leaves my environment?

Nothing, unless you ship it. The agent produces a `discovery-bundle.json` file inside your environment. You decide whether to encrypt it (we recommend `age` with our public key), how to transfer it (object storage, email, USB), and when. There is no phone-home channel embedded in any ACMF script or prompt. This is principle #6 of our [Constitution](../CONSTITUTION.md).

### Where does my data go for analysis?

Your call. Three patterns:

1. **Bundle stays put** — analysis runs inside your environment, against an LLM you self-host or a regional endpoint you approve.
2. **Bundle ships to delivery** — encrypted, transferred out of band, analyzed in our environment.
3. **No bundle leaves at all** — pure-bash discovery (Option 2), analysis run as a human checklist by an SA on-site.

The framework supports all three; the choice is yours.

### What about data residency?

ACMF itself does not pin you to any region. The LLM you point the agent at determines residency for the model call. If you require EU-only or in-country processing, run the analysis against a model that satisfies that — Bedrock in your region, a self-hosted open-weights model, or a partner-hosted endpoint. ACMF prompts are model-agnostic.

### Is the AI making decisions about my migration?

No. The agent does **structured discovery and draft analysis**. Every target-service decision (EKS vs ECS vs App Runner), every wave-grouping decision, and every cutover go/no-go is owned by a named human reviewer. Principle #2 of our [Constitution](../CONSTITUTION.md) is "agent-driven, human-judged" — and we treat that as load-bearing, not aspirational.

### Can the agent change anything in my cluster?

No. Discovery runs in read-only mode (`--no-write` or equivalent), and the tool allowlist does not include any mutating verbs. If you don't trust that — and you shouldn't trust unverified claims — Option 2 is a pure bash script you can read line by line, with no agent runtime at all.

### Will an agent be left running in my environment afterwards?

No. Discovery is **ephemeral** — the agent CLI runs once, produces a bundle, and exits. You can uninstall the CLI immediately afterwards if your policy requires.

There is one exception: Phase 4 (Modernize) optionally supports a longer-lived agent runtime for ongoing optimization recommendations (e.g. via the open-source [Strands Agents SDK](https://strandsagents.com/)). This is **explicitly opt-in**, time-boxed, and removable in one command. It is never used for discovery.

### What credentials does ACMF need?

The minimum your chosen discovery option requires.

- Option 1 (manifest-only): none — you ship the YAML.
- Option 2 (self-export script): your existing `kubectl`/`gcloud`/`govc` credentials, used by you, locally.
- Option 3 (read-only credentials): a 24-hour read-only ServiceAccount you create.
- Option 4 (agent-assisted): same read-only credentials as 2 or 3, accessed through the tool allowlist.
- Option 5 (Phase 4 only): negotiated per engagement, always least-privilege.

ACMF never asks for cluster-admin, AWS root, or long-lived tokens.

### Is the agent's prompt visible?

Yes. Every prompt is in the public repository under `prompts/`. You can read them before you authorize a run. If you want to modify a prompt for your environment, fork it; ACMF treats prompt files as first-class versioned artifacts.

---

## Pricing & commercial

### How is ACMF priced?

The framework itself is free and open. The engagement around it is priced like any consulting or partner-led migration — by scope and effort. If you are inside an AWS MAP funded engagement, ACMF deliverables map cleanly into MAP-funded line items (Assess, Mobilize, Migrate & Modernize).

### What does an engagement cost roughly?

Depends on cluster count, workload count, and how much of the work the customer team takes on directly. A typical first engagement is a single cluster, 1–4 weeks for the Assess + Mobilize phases. Specifics are scoped per customer.

### Do I need an AWS MAP funding agreement?

No, but you probably want one. ACMF artifacts are designed to satisfy MAP MRA (Migration Readiness Assessment) requirements, which is what unlocks MAP funding. If you already have MAP, ACMF accelerates Assess + Mobilize. If you don't, ACMF gives you the artifacts you need to apply.

---

## Timeline & engagement shape

### How long does a typical migration take with ACMF?

The migration itself is still a real project. ACMF compresses the **assessment and planning** parts (which historically dominate timelines) and gives you a structured wave plan; it does not magically shorten cutover windows or data migrations. Realistic shape:

- **Assess phase:** 1–2 weeks (vs 3–6 weeks manual)
- **Mobilize phase:** 3–6 weeks (depending on landing-zone maturity)
- **Migrate phase:** wave-driven; weeks to months depending on workload count and risk tolerance
- **Modernize phase:** ongoing

### Can I run ACMF myself without a delivery partner?

Yes. The repository contains every prompt, schema, and playbook you need. Customers with strong platform teams have everything required to self-deliver Assess and Mobilize. Engaging a partner is helpful for landing-zone IaC, the harder cutovers, and the "second set of eyes on the target-service decision" — but it is not required by the framework.

### What does an ACMF engagement deliver, concretely?

- `discovery-bundle.json` — structured cluster + workload inventory
- `readiness-scorecard.md` + `readiness-gaps.md` — MRA across all six CAF perspectives
- `assessment-report.md` + `target-mapping.yaml` — per-workload 7 Rs decision and AWS service mapping with rationale
- `migration-plan.md` + `waves.yaml` — cutover plan with rollback per wave
- `iac-skeleton/` — starter Terraform/CDK for the landing zone
- `cutover-log.md` per wave during Migrate
- An anonymized case study (with your approval), feeding the next engagement

---

## Tools & implementation

### Which agent runtime do you use?

The reference walkthroughs use [Kiro CLI](https://kiro.dev/docs/cli/installation/) for ephemeral discovery and the open-source [Strands Agents SDK](https://strandsagents.com/) for the optional Phase 4 ongoing-optimization runtime. **Neither is required by the framework.** Any agent harness that supports prompt files and an explicit tool allowlist will work — including pure-Python or pure-Bash if you prefer no agent runtime at all.

### What if my cluster is air-gapped?

Use Discovery Option 2 (self-export script). The script uses only `kubectl`/`gcloud`/`govc` read-only commands, produces a JSON bundle, and ships it out via whatever mechanism you already use to move artifacts across the air gap. The analysis happens on the delivery side, against an LLM in our environment. No outbound LLM call is made from inside your perimeter.

### What if I don't want any LLM involvement at all?

ACMF still works. Every analysis prompt doubles as a structured human checklist. Output schemas (JSON) are the same; the rate at which an SA fills them in is the difference. The decision trees, landing-zone patterns, 7 Rs, and CAF mappings are all human-readable.

### Which AWS targets are supported?

Today: **EKS** (including Auto Mode), **ECS Fargate**, **App Runner**. The decision matrix in [`docs/decisions/ecs-vs-eks.md`](../decisions/ecs-vs-eks.md) tells you which workload goes where. Hybrid mappings (EKS for system pods, ECS for stateless services) are first-class.

### Which source platforms are supported?

Today, in priority order: **Anthos on VMware** (first reference adapter), then Anthos on GCP, OpenShift, Rancher, and vanilla K8s. See [`ROADMAP.md`](../../ROADMAP.md) for status.

---

## "Will it work for…"

### …a regulated industry (healthcare, finance, public sector)?

Yes — that is the design center. The five-option discovery menu, evidence-based recommendations, and customer-controlled execution model exist precisely because regulated customers cannot use App2Container or persistent collectors.

### …a multi-cluster Anthos estate?

Yes. The Anthos-on-VMware adapter is the first reference adapter. Multi-cluster is handled by running discovery per-cluster and aggregating bundles in Phase 2 (Mobilize).

### …a workload that uses Service Mesh / Operators / CRDs heavily?

Yes — those workloads usually map to EKS. The decision matrix and the Anthos adapter both call this out explicitly. Anthos Service Mesh → Istio on EKS or Amazon VPC Lattice; Policy Controller → OPA Gatekeeper or Kyverno; Workload Identity → IRSA / EKS Pod Identity.

### …a workload I want to **modernize** (not just migrate)?

Yes. Phase 4 (Modernize) is a first-class phase — right-sizing, Karpenter / Fargate split, IRSA cleanup, GitOps maturity, and any deferred 7 Rs Refactor work. ACMF treats modernization as the second half of the engagement, not an optional bolt-on.

---

*Don't see your question? Email `hclo@snese.net` or open an issue on the [ACMF repository](https://github.com/snese/agentic-container-migration-framework).*
