# Prerequisites

What you need installed to run ACMF discovery and analysis.

## Universal (all source adapters)

Every ACMF engagement requires:

- **bash** (4.0+) — the self-export scripts are bash
- **kubectl** — configured for the target cluster(s)
- **jq** — JSON processing for bundle assembly
- **A text editor** or LLM-capable environment for reviewing prompts and outputs

## Per-adapter tools

Each source adapter has its own CLI requirements. The table below lists what each adapter's export script calls beyond the universal set:

| Source Adapter | Additional tools needed |
|---|---|
| GKE Enterprise on VMware | `gcloud`, `govc` (VMware vSphere CLI) |
| GKE (cloud-native) | `gcloud` |
| AKS | `az` (Azure CLI) |
| OpenShift | `oc` (OpenShift CLI) |
| Rancher / vanilla K8s | `kubectl` only (or `rancher` CLI for project metadata) |

See each adapter's README under `adapters/source/` for specific version notes and known gotchas.

## Agent runtime (optional — Discovery Option 4)

For agent-assisted discovery (the recommended path when permitted), you need ONE of:

- [Kiro CLI](https://kiro.dev/docs/cli/) — reference agent runtime. Supports prompt files, tool allowlists, and headless mode for CI/CD.
- Any coding-agent CLI that supports MCP and tool allowlisting.

> **Not required.** If no agent CLI is available, use Discovery Option 2 (self-export script) — same JSON output, manual execution. See the Fallback section below.

## Reference agent runtimes

ACMF does not require any specific vendor runtime. The framework ships **prompts and tool allowlists**; you can run them under any harness that accepts a prompt file plus a deny-by-default tool list.

Two publicly available reference choices:

- **[Kiro CLI](https://kiro.dev/docs/cli/)** — Amazon's coding-agent CLI. Used in reference walkthroughs because it supports prompt files, explicit tool allowlists, and a read-only mode that satisfies CONSTITUTION §1 (non-intrusive by default).
- **[Strands Agents SDK](https://strandsagents.com/)** ([GitHub](https://github.com/strands-agents/sdk-python)) — Open-source, model-agnostic agent SDK. Used as the reference for **Phase 4** ongoing-optimization agents (Discovery Option 5), where a longer-lived runtime is acceptable by explicit customer opt-in.

> **Both are referenced for convenience, not required.** Any agent harness that lets you pin a prompt, restrict tools, and inspect outputs is acceptable under the Constitution.

## Schema validation (optional)

To validate discovery bundles locally:

- `npx ajv-cli` (Node.js) — or any JSON Schema validator
- The schema: `schemas/discovery-bundle.schema.json`

## Fallback: no agent CLI available

If the customer environment cannot run an agent CLI (corporate policy, air-gap, sovereignty), ACMF degrades cleanly:

1. **Use Discovery Option 2** — run the source adapter's self-export script directly. Same JSON output (`discovery-bundle.json`); the agent's "questions" become explicit CLI invocations in the script.
2. **Run analysis offline** — take the resulting bundle to any environment with LLM access and feed it to the same analysis prompt manually (any chat client, any model).
3. **Pure human mode** — the prompts work as structured checklists. Every prompt section corresponds to a section in `templates/assessment-report.md`. You get the same methodology; it runs at human pace instead of agent pace.

The minimum viable ACMF run requires **bash**, **kubectl**, **jq**, and a human who can read the phase docs.

## Air-gapped customers

- Default to **Option 2** (self-export script) for discovery.
- Use **Option 1** (manifest-only) if even kubectl access is restricted.
- Run the assessment prompt on a delivery-side workstation that can reach an LLM.
- Skip Option 4 unless the customer explicitly approves a one-shot agent run.
- Skip Option 5 entirely.
