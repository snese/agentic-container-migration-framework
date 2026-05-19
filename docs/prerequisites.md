# ACMF Prerequisites & Tooling

What a customer or delivery team needs installed to run ACMF, and what to do when something is unavailable.

## Discovery option → tools required

| Option | Required tools | Optional |
|---|---|---|
| 1. Manifest-only | git (customer-side), `helm template` if charts | `kustomize` |
| 2. Self-export script | `bash` ≥ 4, `kubectl`, `gcloud` (Anthos), `govc` (VMware), `jq` | `age` for encryption |
| 3. Read-only credentials | `kubectl` (delivery side), short-lived ServiceAccount on customer cluster | VPN / network access |
| 4. Agent-assisted ephemeral run ⭐ | A coding-agent CLI with tool-allowlisting + a recent LLM | An offline-capable model for air-gapped runs |
| 5. Persistent agent runtime (Phase 4 only) | Same model access + a long-running runtime under customer control | Container image registry to host the agent |

## Reference agent runtimes

ACMF does not require any specific vendor runtime. The framework ships **prompts and tool allowlists**; you can run them under any harness that accepts a prompt file plus a deny-by-default tool list.

Two publicly available reference choices:

- **[Kiro CLI](https://kiro.dev/docs/cli/installation/)** — Amazon's coding-agent CLI. Used in our reference walkthroughs because it supports prompt files, explicit tool allowlists, and a `--no-write` mode that satisfies CONSTITUTION §1 (non-intrusive by default). Install path is publicly documented; uninstall is a single command. Requires a Builder ID for auth.
- **[Strands Agents SDK](https://strandsagents.com/)** ([GitHub](https://github.com/strands-agents/sdk-python)) — Open-source, model-agnostic agent SDK from AWS. Used as the reference for **Phase 4** ongoing-optimization agents (Discovery Option 5), where a longer-lived runtime is acceptable by explicit customer opt-in. Strands does not require AWS hosting; it can run on any infrastructure the customer controls.

> **Both are referenced for convenience, not required.** Any agent harness that lets the customer pin a prompt, restrict tools, and inspect outputs is acceptable under the Constitution.

## Fallback path (no agent CLI available)

If neither Kiro CLI nor Strands can be installed in the customer environment (corporate policy, air-gap, sovereignty), ACMF degrades cleanly:

1. **Use Discovery Option 2 (self-export script).** Same data shape (`discovery-bundle.json`); the prompt-style "questions" the agent would have asked become explicit `kubectl`/`gcloud`/`govc` invocations in the script.
2. **Run the analysis prompt offline.** Take the resulting bundle to a delivery-side workstation that *can* reach an LLM, and feed it to the same analysis prompt manually (any chat client, any model). The prompt is the same file, version-controlled.
3. **For pure-bash environments** with no LLM access at all, ACMF's analysis prompts double as **structured human checklists** — every prompt section corresponds to a section in `assessment-report.md`. The framework is still useful; it just runs at SA pace, not agent pace.

The minimum viable ACMF run requires `bash`, `kubectl`, and a human who can read the phase docs. Everything else is leverage.

## Versions we currently test against

| Tool | Tested version |
|---|---|
| Kubernetes (source clusters) | 1.27 – 1.31 |
| `kubectl` | latest stable |
| `gcloud` | latest stable |
| `govc` (VMware) | 0.40+ |
| Kiro CLI | latest stable (rolling) |
| Strands SDK | 0.x (open source, evolving) |
| Terraform | 1.6+ |
| Helm | 3.13+ |

When a version-specific gotcha bites us, we record it in the relevant adapter README, not here.

## Air-gapped customers

- Default to **Option 2** for discovery.
- Use **Option 1** for the assessment prompt run (delivery side, online).
- Skip Option 4 unless the customer explicitly approves a one-shot agent run.
- Skip Option 5 entirely.
