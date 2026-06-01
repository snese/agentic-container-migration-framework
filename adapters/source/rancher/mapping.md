# Rancher → AWS Feature Mapping

| Rancher Feature | AWS Equivalent (EKS) | AWS Equivalent (ECS) | Migration Notes |
|---|---|---|---|
| Rancher management cluster | (no equivalent) | (no equivalent) | Rancher-the-multicluster-control-plane disappears. EKS uses AWS account / OU boundaries |
| RKE2 cluster | EKS cluster | — | Distribution swap; workloads carry over |
| K3s cluster | EKS / ECS Anywhere | — | K3s often runs on edge — see "edge" gotcha |
| Imported cluster (already EKS) | EKS direct | — | Just stop using Rancher; cluster is already on AWS |
| Fleet (GitOps for many clusters) | Flux v2 / Argo CD | — | Per-cluster bootstrap; Fleet's "cluster groups" → Argo CD "ApplicationSets" |
| Longhorn (block CSI) | EBS gp3 / io2 | — | Longhorn does in-cluster replication; EBS handles replication at AZ level — different model |
| Longhorn backup to S3 | AWS Backup for EKS / Velero | Velero | Backup destination changes; restore semantics roughly compatible |
| Project (multi-tenancy) | Namespace + RBAC | Cluster | Rancher Projects are a Rancher abstraction; flatten to namespaces on EKS |
| Rancher RBAC roles | EKS access entries + IAM roles | IAM | Map each Project Role → IAM role + RoleBinding |
| Rancher monitoring (Prometheus + Grafana) | AMP + AMG | CloudWatch Container Insights | Same Prometheus stack; just managed |
| Rancher logging (Loki) | Loki on EKS / CloudWatch / OpenSearch | CloudWatch | Loki keeps working; or move to CloudWatch |
| Catalog (Helm charts) | Helm + Flux/Argo | Helm | App catalog → GitOps |
| Cluster Templates | Terraform / CDK / Pulumi | Same | IaC migration; per-customer choice |
| Harvester (HCI) under Rancher | EC2 + EBS | EC2 | Out of scope for K8s migration; Harvester is a hypervisor |
| MetalLB / kube-vip on RKE2 | AWS Load Balancer Controller | NLB / ALB | `Service: LoadBalancer` becomes managed |
| Kasten K10 (third-party) | AWS Backup for EKS / Velero | Velero | Often deployed alongside Rancher |
| Rancher Apps (built-in chart deployer) | Flux / Argo CD / Helm | Helm | Drop the Rancher-specific Apps abstraction |

## Notes

- **K3s edge clusters** often have very different operating constraints
  (intermittent connectivity, small node count). EKS isn't a great fit for
  true edge — consider ECS Anywhere or AWS IoT Greengrass instead. Out of
  scope for cloud migration.
- **Fleet bundles** are typically pulled from a Git repo specified on the
  management cluster. When you lose Rancher, you also lose Fleet's central
  bundle dispatch. Replace with per-cluster Flux pointing at the same Git repo.
- **Longhorn replication factor 3** maps roughly to EBS `io2 Block Express`
  durability. EBS `gp3` is sufficient for most Longhorn workloads; bump to
  `io2` only for high-IOPS stateful sets.
