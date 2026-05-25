# Target Adapter: Amazon EKS

## When to choose EKS

- Workloads that depend on the Kubernetes API (CRDs, operators, service mesh CRDs)
- Stateful workloads with complex storage requirements
- Teams with strong K8s expertise (minimizes ramp-up time from source platform)

## Patterns

- **Cluster topology:** EKS Auto Mode (recommended default) or Karpenter for custom needs
- **GitOps:** ArgoCD (recommended) or Flux — mirrors Config Sync structure from source
- **Mesh:** Istio (1:1 from GKE Enterprise Service Mesh) or Amazon VPC Lattice (service-to-service)
- **Policy:** OPA Gatekeeper (direct ConstraintTemplate migration) or Kyverno (simpler syntax)
- **Identity:** EKS Pod Identity (preferred) or IRSA (legacy clusters)
- **Networking:** VPC CNI with NetworkPolicies via Calico or Cilium

## Compute model selection

See [`docs/decisions/eks-compute-model.md`](../../../docs/decisions/eks-compute-model.md) for the full decision tree: Auto Mode vs Karpenter vs Managed Node Groups vs Fargate profiles.

## Planned additions

Reference Terraform module, reference Helm umbrella chart, and mesh-federation live-migration pattern are tracked in [`ROADMAP.md`](../../../ROADMAP.md).
