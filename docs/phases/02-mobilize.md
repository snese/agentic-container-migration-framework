# Phase 2: Mobilize

**MAP alignment:** AWS MAP — *Mobilize*.

**Why this phase matters:** Mobilize turns discovery data into executable decisions. Skip it and Migrate becomes trial-and-error against production traffic — every undecided 7 Rs choice or unowned blocker surfaces during cutover, when the cost of a wrong call is highest. Migrate (Phase 3) reads `target-mapping.yaml`, `waves.yaml`, and the IaC skeleton produced here as gospel; if those artifacts are thin, Phase 3 cannot run safely.

**Goal:** Turn the Assess outputs into an executable migration plan, prepare the AWS landing zone, and get the customer to a state where wave 1 cutover is a low-drama event.

This phase merges what v0.1 called "Assess" and "Plan." MAP treats workload assessment, target mapping, planning, and landing zone prep as a single mobilization effort, and that matches reality: you can't finalize a target mapping without a landing zone design, and you can't size the landing zone without an assessment.

## Inputs

- `discovery-bundle.json` from Phase 1
- `readiness-scorecard.md` and `readiness-gaps.md` from Phase 1
- AWS account / Organizations baseline (or a green-field decision to build one)

## A. Workload assessment

1. **LLM-assisted analysis** — feed bundle into analysis prompt; output draft per-workload assessment
2. **Human review** — SA reviews, flags hallucinations, adds context
3. **Blocker identification** — anything that prevents migration without re-architecture
4. **Wave grouping** — cluster workloads by migration affinity (shared dependencies, shared owners, shared blast radius)
5. **7 Rs decision per workload** — apply [`7rs-for-containers.md`](../methodology/7rs-for-containers.md)

## B. Target mapping & planning

1. **Target service per workload** — apply [ECS vs EKS decision tree](../decisions/ecs-vs-eks.md); record rationale
2. **IaC strategy** — Terraform vs CDK; Helm vs Kustomize; Argo CD vs Flux; promotion model
3. **Cutover strategy per workload** — blue/green, canary, dual-running, big-bang
4. **Rollback plan** — explicit triggers and procedures per wave

## C. Landing zone preparation

1. **Account / Organizations layout** — Control Tower or hand-rolled; per-environment account split
2. **Network design** — VPC CIDRs sized for VPC CNI, hybrid connectivity (Direct Connect / VPN / TGW), egress strategy, DNS
3. **Cluster pattern** — EKS reference cluster (Karpenter, add-ons baseline), ECS cluster pattern, App Runner service pattern as IaC modules
4. **Image supply chain** — ECR organization, scanning, signing, promotion accounts
5. **Identity baseline** — IAM Identity Center, IRSA / Pod Identity baseline policies
6. **Observability baseline** — Container Insights / Managed Prometheus / Managed Grafana, log aggregation
7. **Security baseline** — GuardDuty, Security Hub, Config rules, baseline OPA/Gatekeeper or Kyverno policies

## D. Cutover & operations design

1. **Cutover playbooks** drafted per wave (with go/no-go gates)
2. **Operating model** for the AWS environment — on-call, change windows, GitOps workflow
3. **SLOs and observability** target state defined
4. **Communications plan** — customer-facing and internal

## Outputs

- `assessment-report.md` — executive + technical sections (per-workload)
- `blockers.md` — must-fix-before-migration list with owners
- `waves.yaml` — proposed migration waves
- `migration-plan.md` — wave-by-wave plan with cutover/rollback per workload
- `target-mapping.yaml` — workload → AWS service mapping with 7 Rs decision
- `iac-skeleton/` — starter Terraform/CDK modules for landing zone and cluster patterns
- `landing-zone-design.md` — accounts, network, identity, observability baseline
- `runbooks/` — initial operational runbooks

## Exit Criteria

- [ ] All workloads categorized (easy / medium / hard / blocker) with 7 Rs decision and rationale
- [ ] Blockers have remediation plans or scope-out decisions, signed off
- [ ] Customer agrees with wave grouping
- [ ] Every workload has a target service decision with rationale
- [ ] Cutover + rollback documented per wave
- [ ] Cost estimate within ±20% of expected
- [ ] Landing zone deployed in a non-prod account; reference cluster pattern stood up and working
- [ ] Observability and security baselines deployed
- [ ] Operating model and on-call for the AWS environment named and trained
