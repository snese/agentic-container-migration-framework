# Discovery Options

Five options, ordered from least to most intrusive. Pick based on customer policy + trust level.

## Option 1: Manifest-Only

**Mechanism:** Customer ships Helm charts, K8s YAML, Anthos Config Sync repo. We analyze offline.

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

See [`scripts/discovery/anthos-vmware-export.sh`](../../scripts/discovery/anthos-vmware-export.sh).

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

## Option 4: Kiro CLI Ephemeral Run ⭐ (recommended default)

**Mechanism:** Customer installs `kiro` CLI temporarily. We provide a prompt file + tool allowlist. Customer runs, gets structured output, can uninstall after.

**Pros:**
- Agent-driven (handles edge cases gracefully)
- Auditable prompt (customer reads it)
- Tool allowlist enforced
- No persistent process
- Output is structured JSON, easy to validate

**Cons:**
- Requires Kiro CLI install (small footprint)
- LLM call from customer environment (need policy clearance)

**Recipe:**
```bash
# Customer side
kiro \
  --prompt-file acmf/prompts/discovery/anthos-vmware.prompt.md \
  --tools-allow "kubectl:get,kubectl:describe,gcloud:read,govc:ls" \
  --output discovery-bundle.json \
  --no-write

# Encrypt and ship
age -r <our-pubkey> -o discovery-bundle.json.age discovery-bundle.json
```

See [`prompts/discovery/anthos-vmware.prompt.md`](../../prompts/discovery/anthos-vmware.prompt.md).

---

## Option 5: Strands Agent (opt-in, optimization phase only)

**Mechanism:** Persistent agent running in customer env for ongoing optimization recommendations.

**Use when:** Phase 5 (Optimize) only, with explicit customer opt-in. **Not for discovery.**

---

## Choosing

```
Air-gapped or extreme policy?              → Option 1 or 2
Want auditability + automation?            → Option 4 (Kiro CLI)
Online + trusted + want fastest path?      → Option 3
Phase 5 ongoing optimization?              → Option 5
Default recommendation:                    → Option 4
```
