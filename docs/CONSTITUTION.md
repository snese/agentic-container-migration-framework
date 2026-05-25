# ACMF Constitution

> **Last updated:** 2026-05-19 (v0.6 cleanup pass)

The non-negotiable principles of the Agentic Container Migration Framework. Every adapter, prompt, schema, and playbook in this repo must conform. When something here breaks, you don't quietly drift — you propose an amendment.

## 1. Non-intrusive by default

We do not install long-running agents in the customer environment. Discovery, assessment, and planning rely on ephemeral runs, manifest snapshots, or short-lived read-only credentials. The most intrusive option a customer can pick is still bounded in time and scope. If a workflow requires a persistent footprint, it is a deliberate, opt-in exception — documented, time-boxed, and removable in one command.

> **Pending amendment (v0.6):** an amendment proposal under [`docs/discovery/mcp-augmentation.md`](./discovery/mcp-augmentation.md#constitution-amendment-proposal-stub) clarifies that *remote, read-only, customer-pinned* MCP servers may be queried by ephemeral agents during discovery without violating §1 — with explicit air-gapped exclusion. To be tabled under the amendment process below.

## 2. Agent-driven, human-judged

Agents (any coding-agent CLI such as [Kiro CLI](https://kiro.dev/docs/cli/installation/), persistent runtimes such as the open-source [Strands Agents SDK](https://strandsagents.com/), or scripted LLM calls) are the *execution layer* for repeatable, context-heavy work — discovery, manifest analysis, IaC scaffolding, runbook drafting. Humans own taste and judgment: target service decisions, blockers, cutover go/no-go, customer communication. We never let an agent ship to production without a named human owner on the change.

## 3. Auditable end-to-end

Every agent invocation is reproducible. Prompts live in this repo under version control. Tool allowlists are explicit. Outputs are structured (JSON Schema) so they can be diffed, replayed, and reviewed. If a customer asks "what did the agent do?", we can show them — prompt, inputs, tools, outputs — without reconstructing it from memory.

## 4. Source/target adapter decoupling

Source platforms (GKE Enterprise on VMware (formerly Anthos), GKE (with GKE Enterprise license), OpenShift, Rancher, vanilla K8s) and AWS targets (EKS, ECS, ROSA on AWS) live behind narrow interfaces. A new source adapter must not require changes to target adapters and vice versa. Inter-phase artifacts use shared schemas, not adapter-specific shapes.

## 5. Evidence over claims

Recommendations cite evidence. "Move this to Fargate" without a manifest reference, a cost figure, or an SLO is a hallucination — not a plan. Assessment outputs surface the source of every claim (manifest path, metric, customer interview). When evidence is missing, we say so.

## 6. Customer-controlled execution

The customer decides what runs in their environment, when, and with what credentials. We provide prompts, scripts, schemas, and playbooks; they decide which to invoke. Output bundles never leave the customer's perimeter without an explicit, logged transfer step. We never embed phone-home telemetry in anything that runs on customer infrastructure.

## 7. MAP/CAF alignment

ACMF is not a competing methodology. It plugs into AWS MAP (Assess / Mobilize / Migrate & Modernize) and addresses all six AWS CAF perspectives (Business, People, Governance, Platform, Security, Operations). Where we extend MAP — and we do, around container-native discovery, hybrid sources, and agentic execution — we name it explicitly so customers and partners can map ACMF artifacts to their existing MAP engagement.

## 8. Container-native, not VM-translated

ACMF was built for Kubernetes/container workloads, not retrofitted from VM migration tooling. We do not assume VM-level lift-and-shift patterns or VM-level inventory as primitives. The 7 Rs, decision trees, landing zone patterns, and modernization playbooks here are written for containers first. VM concerns appear only where the source platform (e.g. GKE Enterprise on VMware) drags them in.

---

## Amendment Process

This constitution changes through pull requests, not Slack threads.

1. **Open an issue** labeled `constitution-amendment` describing the principle being added, removed, or changed, and the customer or engineering reality forcing the change.
2. **Open a PR** modifying this file plus any downstream artifacts (adapters, schemas, phase docs) that must change to remain consistent.
3. **Two-reviewer rule.** At least two maintainers must approve, and at least one must be from a different perspective than the proposer (e.g. if a Platform maintainer proposes, one Security/Governance reviewer is required).
4. **Migration note.** If the amendment invalidates artifacts produced under the prior version, the PR must include a short migration note in `docs/methodology/00-overview.md`.
5. **Versioned.** Amendments bump a `Constitution: vX` line in this file's footer. Old versions remain reachable via git history.

_Constitution: v0.1 — initial drafting._
