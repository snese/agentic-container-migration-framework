# CAF Perspective: Governance

Governance is how the migration stays predictable: portfolio visibility, risk management, change control, cost guardrails. Container migrations introduce specific governance pitfalls — sprawling namespaces, untracked CRDs, and "shadow clusters" stood up by app teams.

## Stakeholders

- Migration program manager / PMO
- Cloud Center of Excellence (CCoE)
- Risk & compliance officer
- Finance (for budget and cost guardrails — overlaps with Business)

## Container-specific capabilities

- **Workload portfolio management.** A workload-level (not VM-level) inventory: every Deployment / StatefulSet / CronJob across every cluster, with owner, criticality, and wave assignment.
- **CRD and operator governance.** Tracking which custom controllers exist, who owns them, whether they survive the migration. This is the governance equivalent of a software bill of materials.
- **Cost guardrails for K8s.** Tag policies that map to namespaces, Kubecost / OpenCost integration, per-team budgets enforced via Cost Allocation tags + AWS Budgets.
- **Cluster lifecycle policy.** Rules for who can stand up a new cluster, what add-ons are mandatory, and how clusters are decommissioned — to prevent the post-migration sprawl that killed the previous platform.

## Key deliverables

- Wave plan with risk register (per workload: blockers, dependencies, rollback path)
- Change advisory process for cutovers (lightweight, but explicit)
- Tagging / labeling standard mapping K8s labels → AWS tags consistently
- Compliance traceability matrix (controls × workloads × evidence)
- Cost guardrails: budget alerts, anomaly detection, allocation reports

## Anti-patterns to avoid

- "Cluster-level" governance only — losing visibility into who owns workloads inside the cluster.
- Letting GDC / OpenShift's built-in policy controllers retire without replacing them with OPA/Gatekeeper or Kyverno.
- Approving the wave plan once and never updating it as discovery uncovers new dependencies.
- Treating CRD inventory as a Day-2 problem; it's a Day-0 portfolio question.

## How agentic discovery contributes

Agentic discovery produces the structured inventory governance needs but rarely gets: every workload, its labels, its CRDs, its dependencies, in a single bundle that validates against a schema. This means the risk register, wave plan, and compliance matrix can be derived from primary data, not reconstructed in spreadsheets. Subsequent agent runs detect drift between planned and observed state, feeding change control.
