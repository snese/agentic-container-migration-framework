# Contributing

Early-stage. Contributions welcome but please open an issue first to discuss scope.

## Layout principles

- `docs/` — methodology, decisions, case studies (markdown only)
- `adapters/` — source-platform and target-platform specific content
- `prompts/` — Kiro CLI / LLM prompts (versioned)
- `schemas/` — JSON Schemas for inter-phase artifacts (versioned)
- `scripts/` — pure bash, no installer required
- `examples/` — runnable end-to-end walkthroughs

## Adding a new source platform

See [`adapters/source/_template/README.md`](adapters/source/_template/README.md).

## Style

- Markdown: ATX headers, line-wrap at sentence boundaries (don't hard-wrap mid-paragraph)
- Code blocks: always specify language
- Decisions go in `docs/decisions/` as ADRs (lightweight format)
- No customer names / identifying info anywhere; case studies must be anonymized

## Commits

Conventional Commits style preferred:
- `feat:` new content / capability
- `fix:` correction / bugfix
- `docs:` doc-only changes
- `refactor:` reorganization without semantic change
