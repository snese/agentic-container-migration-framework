# EKS Compute Model — Auto Mode vs Karpenter vs Managed Node Groups vs Fargate Profiles

> Once you've decided on EKS over ECS (see [`ecs-vs-eks.md`](./ecs-vs-eks.md)), the next decision is **which compute model** runs your pods. EKS now exposes four supported options; pick per-cluster (or per-node-pool), not org-wide.

## Decision matrix

| Factor | Auto Mode | Karpenter (self-managed) | Managed Node Groups | Fargate profiles |
|---|---|---|---|---|
| Node provisioning model | AWS-managed, JIT | Customer-installed JIT autoscaler | Static / ASG-backed pools | Per-pod, AWS-managed |
| Operational overhead | Lowest | Medium | Medium-high | Lowest (per-pod) |
| Spot support | ✅ Built-in | ✅ Native, mature | ✅ Via launch template | ❌ |
| Custom NodeClass / AMI | ❌ Limited | ✅ Full control | ✅ Custom launch template | ❌ |
| Bottlerocket-only constraint | ✅ (Bottlerocket-based) | Customer choice | Customer choice | N/A |
| GPU instances | ✅ | ✅ | ✅ | ❌ |
| DaemonSets | ✅ | ✅ | ✅ | ❌ Not supported |
| Privileged pods, `hostNetwork`, `hostPath` | ✅ | ✅ | ✅ | ❌ Not supported |
| Per-pod kernel-level isolation | ❌ | ❌ | ❌ | ✅ (Firecracker microVM) |
| Best for fleet size | Small–medium | Medium–very large | Predictable steady-state | Sandbox / per-namespace |
| Pricing | EKS control plane + EC2 + Auto Mode management fee | EC2 only (Karpenter is free) | EC2 only | Per-pod vCPU/GB-hour |

## When Auto Mode wins

[EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html) (GA at re:Invent 2024) is the right default when:

- Customer wants **K8s API + ECS-level operational simplicity**.
- Cluster is small-to-medium and the team doesn't want to operate Karpenter.
- Bottlerocket as the node OS is acceptable.
- Workloads don't need exotic NodeClass configurations.
- "Just give me a cluster that scales" is the goal.

This is the **default recommendation for GKE Enterprise on VMware → EKS** migrations: those teams already understand K8s manifests, and Auto Mode removes the node management burden GDC previously absorbed.

## When Karpenter still wins

[Karpenter](https://karpenter.sh/) remains the right call when:

- **Custom NodeClass / NodePool** needs (specific instance families, custom AMIs,
  custom userdata, IMDS settings, multi-arch fleets).
- **Very large fleets** (thousands of nodes) where Auto Mode's management fee is
  material vs running Karpenter directly.
- **Advanced consolidation** policies tuned by an SRE team (custom expiration,
  drift detection thresholds, weighted bin-packing).
- **Multi-cluster fleet** where you want one Karpenter configuration story and
  Auto Mode's per-cluster opinionation creates inconsistency.
- Customer is **already** running Karpenter at scale and would gain little by
  switching.

## When Managed Node Groups win

[Managed Node Groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html) win when:

- **Predictable steady-state workloads** with stable replica counts (think
  long-running platform services, not bursty app workloads).
- Customer is **not Spot-aggressive** and doesn't need JIT scale-out.
- **Simple ops model** is a hard requirement — managed lifecycle (AMI rolls,
  K8s version upgrades) without introducing a third-party autoscaler.
- Compliance / audit teams want **explicit ASG resources** they can observe and
  bound directly.
- Mixed with Fargate profiles for system pods on a stable baseline.

## When Fargate profiles win

[EKS on Fargate](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html) (Fargate profiles) wins as a **per-namespace or per-selector** carve-out when:

- **Sandbox / multi-tenant** isolation: untrusted workloads run in a Firecracker
  microVM, not on a shared node.
- **Per-namespace isolation** boundary maps to the Fargate profile selector.
- Workload is small, stateless, and the per-pod billing model is favorable.

**Hard limitations** (do not pick Fargate profiles if the workload needs any of these):

- ❌ DaemonSets — there is no host to run them on.
- ❌ Privileged containers, `hostNetwork`, `hostPath`, `hostPort`.
- ❌ GPU / accelerated instances.
- ❌ Persistent EBS volumes (EFS only).
- ❌ Custom CNI / NetworkPolicy enforcement beyond what Fargate exposes.
- ❌ Pods larger than the published Fargate vCPU/memory ceilings.

Source: [Fargate considerations for EKS](https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html#fargate-considerations).

## Hybrid patterns

A real EKS cluster usually mixes models:

- **Platform/system workloads** (CoreDNS, ingress controllers, observability) → Managed Node Groups *or* Auto Mode.
- **Bursty stateless apps** → Auto Mode or Karpenter.
- **GPU / batch** → Karpenter with a GPU NodePool.
- **Untrusted / sandbox tenants** → Fargate profile.

## Version-skew gotchas

Mixing compute models means tracking **two upgrade clocks** per cluster:

- **Managed Node Groups** roll AMIs through the EKS managed-node lifecycle; the kubelet version is bound to the node group's `version` field and only moves when you update it.
- **Karpenter** chooses the AMI per-NodePool via the [`EC2NodeClass`](https://karpenter.sh/docs/concepts/nodeclasses/) resource. With `amiSelectorTerms` you can pin to an alias (e.g. `al2023@latest`) or a specific AMI ID. Karpenter does **not** auto-bump kubelet to match the EKS control-plane minor version — a control-plane upgrade can leave Karpenter-managed nodes one or two minors behind unless you bump the NodeClass.
- **Auto Mode** manages the node OS (Bottlerocket) and kubelet for you and stays within EKS's supported skew window.
- **Fargate profiles** track the control-plane version automatically; no node-side action needed.

Keep an explicit checklist per cluster: control-plane minor → Managed NG version → Karpenter NodeClass AMI → add-ons. [EKS version skew policy](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html). See also upstream [Kubernetes version skew policy](https://kubernetes.io/docs/setup/version-skew-policy/) (kubelet may be up to 3 minor versions behind kube-apiserver as of K8s ≥ 1.28).

## References

- [Amazon EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [Karpenter — official docs](https://karpenter.sh/)
- [EKS Managed Node Groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)
- [EKS Fargate profiles](https://docs.aws.amazon.com/eks/latest/userguide/fargate-profile.html)
- [Fargate considerations / limitations](https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html#fargate-considerations)
