# Target Adapter: Amazon EKS

## When to choose EKS

- Heavy K8s API usage (CRDs, operators, admission webhooks, service mesh CRs)
- Stateful workloads with complex storage or network requirements
- Strong K8s expertise on customer team (or investing in it)
- Source cluster uses GDC/GKE Enterprise features with no ECS equivalent

For stateless workloads where K8s API isn't required, consider [ECS Fargate](../ecs-fargate/README.md) — lower operational overhead and often lower cost.

## Recommended Add-ons (migration landing zone baseline)

| Add-on | Purpose | AWS Doc |
|--------|---------|---------|
| **EKS Auto Mode** (or Karpenter) | Compute management — replaces GDC node pool ops | [Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html) · [Karpenter](https://karpenter.sh/) |
| **AWS Load Balancer Controller** | ALB/NLB Ingress — replaces GCE/GKE Ingress | [Docs](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html) |
| **EKS Pod Identity Agent** | Pod-level IAM — upgrade path from Workload Identity/IRSA | [Docs](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html) |
| **Amazon VPC CNI + Network Policy Controller** | Networking + NetworkPolicy enforcement | [Docs](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html) |
| **CloudWatch Observability add-on** | Container Insights + ADOT traces | [Docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-EKS-otel.html) |
| **CoreDNS, kube-proxy, vpc-cni** | Core managed add-ons — keep current via EKS managed channel | [Managed add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html) |

## Reference Implementations

ACMF does not ship Terraform/CDK modules (Constitution §4). Use these upstream references:

- **EKS Blueprints v5 (Terraform):** https://github.com/aws-ia/terraform-aws-eks-blueprints
- **EKS Blueprints Add-ons:** https://github.com/aws-ia/terraform-aws-eks-blueprints-addons
- **CDK EKS Blueprints:** https://github.com/aws-quickstart/cdk-eks-blueprints
- **EKS Best Practices Guide:** https://aws.github.io/aws-eks-best-practices/

## Migration-Specific Configuration Notes

- **Pod Identity Agent at cluster creation** — enabling after the fact requires a rolling node replacement on affected node groups. Provision it at cluster creation. [Setup guide](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html)
- **EKS Auto Mode requires K8s ≥1.29** — GDC clusters on older versions need an in-place upgrade before migration target provisioning. Verify source version during Assess phase.
- **Deploy ArgoCD before wave 1** — if source cluster uses Anthos Config Sync, ArgoCD must be running and healthy on the target before any workloads are cut over. See [`docs/playbooks/config-sync-to-argocd.md`](../../../docs/playbooks/config-sync-to-argocd.md)
- **Istio version alignment** — if source uses Anthos Service Mesh (Istio), install the same minor version on EKS before the traffic shift wave. Version mismatch causes control-plane incompatibility in multi-cluster mesh. See [`docs/playbooks/traffic-shifting.md`](../../../docs/playbooks/traffic-shifting.md)
- **Fargate profiles on EKS** — useful for namespace-level isolation (e.g. sandbox namespaces) but do not support DaemonSets, privileged containers, or GPU. Plan workload placement during Mobilize.

## Planned Additions

EKS reference Terraform module, Helm umbrella chart, and mesh-federation live-migration pattern are tracked in [`ROADMAP.md`](../../../ROADMAP.md).
