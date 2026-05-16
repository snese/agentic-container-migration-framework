# Phase 4: Migrate

**Goal:** Execute the plan, wave by wave.

## Inputs
- `migration-plan.md`, `target-mapping.yaml`, IaC skeletons

## Activities
- IaC apply (target environment)
- Image rebuild / re-tagging (ECR)
- Data migration (DMS / native replication / fresh load)
- DNS / traffic shift
- Validation — synthetic + production smoke tests

## Outputs
- Workloads running on AWS targets
- `cutover-log.md` per wave

## Exit Criteria (per wave)
- [ ] All workloads in wave running on target
- [ ] SLOs met for 7+ days
- [ ] Rollback path tested at least once before final cutover
