# Phase 3: Plan

**Goal:** Map each workload to a target AWS service and produce an executable migration plan.

## Inputs
- `assessment-report.md`, `waves.yaml` from Phase 2

## Activities
1. **Target mapping** — apply [ECS vs EKS decision tree](../decisions/ecs-vs-eks.md) per workload
2. **IaC strategy** — choose Terraform / CDK / Helm + GitOps stack
3. **Cutover strategy** — per workload: blue/green, canary, big-bang
4. **Rollback plan** — explicit triggers and procedures

## Outputs
- `migration-plan.md` — wave-by-wave plan
- `target-mapping.yaml` — workload → AWS service mapping
- `iac-skeleton/` — starter Terraform/CDK modules

## Exit Criteria
- [ ] Every workload has a target service decision with rationale
- [ ] Cutover + rollback documented per wave
- [ ] Cost estimate within ±20% of expected
