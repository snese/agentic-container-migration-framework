# Discovery Options

Five options, ordered from least to most intrusive. Pick based on customer policy + trust level.

## Option 1: Manifest-Only

**Mechanism:** Customer ships Helm charts, K8s YAML, Anthos Config Sync repo (or other source-of-truth GitOps repo). We analyze offline.

**Pros:**
- Zero customer environment access
- Fully auditable inputs
- Works in air-gapped environments

**Cons:**
- Misses runtime state (actual replicas, observed traffic, drift)
- Misses external dependencies discovered only at runtime

**Use when:** Customer cannot grant any environment access; PoC/scoping phase.

---

## Option 2: Self-Export Script

**Mechanism:** We provide pure bash script using only `kubectl`, `gcloud`, `govc` (all read-only). Customer runs, ships output bundle.

**Pros:**
- Auditable (customer reads every line)
- Air-gap friendly (no outbound traffic during run)
- No long-running process

**Cons:**
- No LLM analysis during run (pure data dump)
- Customer must transfer bundle out-of-band

**Use when:** Air-gapped, regulated, or customer needs to vet every command.

See [`scripts/discovery/gke-enterprise-vmware-export.sh`](../../scripts/discovery/gke-enterprise-vmware-export.sh).

---

## Option 3: Read-Only Credentials

**Mechanism:** Customer creates short-lived (e.g. 24h) read-only ServiceAccount + kubeconfig. We run discovery from our environment.

**Pros:**
- We control execution (better quality)
- No customer effort beyond cred provisioning

**Cons:**
- Requires network connectivity (VPN, peering, or public exposure)
- Customer cedes some control

**Use when:** Online environments, established trust.

---

## Option 4: Agent-Assisted Ephemeral Run ⭐ (recommended default)

**Reference runtime:** [Kiro CLI](https://kiro.dev/docs/cli/installation/) in [headless mode](https://kiro.dev/docs/cli/headless/) (publicly available; supports `--no-interactive`, tool trust allowlist via `--trust-tools`, and API-key auth via `KIRO_API_KEY`). Any agent harness with equivalent guarantees works; ACMF does not lock you in.

**Mechanism:** Customer installs the agent CLI temporarily. We provide a prompt file + tool allowlist. Customer runs, gets structured output, can uninstall after.

**Pros:**
- Agent-driven (handles edge cases gracefully)
- Auditable prompt (customer reads it)
- Tool allowlist enforced
- No persistent process
- Output is structured JSON, easy to validate

**Cons:**
- Requires the agent CLI install (small footprint)
- LLM call from customer environment (need policy clearance)

**Fallback:** if the agent CLI cannot be installed, this option degrades cleanly to Option 2 — the same prompt is consumable as a Bash/Python runbook with no agent runtime. See [`docs/prerequisites.md`](../prerequisites.md).

**Recipe:**
```bash
# Customer side. Kiro CLI headless mode reads the prompt as a positional
# argument (no --prompt-file flag is documented today — inline via $(cat)).
# The tool allowlist uses --trust-tools (comma-separated). Output is captured
# from stdout; the prompt itself instructs the agent to emit a JSON bundle
# conforming to schemas/discovery-bundle.schema.json.

export KIRO_API_KEY="<customer-issued-key>"

kiro-cli chat --no-interactive \
  --trust-tools=read,grep,execute_bash \
  "$(cat acmf/prompts/discovery/gke-enterprise-vmware.prompt.md)" \
  > discovery-bundle.json

# Encrypt and ship
age -r <our-pubkey> -o discovery-bundle.json.age discovery-bundle.json
```

> **[VERIFICATION-PENDING]** Kiro CLI headless flags above are sourced from
> <https://kiro.dev/docs/cli/headless/> (binary name `kiro-cli`, `--no-interactive`,
> `--trust-tools`, `--trust-all-tools`, `KIRO_API_KEY`). Confirm against the
> version installed in your environment — the public docs render client-side
> and the flag surface evolves quickly (see issue
> [kirodotdev/Kiro#5423](https://github.com/kirodotdev/Kiro/issues/5423) for
> in-flight machine-readable output flags).

**Optional augmentation:** MCP servers (e.g. AWS Knowledge MCP) can give the
agent richer context during discovery. This is **opt-in** and disabled by
default — see [`mcp-augmentation.md`](./mcp-augmentation.md).

See [`prompts/discovery/gke-enterprise-vmware.prompt.md`](../../prompts/discovery/gke-enterprise-vmware.prompt.md).

---

## Option 5: Persistent Agent Runtime (opt-in, optimization phase only)

> **Status: placeholder, no reference implementation in repo today.** Strands Agents SDK is publicly available, but ACMF does not currently ship a reference recipe for Phase 4 persistent-agent runtime. Tracked in [ROADMAP.md](../../ROADMAP.md) under Phase 4.

**Reference runtime:** [Strands Agents SDK](https://strandsagents.com/) ([GitHub](https://github.com/strands-agents/sdk-python)) — open-source, model-agnostic. Any persistent runtime under customer control works.

**Mechanism:** Longer-lived agent running in customer env for ongoing optimization recommendations.

**Use when:** Phase 5 (Optimize) only, with explicit customer opt-in. **Not for discovery.**

---

## Choosing

```
Air-gapped or extreme policy?              → Option 1 or 2
Want auditability + automation?            → Option 4 (agent-assisted)
Online + trusted + want fastest path?      → Option 3
Phase 5 ongoing optimization?              → Option 5
Default recommendation:                    → Option 4
```
