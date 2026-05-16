# Phase 2: Assess

**Goal:** Turn raw discovery data into an actionable migration complexity assessment.

## Inputs
- `discovery-bundle.json` from Phase 1

## Activities
1. **LLM-assisted analysis** — feed bundle into analysis prompt; output draft report
2. **Human review** — SA reviews, flags hallucinations, adds context
3. **Blocker identification** — anything that prevents migration without re-architecture
4. **Wave grouping** — cluster workloads by migration affinity

## Outputs
- `assessment-report.md` — executive + technical sections
- `blockers.md` — must-fix-before-migration list
- `waves.yaml` — proposed migration waves

## Exit Criteria
- [ ] All workloads categorized: easy / medium / hard / blocker
- [ ] Blockers have remediation plans or scope-out decisions
- [ ] Customer agrees with wave grouping
