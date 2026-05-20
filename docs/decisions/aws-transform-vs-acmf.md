# AWS Transform vs ACMF — Positioning

> **TL;DR:** AWS Transform and ACMF are complementary, not competitive. Transform is the per-application execution tool; ACMF is the portfolio-level methodology. Use Transform *inside* ACMF whenever a workload needs containerization or per-app refactoring.

This doc is shareable with customers. It contains no internal jargon and no internal-only product names.

## What each is

### AWS Transform

[AWS Transform](https://aws.amazon.com/transform/) is AWS's product for accelerating modernization of individual applications. For containers specifically, it focuses on:

- Containerizing a single application (Dockerfile generation, dependency analysis, base-image selection)
- Image build pipeline scaffolding (ECR, build pipelines, scanning)
- Per-application CI/CD wiring
- Code-level analysis and refactoring assistance for the application being containerized

Transform is a managed AWS service. The unit of work is **an application**.

### ACMF

ACMF is an open methodology for migrating a **container portfolio** (multiple workloads, often multiple clusters) from a non-AWS Kubernetes platform to AWS. It covers:

- Cluster-level discovery across GKE Enterprise on VMware (formerly Anthos), OpenShift, Rancher, vanilla K8s
- Migration Readiness Assessment (MRA) across all six AWS CAF perspectives
- Per-workload target-service selection (EKS vs ECS)
- Wave planning, landing-zone preparation, cutover/rollback design
- Modernization (right-sizing, GitOps, SRE) post-cutover
- Anonymized case-study production

The unit of work is **a cluster, an estate, or a migration wave**.

## Decision matrix — which tool when

| # | Customer scenario | Recommended primary tool | Rationale |
|---|---|---|---|
| 1 | Single Java/.NET app on a VM, customer wants it containerized and deployed on AWS | **AWS Transform** | Single-application containerization is exactly Transform's sweet spot. ACMF would be heavyweight overhead. |
| 2 | Single legacy app already in a container, just needs to land on ECS | **AWS Transform** | Per-app deploy automation, no portfolio decisions needed. |
| 3 | A 50-workload GKE Enterprise on VMware cluster moving to AWS | **ACMF** | Portfolio-level decisions (EKS vs ECS per workload, wave plan, landing zone) dominate. Transform doesn't address those. |
| 4 | A regulated/air-gapped OpenShift estate moving to AWS | **ACMF** | Discovery options 1–2 (manifest-only / self-export) are required by policy; persistent agents are non-starters. ACMF's non-intrusive defaults match. |
| 5 | A multi-cluster mixed estate (GKE Enterprise + Rancher + a few VMs) | **ACMF**, with Transform invoked inside the Migrate phase for individual apps that need containerization rework | Portfolio shape requires methodology; per-app rework benefits from Transform. |
| 6 | A customer who has already shipped manifests and just needs them deployed on AWS | **ACMF (lightweight)** — Phase 2 (Mobilize) onwards | No source-platform discovery needed; Transform doesn't add value if the manifests are ready. |
| 7 | A customer running a single application on a single small K8s cluster, mostly stateless | **AWS Transform** for the application; ACMF only if cluster-level concerns (mesh, networking) actually exist | One workload, one decision — Transform's scope is enough. |

For each row, exactly one tool is the **primary** entry point. The rule of thumb is: **if the question is "which AWS service does this app belong on?", use ACMF. If the question is "how do I containerize and ship this app?", use Transform.**

## How they integrate

ACMF and Transform compose cleanly:

```
ACMF Phase 1 (Assess)        ──→  Discover + score the portfolio
ACMF Phase 2 (Mobilize)      ──→  Per-workload target decision (EKS/ECS) + landing zone
ACMF Phase 3 (Migrate)       ──→  For each workload that needs containerization or per-app refactoring,
                                  invoke AWS Transform here. ACMF treats Transform as one of the tools
                                  available inside the Migrate phase.
ACMF Phase 4 (Modernize)     ──→  Post-cutover optimization
ACMF Phase 5 (Document)      ──→  Case study, framework feedback
```

Specifically, Transform is most useful inside ACMF Phase 3 in these cases:

- A workload's 7 Rs decision is **Replatform** or **Refactor** at the application level (not just a manifest port)
- An application needs a Dockerfile generated or modernized as part of the move
- A specific service is being relocated to ECS from a custom container build
- Per-app CI/CD scaffolding is needed and the customer doesn't have an existing pipeline

If the workload's 7 Rs decision is **Rehost** (manifest port — GKE Enterprise manifest → EKS manifest), Transform is usually unnecessary. The work is at the K8s manifest layer, which is ACMF's home turf.

## Anti-patterns

- ❌ **"We have AWS Transform, so we don't need a methodology."** Transform is a tool, not a portfolio plan. A 50-workload migration without a wave plan and a target-mapping decision per workload will land badly regardless of how good the per-app containerization is.
- ❌ **"We have ACMF, so we don't need Transform."** ACMF is a methodology, not a code-modernization product. If you have apps that need containerizing or per-app refactoring, Transform is the right execution tool — don't reinvent it inside the framework.
- ❌ **Sequencing them serially when they should run in parallel.** Inside Phase 3, multiple workloads can be in flight simultaneously: some moving with manifests-only (no Transform), some flowing through Transform for per-app modernization. The wave plan from Phase 2 names which is which.

## What this means for proposals

When scoping a customer engagement:

1. Start with ACMF's Phase 1 discovery to understand the portfolio shape.
2. The Phase 2 target-mapping output will name which workloads need application-level modernization. Those become Transform candidates.
3. Scope Transform usage as a line item *inside* the ACMF Migrate phase, with the workload list known up front.
4. If the engagement is a single app that doesn't need a portfolio plan, skip ACMF and propose Transform directly.

The goal is to give the customer one coherent migration story, not two parallel ones.

---

*Questions or counterexamples? Open an issue on the [ACMF repository](https://github.com/snese/agentic-container-migration-framework).*
