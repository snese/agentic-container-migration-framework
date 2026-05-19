# Prompt ↔ schema contract

This document defines the cross-validation contract between the discovery
prompt and the discovery bundle JSON schema, and how
`scripts/validate-prompt-schema.sh` enforces it.

## Files under contract

- **Schema**: `schemas/discovery-bundle.schema.json`
- **Prompt**: `prompts/discovery/gke-enterprise-vmware.prompt.md`
  (the framework was renamed Anthos → GKE Enterprise on VMware; the file
  path reflects the new name)

## The contract

1. **Schema → prompt coverage.**
   Every key listed in `schemas/discovery-bundle.schema.json#/required`
   MUST be addressed by the prompt — either by exact name or by an approved
   alias (see `ALIASES` in the validator script). This guarantees the prompt
   instructs the agent to populate every required top-level field.

2. **Prompt → schema coverage.**
   Every `bundle.<field>` reference in the prompt MUST resolve to a real
   top-level property in the schema's `properties` object. Sub-paths like
   `bundle.traffic.summary` are accepted as long as their root (`traffic`)
   is a schema property. Filename references (`discovery-bundle.json`,
   `discovery-bundle.schema.json`) are filtered out by the validator.

3. **Aliases are exceptions, not the default.**
   When the prompt uses a different word for a schema key (e.g. the prompt
   says "ISO-8601" rather than "generated_at"), the validator's `ALIASES`
   map records that exception. New schema keys SHOULD be addressed by their
   exact name in the prompt; aliases must be approved in code review.

## Running the validator

Locally:

```bash
bash scripts/validate-prompt-schema.sh
```

Exit code `0` when the contract holds, `1` on any mismatch. Mismatches are
printed as `MISS <key/ref> — <reason>`.

The same script runs in CI as the `prompt-schema-contract` job in
`.github/workflows/ci.yml` and is wired to fail the workflow on any
contract drift.

## Known aliases (current state)

| Schema key             | Prompt phrasing                               |
|------------------------|-----------------------------------------------|
| `schema_version`       | mentioned via "schema" / schema reference     |
| `generated_at`         | "ISO-8601" timestamp output                   |
| `generated_by`         | "kiro-cli" generator identity                 |
| `scope`                | "Discovery scope summary" section             |
| `external_dependencies`| "External Dependencies" section               |
| `crds`                 | "Operators & CRDs" section                    |
| `vmware`               | "VMware Layer" section                        |
| `utilization`          | "Utilization Metrics" section                 |
| `traffic`              | "Traffic Analysis" section                    |

## Current status

The contract passes as of this commit. Run the validator before any change
to either the schema or the prompt; if a new schema key is introduced
without prompt coverage (or vice versa), the script will block CI until the
gap is closed or an alias is registered.

## TODO / known gaps

_None at the time of writing._ Add entries here as future drift is
discovered, with a tracking note before resolving in code.
