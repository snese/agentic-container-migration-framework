# Target Adapter: Amazon EKS

## When to choose EKS

- Heavy K8s API usage (CRDs, operators, mesh)
- Stateful workloads with complex storage
- Strong K8s expertise on customer team

## Patterns

- **Cluster topology:** EKS Auto Mode for greenfield, managed node groups for migration
- **GitOps:** Flux or ArgoCD (mirror Anthos Config Sync structure from GKE Enterprise sources)
- **Mesh:** Istio (1:1 from GKE Enterprise Service Mesh) or Amazon VPC Lattice (service-to-service)
- **Policy:** Kyverno (1:1 from Policy Controller) or OPA Gatekeeper
- **Identity:** EKS Pod Identity (preferred) or IRSA (legacy clusters)
- **Networking:** VPC CNI, NetworkPolicies via Calico

> ⚠️ **AWS App Mesh is deprecated** (maintenance mode 2026-04-30). Do not recommend for new migrations.

## Recommended add-ons for a migration landing zone

- **EKS Auto Mode / Karpenter** — compute management ([docs](https://docs.aws.amazon.com/eks/latest/userguide/automode.html))
- **AWS Load Balancer Controller** — replaces GCE/GKE Ingress ([docs](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html))
- **EKS Pod Identity Agent** — replaces Workload Identity / IRSA upgrade path ([docs](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html))
- **Amazon VPC CNI** — default; for NetworkPolicy enforcement add Network Policy Controller ([docs](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html))
- **CloudWatch Observability add-on** — Container Insights + ADOT ([docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-EKS-otel.html))
- **AWS Distro for OpenTelemetry (ADOT)** — if customer wants vendor-agnostic traces ([docs](https://aws-otel.github.io/))
- **CoreDNS, kube-proxy, vpc-cni** — keep current via EKS managed add-ons ([docs](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html))

## Reference implementations

Per Constitution §4 this repo ships no IaC; use upstream blueprints:

- [EKS Blueprints v5 (Terraform)](https://github.com/aws-ia/terraform-aws-eks-blueprints)
- [EKS Blueprints Addons](https://github.com/aws-ia/terraform-aws-eks-blueprints-addons)
- [Amazon EKS CDK Blueprints](https://github.com/aws-quickstart/cdk-eks-blueprints)

## Migration-specific configuration notes

- **Enable Pod Identity Agent at cluster creation.** Retrofitting requires rolling node replacement on affected node groups ([docs](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html)).
- **EKS Auto Mode requires K8s ≥1.29** `[VERIFICATION-PENDING]`. Migrations from GDC clusters running ≤1.28 need an in-cluster upgrade first.
- **Anthos Config Sync → ArgoCD:** deploy ArgoCD **before** wave 1 cutover, not after. See [`docs/playbooks/config-sync-to-argocd.md`](../../../docs/playbooks/config-sync-to-argocd.md).
- **Anthos Service Mesh (Istio) sources:** install Istio on EKS at the **same minor version** before traffic shift. See [`docs/playbooks/traffic-shifting.md`](../../../docs/playbooks/traffic-shifting.md).
- Specific version numbers above marked `[VERIFICATION-PENDING]` should be confirmed against current AWS release notes before customer delivery.

## Planned additions

Reference Terraform module, reference Helm umbrella chart, and mesh-federation live-migration pattern are tracked in [`ROADMAP.md`](../../../ROADMAP.md).
