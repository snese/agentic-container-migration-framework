# ECS vs EKS vs App Runner — Target Selection

> TL;DR: Don't default. Decide per-workload using the matrix below.

## Decision Matrix

| Factor | → EKS | → ECS Fargate | → App Runner |
|--------|-------|---------------|--------------|
| K8s API usage (CRDs, operators) | Heavy | None / minimal | None |
| Service mesh (Istio, Linkerd) | Yes | No | No |
| Stateful workloads | Yes | Limited (EFS only) | No |
| Team K8s expertise | High | Medium | Low |
| Operational overhead tolerance | High (standard) / Low (Auto Mode) | Low | Lowest |
| Cost sensitivity | Medium | High | High (per-request) |
| Workload type | Mixed / system | Stateless services / batch | Single HTTP service |
| Networking complexity | Custom CNI, NetworkPolicies | Standard VPC | Public HTTPS only |
| Compute management | Self-managed / Karpenter / Auto Mode | Fully managed (Fargate) | Fully managed |

## EKS Auto Mode vs Standard EKS

EKS Auto Mode (GA re:Invent 2024) automates compute provisioning, scaling, and patching. It changes the ECS-vs-EKS calculus:

- **When Auto Mode tips toward EKS**: Customer needs K8s APIs (CRDs, operators) but wants ECS-level operational simplicity. Auto Mode eliminates the "EKS needs more ops" argument.
- **When ECS still wins**: No K8s requirement, simpler programming model, Docker Compose compatibility (ECS Express Mode).
- **Key difference**: Auto Mode still requires K8s knowledge for workload manifests. ECS/App Runner don't.
- **For Anthos migrations**: Auto Mode is often the right default — Anthos teams already know K8s manifests, and Auto Mode removes the node management burden they previously delegated to Anthos/GKE.

## Anthos → AWS Mapping Heuristics

Anthos clusters tend to be over-engineered. Don't blindly map 1:1.

- Anthos Service Mesh → ECS Service Connect (often sufficient) or Istio on EKS (only if mesh is core) or Amazon VPC Lattice (service-to-service networking)
- Anthos Config Sync → GitOps with ArgoCD/Flux on EKS, or Terraform Cloud for ECS
- Anthos Policy Controller → OPA Gatekeeper / Kyverno on EKS, or AWS Config + SCPs for ECS
- Workload Identity → IRSA / EKS Pod Identity (EKS) or Task Role (ECS)

> ⚠️ **Do NOT recommend AWS App Mesh** — it is deprecated (2024) with no new feature development.

## When to split a cluster across targets

Yes, split. Anthos clusters often run a mix:

- Platform/system pods → EKS (Auto Mode)
- Stateless app services → ECS Fargate (cheaper, simpler)
- Batch jobs → ECS on Fargate Spot or AWS Batch
- Single-purpose HTTP APIs → App Runner

Split by namespace mapping. Document the rationale per group.

## Anti-patterns

- ❌ "Customer used Anthos so we use EKS" — laziness, not strategy
- ❌ "Everything to ECS to save money" — breaks operator-dependent workloads
- ❌ "App Runner for everything stateless" — egress + cold-start surprises
- ❌ "Standard EKS because Auto Mode is too new" — Auto Mode is GA and production-ready

## Open questions

These remain open and are tracked in [`ROADMAP.md`](../../ROADMAP.md):

- Concrete cost models per pattern (need real customer baselines)
- EKS Auto Mode vs ECS Fargate — detailed cost comparison for equivalent workloads
- Multi-region story per target
