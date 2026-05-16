# Phases

ACMF v0.2 is organized into five phases, aligned with the AWS Migration Acceleration Program (MAP).

| # | Phase | MAP alignment | Goal | Key Output |
|---|---|---|---|---|
| 1 | [Assess](01-assess.md) | Assess | Non-intrusive discovery + Migration Readiness Assessment | `discovery-bundle.json`, `readiness-scorecard.md` |
| 2 | [Mobilize](02-mobilize.md) | Mobilize | Workload assessment, target mapping, planning, landing zone | `migration-plan.md`, `target-mapping.yaml`, `iac-skeleton/` |
| 3 | [Migrate](03-migrate.md) | Migrate & Modernize | Wave-by-wave cutover | Running workloads + `cutover-log.md` per wave |
| 4 | [Modernize](04-modernize.md) | Migrate & Modernize | Cost / reliability / security tuning + deferred Refactor work | `optimization-backlog.md` |
| 5 | [Document](05-document.md) | (cross-cutting) | Anonymized case study, reusable artifacts | `docs/case-studies/<slug>.md` |

See [`../methodology/00-overview.md`](../methodology/00-overview.md) for how these phases map to the AWS CAF six perspectives, and [`../methodology/7rs-for-containers.md`](../methodology/7rs-for-containers.md) for the container-native interpretation of the 7 Rs used during Mobilize.

Each phase doc includes:
- **Inputs** — what's required to start
- **Activities** — agent-driven, manual, or hybrid
- **Outputs** — concrete artifacts (with schemas)
- **Exit criteria** — how to know you're done

> **Migrating from v0.1?** The old "Discover / Assess / Plan / Migrate / Optimize / Document" six-phase structure has collapsed into the five MAP-aligned phases above. Old discover content lives in `01-assess.md`; old assess + plan content lives in `02-mobilize.md`. Git history is preserved via `git mv`.
