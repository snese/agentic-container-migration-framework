# Anthos-on-GCP → AWS Feature Mapping

| Anthos / GKE Feature | AWS Equivalent (EKS) | AWS Equivalent (ECS) | Migration Notes |
|---|---|---|---|
| GKE Standard cluster | EKS cluster | — | 1:1 conceptually; node-group provisioning differs (Karpenter on EKS vs GKE node auto-provisioner) |
| GKE Autopilot | EKS Auto Mode | ECS Fargate | Auto Mode is the closest equivalent; pod-level resource model translates directly |
| Workload Identity (KSA→GSA) | IRSA (IAM Roles for Service Accounts) | Task Role | Annotation-driven mapping; needs OIDC trust setup |
| Config Sync (RootSync/RepoSync) | Flux v2 / ArgoCD | — | Config Sync is GitOps; on AWS Flux is the standard; ArgoCD if customer prefers |
| Anthos Service Mesh (managed Istio) | EKS + Istio (self-managed) | App Mesh / ECS Service Connect | App Mesh is GA but App Mesh successor strategy is in flux — recommend Istio on EKS for like-for-like |
| Multi-cluster Service Mesh | EKS w/ Istio multi-cluster | — | Cross-cluster trust + DNS = significant rebuild |
| Policy Controller (Gatekeeper) | Kyverno on EKS | — | OPA Gatekeeper on EKS works too; Kyverno is more idiomatic on AWS |
| GCP Filestore (NFS) | EFS | EFS (via Fargate volume) | RWX use cases; mount points differ |
| Persistent Disk (pd.csi.storage.gke.io) | EBS (ebs.csi.aws.com) | — | Block volumes; reclaim policy + snapshot strategy must be redesigned |
| GCS bucket access via WI | S3 + IRSA | S3 + Task Role | Object storage 1:1 |
| Cloud SQL via Cloud SQL Auth Proxy | RDS + IAM auth / Aurora | RDS | Connection-string and IAM-token semantics differ |
| Pub/Sub | SNS + SQS / EventBridge / MSK | SNS+SQS | Pub/Sub fan-out → SNS topic + SQS subscriber |
| Cloud Memorystore (Redis) | ElastiCache (Redis) | ElastiCache | 1:1 |
| BigQuery | Athena / Redshift Serverless | Athena | Different cost model; query syntax mostly compatible (Redshift differs more) |
| Secret Manager | AWS Secrets Manager / SSM Parameter Store | Secrets Manager / SSM | External Secrets Operator works against either |
| GKE Logging → Cloud Logging | CloudWatch Logs (via FluentBit / OTel) | CloudWatch Logs | Standard fluent-bit config swap |
| GKE Monitoring → Cloud Monitoring | CloudWatch Metrics + Managed Prometheus (AMP) | CloudWatch Container Insights | AMP for k8s-native; Container Insights for ECS |
| GKE NetworkPolicies (Calico) | Calico on EKS / VPC CNI Network Policies | Security Groups / Service Connect policies | EKS supports NetworkPolicy via VPC CNI (since 2023) |
| Multi-cluster Ingress | AWS Global Accelerator + ALB / Route 53 latency-based | — | Architectural rebuild; usually consolidate into fewer regions |
| Binary Authorization | ECR scan + Signer / Notation | ECR scan + Signer | Image-signing posture — Sigstore + Cosign also valid |
| Cloud Run side-by-side | App Runner / ECS Fargate / Lambda | App Runner / Lambda | Out of scope for K8s migration; called out for hybrid portfolios |

## Notes

- **Autopilot pricing** is per-pod; EKS Auto Mode bills compute + a control-plane fee. Run an actual cost diff for portfolios with many small pods.
- **Workload Identity** annotation `iam.gke.io/gcp-service-account` → must rewrite as `eks.amazonaws.com/role-arn` for IRSA.
- **Anthos Service Mesh certs** are issued by Mesh CA; on AWS with Istio you bring your own root CA or use cert-manager.
