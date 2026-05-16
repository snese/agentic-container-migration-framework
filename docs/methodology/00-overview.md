# Methodology Overview — ACMF ↔ AWS MAP & CAF

ACMF is opinionated about *how* to migrate container workloads, but it is not a parallel universe. It is designed to drop into a customer engagement that already speaks AWS MAP (Migration Acceleration Program) and AWS CAF (Cloud Adoption Framework). This page is the Rosetta Stone.

If you only read one methodology doc, read this one.

## ACMF phases ↔ AWS MAP phases

AWS MAP has three phases: **Assess**, **Mobilize**, **Migrate & Modernize**. ACMF v0.2 reorganizes its internal flow to match.

| ACMF phase | MAP phase | What we actually do |
|---|---|---|
| 1. Assess | Assess | Non-intrusive discovery + Migration Readiness Assessment (MRA) across business, people, governance dimensions. Produces `discovery-bundle.json` and a readiness scorecard. |
| 2. Mobilize | Mobilize | Workload assessment, target mapping, wave planning, landing zone prep, IaC skeletons, cutover/rollback design. Produces `migration-plan.md`, `target-mapping.yaml`, `iac-skeleton/`. |
| 3. Migrate | Migrate & Modernize | Wave-by-wave cutover. Image rebuild, IaC apply, data migration, traffic shift, validation. Produces running workloads + `cutover-log.md` per wave. |
| 4. Modernize | Migrate & Modernize | Post-cutover modernization & optimization — right-sizing, Karpenter/Fargate split, IRSA, GitOps maturity, SRE practices. Produces `optimization-backlog.md`. |
| 5. Document | (cross-cutting) | Anonymized case study, reusable patterns contributed back to adapters, framework backlog. |

**Key shift from v0.1:** the old "Discover / Assess / Plan" trio collapses into MAP-aligned **Assess + Mobilize**. Modernization gets its own phase instead of being buried in "Optimize" — because for container workloads, modernization is rarely optional.

## ACMF deliverables ↔ AWS CAF perspectives

CAF organizes cloud adoption capabilities into six perspectives. Every ACMF deliverable lands in at least one. This is how we make sure a migration proposal doesn't ship with a beautiful EKS cluster and zero answers for the operations team.

| CAF perspective | ACMF artifacts | Lives in |
|---|---|---|
| **Business** | Business case, TCO model, value-tracking KPIs, modernization ROI | [`business.md`](caf-perspectives/business.md) |
| **People** | Skills gap analysis, training plan, org/role changes (K8s ops → AWS-native ops) | [`people.md`](caf-perspectives/people.md) |
| **Governance** | Wave plan, risk register, change control, cost guardrails, portfolio view | [`governance.md`](caf-perspectives/governance.md) |
| **Platform** | Landing zone, EKS/ECS/App Runner reference architectures, IaC skeletons, network design | [`platform.md`](caf-perspectives/platform.md) |
| **Security** | IRSA design, image supply chain, network policies, secrets, compliance mapping | [`security.md`](caf-perspectives/security.md) |
| **Operations** | SLOs, observability stack, incident runbooks, on-call rotation, GitOps workflow | [`operations.md`](caf-perspectives/operations.md) |

## Where ACMF extends MAP

MAP is excellent at the macro shape of a migration, but it was largely shaped by VM-era patterns. ACMF extends it in three places:

1. **Container-native discovery and the 7 Rs.** MAP's classic 7 Rs (Retire, Retain, Rehost, Relocate, Repurchase, Replatform, Refactor) were defined for VMs and applications. For Kubernetes workloads, these mean different things — *Rehost* is a manifest port, not a VM lift; *Relocate* usually means EKS-Anywhere or ROSA → ROSA on AWS, not VMware Cloud on AWS. See [`7rs-for-containers.md`](7rs-for-containers.md).

2. **Agentic discovery for hybrid and air-gapped sources.** MAP partner tooling (App2Container, MGN, Migration Evaluator) assumes you can install an agent or run an inventory collector with broad credentials. ACMF supports customers where that is impossible — air-gapped Anthos, sovereign OpenShift, customer-controlled Rancher — by replacing persistent agents with ephemeral, auditable agent runs. See [`docs/discovery/`](../discovery/).

3. **Source-platform diversity beyond AWS-native.** MAP's reference flows assume VMware → AWS or AWS account → AWS account. ACMF treats Anthos on VMware, Anthos on GCP, OpenShift, Rancher, and vanilla K8s as first-class sources, each with its own adapter. The cross-cloud and cross-distribution concerns (Workload Identity → IRSA, Anthos Config Sync → Argo CD, OpenShift Routes → Ingress) live in source adapters, not in the core methodology.

## How to use this methodology layer

- **Selling/proposal stage:** read [`business.md`](caf-perspectives/business.md), [`governance.md`](caf-perspectives/governance.md), and [`7rs-for-containers.md`](7rs-for-containers.md). These align ACMF to the language MAP customers already speak.
- **Engagement kickoff:** map your engagement's deliverables to the table above. Anything missing is a gap to flag, not silently drop.
- **Delivery:** follow the [`docs/phases/`](../phases/) playbooks; each phase doc cross-references the perspectives it touches.
- **Constitution conflicts:** if a CAF-shaped expectation contradicts an ACMF principle, the [Constitution](../CONSTITUTION.md) wins, and you open an amendment issue if you disagree.
