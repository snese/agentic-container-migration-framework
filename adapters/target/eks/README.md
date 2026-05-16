# Target Adapter: Amazon EKS

## When to choose EKS

- Heavy K8s API usage (CRDs, operators, mesh)
- Stateful workloads with complex storage
- Strong K8s expertise on customer team

## Patterns

- **Cluster topology:** EKS Auto Mode for greenfield, managed node groups for migration
- **GitOps:** Flux or ArgoCD (mirror Anthos Config Sync structure)
- **Mesh:** Istio (1:1 from Anthos Service Mesh) or App Mesh
- **Policy:** Kyverno (1:1 from Policy Controller) or OPA Gatekeeper
- **Identity:** IRSA (Pod Identity for newer setups)
- **Networking:** VPC CNI, NetworkPolicies via Calico

## TBD

- Reference Terraform module
- Reference Helm umbrella chart
- Mesh federation for live migration
