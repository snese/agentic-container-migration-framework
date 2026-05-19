# Target Adapter: Amazon EKS

## When to choose EKS

- Heavy K8s API usage (CRDs, operators, mesh)
- Stateful workloads with complex storage
- Strong K8s expertise on customer team

## Patterns

- **Cluster topology:** EKS Auto Mode for greenfield, managed node groups for migration
- **GitOps:** Flux or ArgoCD (mirror Anthos Config Sync structure from GDC sources)
- **Mesh:** Istio (1:1 from Anthos Service Mesh) or App Mesh
- **Policy:** Kyverno (1:1 from Policy Controller) or OPA Gatekeeper
- **Identity:** IRSA (Pod Identity for newer setups)
- **Networking:** VPC CNI, NetworkPolicies via Calico

## Planned additions

Reference Terraform module, reference Helm umbrella chart, and mesh-federation live-migration pattern are tracked in [`ROADMAP.md`](../../../ROADMAP.md).
