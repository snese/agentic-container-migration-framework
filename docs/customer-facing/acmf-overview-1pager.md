# ACMF — One-Pager

> **Container migrations shouldn't take quarters.** ACMF is a methodology for migrating Kubernetes workloads from on-prem and hybrid platforms (Anthos, OpenShift, Rancher, vanilla K8s) to AWS — using *ephemeral* AI agents that run under the customer's control, with auditable inputs, prompts, and outputs.

## The problem

Container estates are large, opinionated, and stitched into the customer's network. Traditional migration tooling assumes either a long-running collector agent (App2Container, MGN) or VM-shaped workloads. That doesn't fit Anthos-on-VMware, regulated OpenShift, or air-gapped Rancher. Senior architects end up doing manifest-by-manifest analysis by hand — typically 5–10 working days for a 100-workload cluster — before any decision can be made.[^1]

[^1]: Internal ACMF benchmark across multi-cluster Anthos engagements; per-customer baseline is captured as an Assess-phase artifact, not promised up-front.

## What ACMF does

| | Traditional approach | ACMF |
|---|---|---|
| Discovery | Persistent agent or manual scripts | Ephemeral, auditable agent run (or pure-bash fallback) |
| Analysis | SA-led, days | Agent-assisted, hours, every prompt versioned |
| Target choice | Defaulting to one service | Per-workload decision tree (EKS / ECS / App Runner) |
| Methodology | Vendor-specific framework | Plugs into AWS MAP & CAF — speaks the standard language |

## What ACMF is *not*

- Not another product or SaaS — it is a **GitHub-tracked methodology** with prompts, schemas, and playbooks.
- Not a replacement for AWS MAP / CAF — it extends them for container workloads.
- Not a fully autonomous migration robot — humans own target decisions, blockers, and cutovers.
- Not a competitor to AWS Transform — see [`aws-transform-vs-acmf.md`](../decisions/aws-transform-vs-acmf.md). They are complementary.

## Customer-visible benefits

1. **Non-intrusive.** No persistent agents, no broad credentials. Five graduated discovery options, ranging from "ship us your manifests" to a one-shot agent run with an explicit tool allowlist.
2. **Auditable.** Every prompt, tool call, and output is version-controlled. If a customer asks "what did the agent do?", we can show them — exactly.
3. **Faster where it counts.** The repetitive parts (discovery, manifest analysis, wave grouping) compress from days to hours. The judgment parts (target choice, cutover risk, customer comms) stay where they belong: with humans.
4. **MAP-aligned.** Phases map 1:1 to MAP *Assess / Mobilize / Migrate & Modernize*; deliverables cover all six AWS CAF perspectives.
5. **Container-native.** 7 Rs, decision trees, landing zones, and modernization patterns are written for Kubernetes — not retrofitted from VM tooling.
6. **Evidence-based.** Recommendations cite a manifest path, a metric, or a customer interview. No claim ships without a source.

## Phase shape

```
Assess  →  Mobilize  →  Migrate  →  Modernize  →  Document
(MRA +     (plan +     (wave        (right-size,   (case study,
discovery)  landing     cutovers)    GitOps,        framework
            zone)                    SRE)           feedback)
```

## What you walk away with (per engagement)

- `discovery-bundle.json` — structured cluster + workload inventory
- `readiness-scorecard.md` — MRA across business, people, governance, platform, security, ops
- `assessment-report.md` + `target-mapping.yaml` — per-workload 7 Rs decision and AWS service mapping
- `migration-plan.md` + `waves.yaml` — cutover plan with rollback per wave
- `iac-skeleton/` — starter Terraform/CDK for the landing zone
- An anonymized case study (with customer approval), feeding the next engagement

## How to start a conversation

1. Read [`acmf-pitch-guide.md`](./acmf-pitch-guide.md) — talk track and discovery questions.
2. Pre-read the [`acmf-customer-faq.md`](./acmf-customer-faq.md) for the security and data-handling questions that always come up.
3. Pick a discovery option from [`docs/prerequisites.md`](../prerequisites.md) that matches the customer's policy posture.
4. Walk [`docs/phases/01-assess.md`](../phases/01-assess.md).

---

*Hung-Che Lo · `hclo@snese.net` · [github.com/snese/agentic-container-migration-framework](https://github.com/snese/agentic-container-migration-framework)*
