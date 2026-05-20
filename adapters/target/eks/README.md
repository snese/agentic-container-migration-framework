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

## Planned additions

Reference Terraform module, reference Helm umbrella chart, and mesh-federation live-migration pattern are tracked in [`ROADMAP.md`](../../../ROADMAP.md).
