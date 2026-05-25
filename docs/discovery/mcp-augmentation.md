# MCP Augmentation for ACMF Discovery

> **Status:** v0.6 design note. Disabled by default. Gated behind explicit customer opt-in.

## Why MCP at all

A coding-agent CLI doing Phase 1 (Assess) discovery without domain context will miss obvious-to-an-AWS-SA mappings:

- "This is a GKE Workload Identity ServiceAccount → on EKS that becomes IRSA *or* EKS Pod Identity."
- "This Anthos Service Mesh `VirtualService` has a header-based route → on AWS that's an ALB listener rule with header conditions, or VPC Lattice."
- "This `vsphere-csi-fast` storageClass with `storagepolicyname=gold` → on AWS that's `gp3` with provisioned IOPS."

The agent can produce the structured discovery bundle without these mappings, but the *quality* of the assessment narrative downstream improves materially when the agent can ground itself in current AWS docs and current Kubernetes guidance during discovery.

[Model Context Protocol](https://modelcontextprotocol.io/) (MCP) is the standardized way to expose those grounding sources to the agent. ACMF treats MCP as an **optional augmentation** — not a hard requirement — and explicitly bounds its threat model.

## In-scope MCP servers

ACMF currently lists two MCP servers as in-scope reference integrations. Customers can swap in equivalents.

### 1. AWS Knowledge MCP Server (AWS docs / blogs / What's New / regional availability)

- **Endpoint:** `https://knowledge-mcp.global.api.aws` (Streamable HTTP transport).
- **Transport:** remote, AWS-hosted; no AWS account required.
- **Authoritative reference:** [AWS Knowledge MCP Server](https://awslabs.github.io/mcp/servers/aws-knowledge-mcp-server) and the [GA announcement](https://aws.amazon.com/about-aws/whats-new/2025/10/aws-knowledge-mcp-server-generally-available/) (Oct 2025).
- **Topic-based search** for AWS Amplify, AWS CDK, CloudFormation, Troubleshooting domains: see [Nov 2025 announcement](https://aws.amazon.com/about-aws/whats-new/2025/11/aws-knowledge-mcp-server-topic-based-search/).
- **Note on naming:** AWS recommends migrating to the newer **AWS MCP Server** (a managed remote MCP server with IAM condition-key controls — see the [Agent Toolkit for AWS](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/getting-started-aws-mcp-server.html)). For the ACMF discovery use case (read-only docs grounding), the AWS Knowledge MCP Server remains the simpler choice; for engagements that need IAM-scoped control, prefer the AWS MCP Server.

### 2. Kubernetes MCP Server

There is no single canonical "Kubernetes MCP server"; the ecosystem has multiple competing implementations. ACMF lists three with neutral assessment so customers can pick under their own policy:

| Implementation | Source | Notes |
|---|---|---|
| [`containers/kubernetes-mcp-server`](https://github.com/containers/kubernetes-mcp-server) | Red Hat Containers org | Native Go server (not a kubectl wrapper); supports both Kubernetes and OpenShift. Most-actively-maintained option and the closest thing to a community default at time of writing. |
| [`mcp-kubernetes-server`](https://pypi.org/project/mcp-kubernetes-server/) | Independent (PyPI) | Python-based; bridges natural-language requests to kubectl-like operations. |
| [`siddjoshi/kube-mcp`](https://mcpservers.org/servers/siddjoshi/kube-mcp) | Independent | Go, supports chunked HTTP streaming and bundled troubleshooting prompts. |

> **** ACMF does not yet endorse any single Kubernetes MCP server as the reference. Customers should review each implementation's RBAC model, kubeconfig handling, and update cadence before allowlisting it for an engagement.

## Threat model implications (Constitution §1)

MCP servers expand the tool surface available to the discovery agent. That has direct implications for [`docs/CONSTITUTION.md`](../CONSTITUTION.md) §1 — *Non-intrusive by default*:

1. **Persistence.** A *remote* MCP server (e.g. AWS Knowledge MCP) is, strictly speaking, a persistent third-party service. Constitution §1 was originally drafted assuming "no persistent agent during discovery" meant nothing long-running on customer infrastructure; remote read-only MCP endpoints don't run in the customer's environment but they are still a persistent dependency the agent talks to.
2. **Egress.** MCP calls leave the customer's perimeter. Air-gapped engagements cannot use remote MCP at all.
3. **Allowlist scope.** Each MCP server exposes a tool surface; that surface must be enumerated and allowlisted, not used wholesale.

ACMF's stance, codified by the modes below:

- MCP must be **customer-controlled**: the customer either runs the MCP server locally, or pins a specific remote endpoint URL.
- MCP must be **allowlist-vetted**: every tool the agent is allowed to call from an MCP server is enumerated.
- MCP is **disabled by default in air-gapped engagements** and only enabled with explicit written customer opt-in elsewhere.

## Modes

ACMF defines three discovery modes for Phase 1:

### (a) Discovery-only (default for [Option 4](./README.md#option-4-agent-assisted-ephemeral-run--recommended-default))

- No MCP servers configured.
- Agent toolset is limited to local read-only commands (`read`, `grep`, `kubectl`-via-execute_bash, `gcloud`, `govc`, `oc`, `az`, etc.).
- This is the **default** and the only mode acceptable in air-gapped or extreme-policy engagements.

### (b) Discovery + MCP (opt-in)

- Customer reviews the MCP server inventory ahead of the run.
- Customer either runs the MCP server locally or pins an immutable remote endpoint URL.
- Customer signs off on the MCP tool allowlist.
- Outbound network must be permitted to the pinned endpoint(s) only.

### (c) Modernize (Phase 4)

- Persistent agent runtime (see [Discovery Option 5](./README.md#option-5-persistent-agent-runtime-opt-in-optimization-phase-only)) is acceptable.
- MCP usage is broadly allowed because customer trust has been established by Phases 1–3.

## Reference recipe — Option 4 with MCP enabled

This is **opt-in only**. The default Option 4 recipe in [`./README.md`](./README.md) does **not** include `--mcp-server`.

```bash
# Customer side — Option 4 + MCP (opt-in)
export KIRO_API_KEY="<customer-issued-key>"

kiro-cli chat --no-interactive \
  --trust-tools=read,grep,execute_bash \
  --mcp-server "aws-knowledge:https://knowledge-mcp.global.api.aws" \
  --mcp-server "kubernetes:http://localhost:8080/mcp" \
  "$(cat acmf/prompts/discovery/gke-enterprise-vmware.prompt.md)" \
  > discovery-bundle.json
```

> **** Kiro CLI's exact MCP CLI flag surface is not in the
> public headless docs at <https://kiro.dev/docs/cli/headless/> (only `--no-interactive`,
> `--trust-tools`, `--trust-all-tools`, and `KIRO_API_KEY` are documented). The
> `--mcp-server` flag above is illustrative — in practice MCP servers are usually
> configured via a JSON config file (e.g. the same `mcp.json` used by Claude
> Desktop / Cursor / VS Code MCP). Confirm the actual configuration mechanism
> against the version installed in your environment and update this recipe.

## Constitution amendment proposal (stub)

The author of this doc proposes the following amendment to [`docs/CONSTITUTION.md`](../CONSTITUTION.md) §1, to be tabled under the standard amendment process:

> **§1 (revised draft).** ACMF does not install long-running agents in the customer environment. Discovery, assessment, and planning rely on ephemeral agent runs, manifest snapshots, or short-lived read-only credentials.
>
> **Persistent third-party services may be queried by ephemeral agents during discovery if and only if they are (a) read-only with respect to the customer's environment, (b) customer-pinned to a specific endpoint, and (c) explicitly enumerated in the engagement's tool allowlist. Air-gapped engagements may not use any external MCP or third-party context source.**
>
> The most intrusive option a customer can pick is still bounded in time and scope.

**Open questions for the amendment PR:**

1. Should MCP server inventory be a versioned artifact (e.g. `docs/discovery/mcp-allowlist.md`) so customers can diff it across engagements?
2. Should ACMF ship a reference customer-side MCP launcher (Docker Compose for `containers/kubernetes-mcp-server` + a stdio→HTTP fastmcp proxy for AWS Knowledge MCP) so air-gapped customers have a documented opt-in path?
3. Where does this leave persistent agent runtimes (Strands, Phase 4)? §1 already carves them out as opt-in for Phase 4 only; the amendment should preserve that carve-out verbatim.

Cross-reference: see [`docs/discovery/README.md`](./README.md) for the in-context note on Option 4 + MCP, and [`docs/CONSTITUTION.md`](../CONSTITUTION.md) for the amendment process.
