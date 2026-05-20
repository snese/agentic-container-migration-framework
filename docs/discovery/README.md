# Discovery Options

Five options, ordered from least to most intrusive. Pick based on customer policy + trust level.

## Option 1: Manifest-Only

**Mechanism:** Customer ships Helm charts, K8s YAML, or GitOps repo (Config Sync, ArgoCD, Flux). We analyze offline.

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

**Mechanism:** We provide a pure bash script using `kubectl` (and optionally platform-specific CLIs like `gcloud`, `govc`, `az`, or `oc` depending on the source adapter). All commands are read-only. Customer runs the script and ships the output bundle.

**Pros:**
- Auditable (customer reads every line)
- Air-gap friendly (no outbound traffic during run)
- No long-running process

**Cons:**
- No LLM analysis during run (pure data dump)
- Customer must transfer bundle out-of-band

**Use when:** Air-gapped, regulated, or customer needs to vet every command.

Available scripts:
- GKE Enterprise on VMware: [`scripts/discovery/gke-enterprise-vmware-export.sh`](../../scripts/discovery/gke-enterprise-vmware-export.sh)
- GKE: [`scripts/discovery/gke-export.sh`](../../scripts/discovery/gke-export.sh) (stub)
- AKS: [`scripts/discovery/aks-export.sh`](../../scripts/discovery/aks-export.sh) (stub)
- OpenShift: [`scripts/discovery/openshift-export.sh`](../../scripts/discovery/openshift-export.sh) (stub)
- Rancher: [`scripts/discovery/rancher-export.sh`](../../scripts/discovery/rancher-export.sh) (stub)

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

> ⚠️ **This is the only discovery option where data leaves the customer's environment.** All other options keep the bundle on-premises until the customer explicitly shares it. Ensure the customer's security and compliance teams approve this approach before proceeding.

---

## Option 4: Agent-Assisted Ephemeral Run ⭐ (recommended default)

**Reference runtime:** [Kiro CLI](https://kiro.dev/docs/cli/) in [headless mode](https://kiro.dev/docs/cli/headless/). Any agent harness with equivalent guarantees (non-interactive execution, tool allowlisting, structured output) works; ACMF does not lock you in.

**Mechanism:** Customer installs the agent CLI temporarily. We provide a prompt file + tool allowlist guidance. Customer runs, gets structured output, can uninstall after.

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
# Customer side — Kiro CLI headless mode.
# Verify exact flags against your installed version:
#   kiro-cli --help
#   https://kiro.dev/docs/cli/headless/

export KIRO_API_KEY="<customer-provisioned-key>"

kiro-cli chat --no-interactive \
  --trust-tools=read,grep,execute_bash \
  "$(cat prompts/discovery/gke-enterprise-vmware.prompt.md)" \
  > discovery-bundle.json

# Validate output against schema
npx ajv-cli validate -s schemas/discovery-bundle.schema.json -d discovery-bundle.json

# Encrypt and share via agreed channel (example using age encryption)
# age: https://github.com/FiloSottile/age — modern file encryption tool
age -r <recipient-public-key> -o discovery-bundle.json.age discovery-bundle.json
```

> **Note:** Kiro CLI's flag surface evolves across releases. The recipe above reflects [Kiro CLI 2.x headless mode](https://kiro.dev/docs/cli/headless/). Verify `--trust-tools` categories and authentication method against your installed version. The core pattern (non-interactive + tool allowlist + prompt as input) is stable across versions.

**Skills:** The discovery prompt can also be packaged as a [Kiro Skill](https://kiro.dev/changelog/cli/1-24/) for progressive context loading in complex multi-cluster environments. This is optional — the raw prompt file works standalone.

**Optional MCP augmentation:** MCP servers (e.g. AWS Knowledge MCP) can give the agent richer context during discovery. This is **opt-in** and disabled by default — see [`mcp-augmentation.md`](./mcp-augmentation.md).

See [`prompts/discovery/gke-enterprise-vmware.prompt.md`](../../prompts/discovery/gke-enterprise-vmware.prompt.md).

---

## Option 5: Persistent Agent Runtime (opt-in, optimization phase only)

> **Status: placeholder — no reference implementation in repo today.** Tracked in [ROADMAP.md](../../ROADMAP.md) under Phase 4.

**Reference runtime:** [Strands Agents SDK](https://strandsagents.com/) ([GitHub](https://github.com/strands-agents/sdk-python)) — open-source, model-agnostic. Any persistent runtime under customer control works.

**Mechanism:** Longer-lived agent running in customer env for ongoing optimization recommendations.

**Use when:** Phase 4 (Modernize) only, with explicit customer opt-in. **Not for discovery.**

---

## Choosing

```
Air-gapped or extreme policy?              → Option 1 or 2
Want auditability + automation?            → Option 4 (agent-assisted)
Online + trusted + want fastest path?      → Option 3 (data leaves customer env)
Phase 4 ongoing optimization?              → Option 5
Default recommendation:                    → Option 4
```
