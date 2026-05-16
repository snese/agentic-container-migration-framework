# Phases

ACMF is organized into six sequential (but iterable) phases:

| # | Phase | Goal | Key Output |
|---|---|---|---|
| 1 | [Discover](01-discover.md) | Understand source environment without long-running agents | `discovery-bundle.json` |
| 2 | [Assess](02-assess.md) | Identify migration complexity, blockers, dependencies | `assessment-report.md` |
| 3 | [Plan](03-plan.md) | Map workloads to target services; sequence waves | `migration-plan.md` |
| 4 | [Migrate](04-migrate.md) | Execute via IaC + cutover playbooks | Running workloads on AWS |
| 5 | [Optimize](05-optimize.md) | Cost, SRE, security tuning post-migration | `optimization-backlog.md` |
| 6 | [Document](06-document.md) | Case study + reusable artifacts | Anonymized case study |

Each phase doc includes:
- **Inputs** — what's required to start
- **Activities** — agent-driven, manual, or hybrid
- **Outputs** — concrete artifacts (with schemas)
- **Exit criteria** — how to know you're done
