# ECS vs EKS vs App Runner — Target Selection

> **TL;DR:** Don't default. Decide per-workload using the matrix below.

## Decision Matrix

| Factor | → EKS | → ECS Fargate | → App Runner |
|---|---|---|---|
| K8s API usage (CRDs, operators) | Heavy | None / minimal | None |
| Service mesh (Istio, Linkerd) | Yes | No | No |
| Stateful workloads | Yes | Limited (EFS only) | No |
| Team K8s expertise | High | Medium | Low |
| Operational overhead tolerance | High | Low | Lowest |
| Cost sensitivity | Medium | High | High (per-request) |
| Workload type | Mixed / system | Stateless services / batch | Single HTTP service |
| Networking complexity | Custom CNI, NetworkPolicies | Standard VPC | Public HTTPS only |

## Anthos → AWS Mapping Heuristics

**Anthos clusters tend to be over-engineered.** Don't blindly map 1:1.

- Anthos Service Mesh → ECS Service Connect (often sufficient) or App Mesh / EKS+Istio (only if mesh is core)
- Anthos Config Sync → GitOps with Flux/ArgoCD on EKS, or Terraform Cloud for ECS
- Anthos Policy Controller → Kyverno on EKS, or AWS Config + SCPs for ECS
- Workload Identity → IRSA (EKS) or Task Role (ECS)

## When to split a cluster across targets

**Yes, split.** Anthos clusters often run a mix:
- Platform/system pods → EKS
- Stateless app services → ECS Fargate (cheaper, simpler)
- Batch jobs → ECS on Fargate Spot or AWS Batch
- Single-purpose HTTP APIs → App Runner

Split by namespace mapping. Document the rationale per group.

## Anti-patterns

- ❌ "Customer used Anthos so we use EKS" — laziness, not strategy
- ❌ "Everything to ECS to save money" — breaks operator-dependent workloads
- ❌ "App Runner for everything stateless" — egress + cold-start surprises

## Open questions / TBD

- [ ] Concrete cost models per pattern (need real data)
- [ ] EKS Auto Mode vs ECS Fargate — when does Auto Mode tip the scale?
- [ ] Multi-region story per target
