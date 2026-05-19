# Phase 3: Migrate

**MAP alignment:** AWS MAP — *Migrate & Modernize* (migrate portion).

**Why this phase matters:** This is where planning meets reality. Every decision made in Assess and Mobilize is validated — or invalidated — by actual traffic and data. Skip the wave discipline here and one bad cutover will stall the rest of the program for weeks while trust is rebuilt. Modernize (Phase 4) depends on stable, observable workloads on AWS targets; without a clean Migrate, there is nothing concrete to right-size, harden, or refactor.

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
