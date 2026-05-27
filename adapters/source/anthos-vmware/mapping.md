# Anthos-on-VMware → AWS Feature Mapping

| Anthos-on-VMware Feature | AWS Equivalent (EKS) | AWS Equivalent (ECS) | Migration Notes |
|---|---|---|---|
| Anthos cluster on vSphere | EKS cluster | — | Control plane goes from customer-managed VMs to AWS-managed |
| vSphere CSI volumes | EBS gp3 / EFS | — | Block → EBS, RWX → EFS; data migration plan needed |
| Anthos Config Management (Config Sync) | Flux v2 / ArgoCD on EKS | — | GitOps mostly translates; RootSync vs RepoSync distinction matters |
| Anthos Service Mesh (Istio) | Istio on EKS / App Mesh | App Mesh / ECS Service Connect | Istio-on-EKS is closest like-for-like |
| Policy Controller (Gatekeeper) | Kyverno / Gatekeeper on EKS | — | Either choice works; Kyverno is more idiomatic on AWS |
| Workload Identity (KSA→GSA) | IRSA | Task Role | Annotation-driven; rewrite required |
| Anthos Identity Service (LDAP/OIDC) | Cognito / IAM Identity Center / external OIDC | Same | Identity provider migration is its own work stream |
| Connect Gateway | EKS Connector | (n/a) | Cross-account / cross-region visibility tool; different operational model |
| Multi-cluster Service Mesh | EKS Istio multi-cluster | — | Significant rebuild; review per-portfolio |
| GKE Hub fleet membership | EKS — no equivalent | — | Fleet abstraction disappears; replace with AWS Organizations + access entries |
| vSphere LoadBalancer (F5/SeeSaw/MetalLB) | AWS Load Balancer Controller | NLB / ALB | LoadBalancer Service becomes managed |
| vSphere PV (CSI) | EBS / EFS | — | Volume migration: DMS for DBs, fresh load + replay for caches |
| Private Anthos registry (Artifact Registry mirror) | ECR + pull-through cache | ECR | Replication setup before cutover |
| vCenter / vSphere observability | CloudWatch + EC2 metrics + AMP | CloudWatch | Hypervisor disappears; replace with EC2/EKS observability |

## Notes

- **vSphere CSI**: the most common migration blocker. PVs back to VMware; on AWS they become
  EBS volumes (which are AZ-local). Stateful workloads need a data-migration plan: DMS for
  databases, fresh-load + replay for caches/queues.
- **F5 / SeeSaw / MetalLB** are the typical Anthos-on-VMware LoadBalancer implementations. All
  three disappear; AWS Load Balancer Controller takes over.
- **vSphere fault domains** ≠ AWS AZs. Topology-aware scheduling annotations need re-mapping.
- **Anthos Service Mesh certs** issued by Mesh CA — bring your own root CA on AWS, or use
  cert-manager.
