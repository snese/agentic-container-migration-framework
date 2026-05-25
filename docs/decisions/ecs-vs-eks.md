# ECS vs EKS Decision Tree (v2) — For Container Platform Migration

> **Context**: This decision tree is designed for the ACMF migration scenario — workloads moving FROM another Kubernetes platform (GKE Enterprise, AKS, OpenShift, Rancher) TO AWS. Every claim is traceable to a public AWS source.

---

## Level 1: EKS vs ECS — The Top-Level Decision

The primary discriminator is **Kubernetes API dependency**:

```
Source workload characteristics
│
├─ Uses Kubernetes-native patterns? ─────────────────────────────────────────→ [A]
│  (CRDs, operators, Helm charts, admission webhooks,
│   service mesh CRDs, GitOps controllers, StatefulSets
│   with PV lifecycle, DaemonSets, Pod Security Standards)
│
├─ Stateless services with simple networking? ───────────────────────────────→ [B]
│  (HTTP APIs, queue consumers, batch jobs,
│   no CRDs/operators, no service mesh CRDs)
│
└─ Mixed portfolio? ─────────────────────────────────────────────────────────→ [C]
   (Some namespaces are K8s-native, others are simple services)
```

### Path [A] → EKS

**Rationale**: Manifest portability. K8s workloads using CRDs, operators, Helm, and service mesh CRDs can be deployed to EKS with minimal rewrite — primarily annotation/ingress-class changes. Replatforming to ECS would require re-architecting these patterns.

**Source**: [AWS Blog — "Amazon ECS vs Amazon EKS: making sense of AWS container services"](https://aws.amazon.com/blogs/containers/amazon-ecs-vs-amazon-eks-making-sense-of-aws-container-services/):
> "Teams choose Kubernetes for its vibrant ecosystem and community, consistent open source APIs, and broad flexibility."

### Path [B] → ECS

**Rationale**: Operational simplicity. ECS eliminates the Kubernetes control plane abstraction entirely — no etcd, no API server, no kubelet. For workloads that don't need the K8s API, this removes an entire layer of operational complexity.

**Source**: [AWS Blog](https://aws.amazon.com/blogs/containers/amazon-ecs-vs-amazon-eks-making-sense-of-aws-container-services/):
> "What customers tell us they love most about Amazon ECS is the simplicity it provides. Amazon ECS delivers an AWS-opinionated solution for running containers at scale."

### Path [C] → Hybrid (EKS + ECS)

**Rationale**: Containers are portable between services. Use EKS for the K8s-native workloads, ECS for the simple services. Both share ECR, CloudWatch, IAM, VPC, and ALB/NLB.

**Source**: [AWS Blog](https://aws.amazon.com/blogs/containers/amazon-ecs-vs-amazon-eks-making-sense-of-aws-container-services/):
> "Choosing a container service at AWS does not need to be a binary decision. Amazon ECS and Amazon EKS work together seamlessly."

---

## Level 1 — Decision Matrix

| Decision Factor | → EKS | → ECS |
|---|---|---|
| **K8s API usage** (CRDs, operators, webhooks) | Any K8s-native pattern | No K8s API dependency |
| **Manifest portability** from source | Direct — Deployments, Services, Ingress carry over | Requires rewrite to Task Definitions |
| **Team expertise** | K8s-experienced team (from GKE/AKS/OCP) | AWS-first or platform-agnostic team |
| **Operational model** | Team manages cluster upgrades + add-ons | AWS manages orchestration fully |
| **Ecosystem** | Helm, Kustomize, ArgoCD, Istio, OPA, Prometheus | AWS-native: CloudMap, Service Connect, CodeDeploy |
| **Multi-cluster / federation** | Native (ArgoCD ApplicationSets, Istio multi-cluster) | Limited (per-cluster only) |
| **Pricing** | $0.10/hr per cluster + compute | Compute only (no cluster fee) |
| **Control plane availability** | AWS-managed (3-AZ etcd) | Fully abstracted (no control plane concept) |

**Sources**:
- EKS pricing: [aws.amazon.com/eks/pricing](https://aws.amazon.com/eks/pricing/) — "$0.10 per hour for each Amazon EKS cluster"
- ECS simplicity: [AWS Containers decision guide](https://docs.aws.amazon.com/decision-guides/latest/containers-on-aws-how-to-choose/choosing-aws-container-service.html)

---

## Level 2A: EKS Compute Model

Once you've chosen EKS, select the compute model:

```
EKS cluster provisioned
│
├─ Want minimal ops + don't need custom AMI? ────────────→ EKS Auto Mode
│  (AWS manages nodes, scaling, add-ons;
│   Bottlerocket only; Karpenter-based under the hood)
│
├─ Need custom AMI / advanced instance selection? ───────→ Karpenter (self-managed)
│  (Full EC2NodeClass control, custom AMI, multi-arch,
│   advanced consolidation policies)
│
├─ Predictable steady-state + simple ops? ───────────────→ Managed Node Groups
│  (ASG-backed, explicit scaling, familiar EC2 model)
│
├─ Need per-pod isolation / sandbox tenants? ────────────→ Fargate profiles
│  (Firecracker microVM per pod; no DaemonSets,
│   no GPU, no EBS, no privileged, no hostNetwork)
│
└─ GPU / ML inference / CUDA? ───────────────────────────→ Karpenter or MNG
   (with GPU instance families: g5, g6, p4, p5;
    NOT Fargate — no GPU support)
```

### EKS Auto Mode

- **What it is**: AWS-managed compute using Karpenter under the hood. Nodes run Bottlerocket AMI. AWS manages Karpenter, ALB Controller, VPC CNI, EBS CSI, Pod Identity Agent.
- **Best for**: GKE Enterprise migrations where the team wants K8s API compatibility WITHOUT the node management burden that GKE Enterprise previously provided.
- **Limitations**: No custom AMI; Bottlerocket only; per-node management fee on top of EC2 pricing.
- **Default NodePools**: `general-purpose` (C/M/R gen4+, On-Demand) and `system` (critical add-ons).

**Source**: [EKS Auto Mode Best Practices](https://docs.aws.amazon.com/eks/latest/best-practices/automode.html):
> "EKS Auto Mode uses a Karpenter-based system that automatically provisions EC2 instances in response to pod requests. These instances run on Bottlerocket AMIs with pre-installed add-ons."

### Karpenter (self-managed)

- **What it is**: Open-source JIT node provisioner. Customer installs + manages the Karpenter controller.
- **Best for**: Large fleets (1000+ nodes), custom AMI requirements, multi-arch (ARM + x86), advanced consolidation.
- **When over Auto Mode**: Custom AMI, specific instance pinning, fleet >1000 nodes (management fee adds up), multi-cluster consistency.

**Source**: [EKS Best Practices — Data Plane Scaling](https://docs.aws.amazon.com/eks/latest/best-practices/scale-data-plane.html):
> "Managed node groups and Karpenter are recommended for large scale clusters."

**Source**: [Salesforce case study (AWS blog)](https://aws.amazon.com/blogs/architecture/how-salesforce-migrated-from-cluster-autoscaler-to-karpenter-across-their-fleet-of-1000-eks-clusters/)

### Managed Node Groups

- **Best for**: Predictable steady-state, explicit capacity control, compliance requirements that mandate visible ASG resources.
- **When over Karpenter/Auto Mode**: Stable replica counts, not Spot-aggressive, want explicit AMI lifecycle control via ASG.

**Source**: [EKS Managed Node Groups docs](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)

### Fargate Profiles (EKS)

- **Best for**: Per-namespace isolation boundary (Firecracker microVM), untrusted workloads, sandbox tenants.
- **Hard limitations** (do NOT pick if workload needs these):
  - ❌ DaemonSets
  - ❌ Privileged containers, `hostNetwork`, `hostPath`, `hostPort`
  - ❌ GPU instances
  - ❌ Persistent EBS volumes (EFS only)
  - ❌ Pods beyond published vCPU/memory ceilings

**Source**: [EKS Fargate considerations](https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html#fargate-considerations)

---

## Level 2B: ECS Compute Model

Once you've chosen ECS, select the launch type:

```
ECS service/task defined
│
├─ Spiky/unpredictable load + no GPU? ──────────────────→ Fargate (on-demand)
│  (Per-task billing, no capacity planning,
│   max 16 vCPU / 120 GB memory per task)
│
├─ Batch / interruption-tolerant? ──────────────────────→ Fargate Spot
│  (Up to ~70% off on-demand; 2-min interruption notice)
│
└─ GPU / custom AMI / privileged / high utilization? ───→ EC2 launch type
   (Full instance control, Daemon scheduling,
    any instance type including GPU)
```

### Fargate Task Size Limits

| vCPU | Memory range | OS |
|------|---|---|
| 0.25 | 0.5–2 GB | Linux |
| 0.5 | 1–4 GB | Linux |
| 1 | 2–8 GB | Linux, Windows |
| 2 | 4–16 GB | Linux, Windows |
| 4 | 8–30 GB | Linux, Windows |
| 8 | 16–60 GB | Linux |
| 16 | 32–120 GB | Linux |

**Source**: [ECS task sizing (Fargate launch type)](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html)

### When EC2 Launch Type Wins

Use EC2 when **at least one** applies:
1. **GPU** — Fargate has no GPU SKUs
2. **High steady-state utilization** (>50% sustained) — right-sized EC2 fleet is cheaper
3. **Custom AMI** — FIPS, custom kernel, compliance scanning
4. **Privileged / hostNetwork** — Fargate disallows both
5. **Daemon workloads** — one task per host (log shippers, security agents)

**Source**: [ECS launch type comparison](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/launch_types.html)

---

## Level 3: Operational Patterns (post-selection)

### For EKS migrations (from GKE Enterprise / AKS / OpenShift):

| Source Pattern | → AWS Target Pattern | Notes |
|---|---|---|
| Config Sync / Flux | ArgoCD or Flux on EKS | ArgoCD has higher adoption for multi-cluster |
| Anthos Service Mesh (Istio-based) | Istio on EKS | 1:1 API compatibility |
| Policy Controller (OPA) | OPA Gatekeeper or Kyverno | Direct ConstraintTemplate migration |
| GKE Workload Identity | EKS Pod Identity | Preferred over IRSA for new setups |
| GKE Ingress / Gateway API | AWS Load Balancer Controller + Gateway API | `gatewayClassName` change only |
| vSphere CSI StorageClass | EBS CSI (`gp3`) or EFS CSI (RWX) | Data migration required |

### For ECS migrations:

| Source Pattern | → AWS Target Pattern | Notes |
|---|---|---|
| K8s Service + DNS | ECS Service Connect | Replaces in-cluster DNS + basic mesh |
| K8s Ingress | Application Load Balancer | Native ECS integration |
| K8s Secrets | AWS Secrets Manager + ECS integration | Task-level injection |
| K8s RBAC | IAM Task Roles + IAM conditions | Per-task identity |
| K8s HPA | ECS Application Auto Scaling | Target tracking or step policies |
| K8s Deployment (rolling) | ECS rolling update or Blue/Green via CodeDeploy | Built-in |

---

## Migration-Specific Decision Factors

For workloads migrating FROM Kubernetes to AWS:

| Factor | Strong EKS Signal | Strong ECS Signal |
|---|---|---|
| Source uses CRDs / custom controllers | ✅ | ❌ (would need rewrite) |
| Source uses Helm charts extensively | ✅ (deploy as-is) | ❌ (convert to Task Defs) |
| Source has service mesh (Istio/Linkerd) | ✅ (Istio runs on EKS) | Consider VPC Lattice |
| Source is stateless HTTP microservices only | Either | ✅ (simpler ops) |
| Team has deep K8s expertise (from source) | ✅ (minimal ramp-up) | Ramp-up on ECS model |
| Customer wants to eliminate K8s complexity | ❌ | ✅ (escape K8s entirely) |
| Multi-cluster federation needed | ✅ (ArgoCD, Istio multi-cluster) | ❌ |
| Cost #1 priority, small scale | Either | ✅ (no cluster fee) |
| Cost #1 priority, large scale | ✅ (cluster fee amortized) | Either |
| Regulatory per-workload isolation | ✅ (Fargate profiles) | ✅ (Fargate task isolation) |

---

## Pricing Comparison (simplified)

| Component | EKS | ECS |
|---|---|---|
| Control plane | $0.10/hr per cluster (~$73/mo) | $0 (included) |
| Compute (Fargate) | Per-pod vCPU + memory | Per-task vCPU + memory |
| Compute (EC2) | Standard EC2 pricing | Standard EC2 pricing |
| Auto Mode fee | Per-node management fee | N/A |
| Add-ons (ALB Controller, CSI) | Customer-managed (or Auto Mode) | Built-in |

**Source**: [EKS pricing](https://aws.amazon.com/eks/pricing/) — "$0.10 per hour for each Amazon EKS cluster" (standard support); extended support adds $0.50/hr.

---

## Quick Reference — Decision Flowchart (ASCII)

```
START: Workload migrating from K8s platform to AWS
│
│  Q1: Does it USE the Kubernetes API?
│      (CRDs, operators, Helm, admission webhooks, mesh CRDs)
│
├─ YES ──→ EKS
│           │
│           │  Q2: Ops preference?
│           ├─ Minimal ops, standard workloads ──→ EKS Auto Mode
│           ├─ Custom AMI / large fleet ─────────→ Karpenter
│           ├─ Steady-state, explicit control ───→ Managed Node Groups
│           └─ Per-pod isolation needed ─────────→ Fargate profiles
│
├─ NO ───→ ECS
│           │
│           │  Q2: Compute needs?
│           ├─ Serverless, spiky ────────────────→ Fargate
│           ├─ Batch, interrupt-OK ──────────────→ Fargate Spot
│           └─ GPU / privileged / daemon ────────→ EC2 launch type
│
└─ MIXED ──→ Hybrid (EKS + ECS)
             Split by namespace: K8s-native → EKS, simple → ECS
             Shared: ECR, CloudWatch, IAM, VPC, ALB/NLB
```

---

## Sources

| # | Source | URL | Used for |
|---|---|---|---|
| 1 | AWS Blog — ECS vs EKS | https://aws.amazon.com/blogs/containers/amazon-ecs-vs-amazon-eks-making-sense-of-aws-container-services/ | Simplicity vs flexibility framing |
| 2 | AWS Decision Guide — Containers | https://docs.aws.amazon.com/decision-guides/latest/containers-on-aws-how-to-choose/choosing-aws-container-service.html | Service selection framework |
| 3 | EKS Auto Mode Best Practices | https://docs.aws.amazon.com/eks/latest/best-practices/automode.html | Auto Mode architecture + limitations |
| 4 | EKS Pricing | https://aws.amazon.com/eks/pricing/ | Cluster fee ($0.10/hr) |
| 5 | ECS Task Sizes (Fargate) | https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html | vCPU/memory matrix |
| 6 | EKS Fargate Considerations | https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html | Fargate profile limitations |
| 7 | EKS Data Plane Scaling | https://docs.aws.amazon.com/eks/latest/best-practices/scale-data-plane.html | MNG + Karpenter recommendation |
| 8 | ECS Launch Types | https://docs.aws.amazon.com/AmazonECS/latest/developerguide/launch_types.html | Fargate vs EC2 feature comparison |
| 9 | Salesforce Karpenter at 1000 clusters | https://aws.amazon.com/blogs/architecture/how-salesforce-migrated-from-cluster-autoscaler-to-karpenter-across-their-fleet-of-1000-eks-clusters/ | Large-scale Karpenter validation |
