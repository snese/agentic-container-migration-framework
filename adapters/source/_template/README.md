# Source Adapter Template

Copy this directory to add support for a new source platform.

## Required files

- `README.md` — overview, scope, gotchas
- `mapping.md` — source-feature → AWS-equivalent table
- `gotchas.md` — known issues + workarounds
- Discovery prompt at `prompts/discovery/<platform>.prompt.md`
- Optional: `scripts/discovery/<platform>-export.sh` for Discovery Option 2

## Checklist when adding a new source

- [ ] Add platform enum value to `schemas/discovery-bundle.schema.json` `source_platform`
- [ ] Provide discovery prompt
- [ ] Provide at least one self-export script variant
- [ ] Document feature-mapping table
- [ ] Add at least one gotcha entry
- [ ] Wire into top-level README target/source matrix
- [ ] Reference one example case study (anonymized OK)
