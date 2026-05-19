# ECS vs EKS — Target Selection

> TL;DR: Don't default. Decide per-workload using the matrix below.
>
> **Compute-model selection lives elsewhere.** Once you've picked ECS or EKS, the launch-type / node-pool decision is a separate doc:
> - [ECS compute model](./ecs-compute-model.md) (Fargate vs EC2 vs Fargate Spot)
> - [EKS compute model](./eks-compute-model.md) (Auto Mode vs Karpenter vs Managed Node Groups vs Fargate profiles)
>
> **Note on App Runner:** AWS App Runner entered maintenance mode on 2026-04-30 (no new customers). It is no longer a recommended target for new container migrations; existing App Runner workloads should plan a move to ECS Fargate. See [#37](https://github.com/snese/agentic-container-migration-framework/issues/37).

## Decision Matrix

| Factor | → EKS | → ECS |
|--------|-------|-------|
| K8s API usage (CRDs, operators) | Heavy | None / minimal |
| Service mesh (Istio, Linkerd) | Yes | No |
| Stateful workloads | Yes | Limited (EFS only on Fargate) |
| Team K8s expertise | High | Medium |
| Operational overhead tolerance | High (standard) / Low (Auto Mode) | Low |
| Cost sensitivity | Medium | High |
| Workload type | Mixed / system | Stateless services / batch |
| Networking complexity | Custom CNI, NetworkPolicies | Standard VPC |
| Compute management | See [EKS compute model](./eks-compute-model.md) | See [ECS compute model](./ecs-compute-model.md) |

## EKS vs ECS — the binary question

The top-level question is: **does the workload need the Kubernetes API?** That includes CRDs, operators, admission webhooks, and service-mesh CRs. If yes → EKS. If no, and ops simplicity / cost matter more than flexibility → ECS.

EKS Auto Mode (GA re:Invent 2024) erased the old "EKS needs more ops" argument: customers who need the K8s API can now get ECS-level operational simplicity. ECS still wins when there is **no** K8s requirement — simpler programming model, Docker Compose compatibility (ECS Express Mode), and lower cognitive overhead for non-K8s teams. Detailed compute-model trade-offs are in the per-target docs linked above.

## GDC for VMware → AWS Mapping Heuristics

GDC for VMware (formerly Anthos on VMware) clusters tend to be over-engineered. Don't blindly map 1:1.

- Anthos Service Mesh → ECS Service Connect (often sufficient) or Istio on EKS (only if mesh is core) or Amazon VPC Lattice (service-to-service networking)
- Anthos Config Sync → GitOps with ArgoCD/Flux on EKS, or Terraform Cloud for ECS
- Anthos Policy Controller → OPA Gatekeeper / Kyverno on EKS, or AWS Config + SCPs for ECS
- Workload Identity → IRSA / EKS Pod Identity (EKS) or Task Role (ECS)

> ⚠️ **Do NOT recommend AWS App Mesh** — it is deprecated (2024) with no new feature development.

## When to split a cluster across targets

Yes, split. GDC for VMware clusters often run a mix:

- Platform/system pods → EKS (Auto Mode)
- Stateless app services → ECS Fargate (cheaper, simpler)
- Batch jobs → ECS on Fargate Spot or AWS Batch
- Single-purpose HTTP APIs → ECS Fargate behind ALB (App Runner is no longer recommended)

Split by namespace mapping. Document the rationale per group.

## Anti-patterns

- ❌ "Customer used GDC so we use EKS" — laziness, not strategy
- ❌ "Everything to ECS to save money" — breaks operator-dependent workloads
- ❌ "Standard EKS because Auto Mode is too new" — Auto Mode is GA and production-ready

## Open questions

These remain open and are tracked in [`ROADMAP.md`](../../ROADMAP.md):

- Concrete cost models per pattern (need real customer baselines)
- EKS Auto Mode vs ECS Fargate — detailed cost comparison for equivalent workloads
- Multi-region story per target
