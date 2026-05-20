# ACMF Pitch Guide

Talk track, discovery questions, and objection handling for first conversations with a customer who is considering a container migration to AWS.

This is **internal/delivery-side**, but every claim made here can be backed by something in this repo. Don't say it on a call if you can't show it on the screen.

## When to bring up ACMF

- Customer runs GKE Enterprise on VMware (formerly Anthos) / OpenShift / Rancher / self-managed K8s and is evaluating AWS.
- They have ≥10 services or ≥1 production cluster — small enough to skip a methodology, but large enough to need one.
- They have policy constraints (regulated, air-gapped, sovereign) that rule out persistent collectors or long-running agents.
- They are already running an AWS MAP engagement and asking "but how do we *actually* do containers?"

## When **not** to bring up ACMF

- Single Dockerfile, single service, no K8s — point them at AWS Transform's containerization flow and ECS. ACMF is overkill.
- Pure VM lift-and-shift — that is  territory. Don't muddy the water.
- They want a turnkey product. ACMF is a methodology; if they want a SaaS, they want AWS Transform.

## 30-second pitch

> Most container migrations stall on the assessment phase — a senior architect hand-grading manifests for a week. We have a methodology called ACMF that compresses that into hours by running an auditable AI agent against your cluster, in your environment, under your control. It plugs into AWS MAP, covers all six CAF perspectives, and gives you a per-workload target-service decision (EKS or ECS) backed by evidence — not vibes. You keep every artifact.

## 5-minute talk track

1. **Frame the problem** (60s). Container migrations are different from VM migrations. The hard part isn't moving the container — it's deciding *what to move where, in what order, with what landing zone*. That is reading manifests, mapping dependencies, sorting waves. Humans do it; it eats weeks.
2. **Frame the constraint** (30s). Most container customers can't run a persistent collector. GKE Enterprise on VMware sits behind their firewall; OpenShift is regulated; Rancher is sovereign. So you're back to "send us your YAML" and a Confluence page of decisions.
3. **Introduce the shift** (60s). ACMF replaces the persistent agent with an *ephemeral* one — a coding-agent CLI the customer runs **once**, with a prompt and tool allowlist they can audit. Output is structured JSON; the agent uninstalls. No phone-home, no daemon.
4. **Tie to AWS standards** (60s). Phases map to MAP. Deliverables hit all six CAF perspectives. Target selection isn't "EKS for everything" — it's a per-workload decision matrix between EKS and ECS, with the rationale recorded in YAML.
5. **Concrete next step** (30s). Pick a discovery option (we have five, ordered by intrusiveness) and an engagement shape (self-service, SA-assisted, ProServe, or partner — see [`engagement-model.md`](./engagement-model.md)). Walk Phase 1 on a single cluster. You get a discovery bundle, a readiness scorecard, and a draft target-mapping inside one engagement week.

## Discovery questions

Use these to qualify the opportunity and pick the right discovery option:

- **Source platform.** "Which clusters are in scope — vendor, version, on-prem or cloud?"
- **Network posture.** "Can a workstation reach your control plane from outside, or is everything inside the perimeter?"
- **Tooling policy.** "Can a CLI tool talk to an external LLM from inside your environment, or does it need to stay local/offline?"
- **Air-gap.** "Is there a hard boundary that no inbound or outbound TCP crosses?"
- **Credentials.** "Could you grant a 24h read-only ServiceAccount, or is even that out of policy?"
- **Existing AWS posture.** "Do you have a landing zone? AWS Organizations? An Identity Center setup?"
- **Existing MAP engagement.** "Are you already inside an AWS MAP funded engagement?"
- **Modernization appetite.** "Are you trying to move *as-is* and modernize later, or is this a chance to clean up debt at the same time?"
- **Workload shape.** "Stateful, stateless, batch, system. Roughly what's the split?"
- **Operational comfort with K8s.** "Do you want to keep running Kubernetes on AWS, or would you happily drop to ECS where it fits?"

## Objection handling

### 1. "We don't allow AI tools to run inside our environment."

Acknowledge first; don't argue. Then:

> Totally fair. ACMF has five discovery options for exactly this reason. The default option uses an agent CLI, but options 1 and 2 don't — option 1 is "ship us your manifests, we analyze offline," option 2 is a pure bash script using only `kubectl`. Same output schema, no agent runtime in your environment. We can deliver the framework end-to-end with zero agent runs on your side if needed.

Show them: [`docs/discovery/README.md`](../discovery/README.md) and [`docs/prerequisites.md`](../prerequisites.md) (fallback section).

### 2. "How do we know the AI didn't hallucinate the recommendation?"

> Two answers. First, the agent's job is **discovery and structured analysis**, not the final decision — every target-service choice is reviewed by a human SA against the decision matrix in `docs/decisions/ecs-vs-eks.md`. Second, every claim in the assessment cites the manifest path, the metric, or the interview that produced it. If a recommendation can't show its source, it's flagged. That's principle #5 in our [Constitution](../CONSTITUTION.md): "evidence over claims."

### 3. "Why not just use AWS Transform?"

Don't position as either/or. ACMF complements Transform.

> AWS Transform is excellent at the per-application containerization step — Dockerfile, image build, ECR, CI/CD wiring. ACMF is the layer above: which workloads, in which order, on which AWS service, with what landing zone. We use Transform *inside* ACMF's Migrate phase whenever a workload needs containerization or refactoring at the per-app level.

Hand them: [`docs/decisions/aws-transform-vs-acmf.md`](../decisions/aws-transform-vs-acmf.md).

### 4. "Our security team will block any LLM call."

> Then we run option 2 (pure bash export) on your side and run the analysis prompts on our side, against an LLM in our environment, on the bundle you sent us. Or we run it entirely on a model you self-host — Strands Agents and most coding-agent harnesses are model-agnostic. Either way, no LLM call originates from your environment.

### 5. "Isn't this just consulting with extra steps?"

Honest answer:

> Partially yes. ACMF is what we hand to a delivery team or partner so the consulting *isn't* artisanal anymore. The methodology, prompts, schemas, and decision trees are version-controlled. Two engineers running ACMF on the same cluster produce comparable bundles. It is faster *and* more consistent than ad-hoc SA work, but it is not a SaaS product — and we don't pretend it is.

### 6. "How do we know you won't take our data?"

> The bundle is generated in your environment, encrypted with a key you choose, and shipped over a channel you choose. You can read every line of every prompt and every script before you run them — they're in a public Git repo. Constitution principle #6: customer-controlled execution. We never embed phone-home telemetry in anything that runs on your infrastructure.

### 7. "Pricing?"

ACMF itself is open methodology — there is no per-seat license. Cost is the engagement (delivery hours) plus AWS consumption. If the customer is already in AWS MAP, ACMF deliverables typically map directly to MAP-funded work.

## Closing the conversation

Ideal next step out of a first call:

1. Customer names a single in-scope cluster.
2. We agree which of the five discovery options matches their policy.
3. We schedule a 1-day workshop to walk Phase 1 on that cluster.
4. The output is a discovery bundle and a readiness scorecard — concrete artifacts, not a slide deck.

If they're not ready for a workshop, hand them the [1-pager](./acmf-overview-1pager.md) and the [FAQ](./acmf-customer-faq.md) and follow up in two weeks.
