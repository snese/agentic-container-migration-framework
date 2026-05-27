# OpenShift → AWS Feature Mapping

| OpenShift Feature | AWS Equivalent (EKS) | AWS Equivalent (ECS) | Migration Notes |
|---|---|---|---|
| Project (= Namespace + extras) | Namespace | — | OpenShift Projects add default network policy + LimitRange + SCC. Recreate explicitly on EKS. |
| Route (`route.openshift.io/v1`) | Ingress (ALB Controller) | ALB / Service Connect | TLS edge/passthrough/reencrypt → matching ALB listener config |
| ImageStream + BuildConfig (S2I) | ECR + CodeBuild | ECR + CodeBuild | S2I scripts → Dockerfile or buildpacks; CI moves out of cluster |
| Source-to-Image (S2I) | CodeBuild + custom image | CodeBuild | Most teams happily move CI out of K8s during migration |
| OLM Subscriptions | Helm + flux/argo | Helm | Each Operator becomes either a Helm chart or a managed AWS service |
| MachineConfigPool / MachineSet | Karpenter / Managed Node Groups | — | Cluster-as-code → IaC (Terraform/CDK) + Karpenter |
| SecurityContextConstraints (SCC) | Pod Security Admission (PSA) | — | OCP `restricted-v2` ≈ PSA `restricted`; `anyuid` mostly disappears in cloud-native rewrites |
| OAuth (built-in IdP) | Cognito / IAM Identity Center / external OIDC | Same | Identity provider migration is its own work stream |
| Internal image registry | ECR | ECR | Pull-through cache for read-mostly use cases |
| Cluster Logging Operator | OTel Collector + CloudWatch / OpenSearch | CloudWatch | Loki on EKS is a popular open-source equivalent if customer wants to stay open |
| Cluster Monitoring (Prometheus Operator) | AMP + AMG | CloudWatch Container Insights | AMP is AWS Managed Prometheus; AMG is AWS Managed Grafana |
| OpenShift Pipelines (Tekton) | CodePipeline + CodeBuild / Tekton on EKS | CodePipeline | Tekton → Tekton works; or ditch for AWS-native pipelines |
| OpenShift GitOps (ArgoCD) | ArgoCD on EKS / Flux | ArgoCD | 1:1 |
| OpenShift Service Mesh (Istio) | Istio on EKS | App Mesh / Service Connect | Same trade-offs as Anthos Service Mesh migration |
| OpenShift Virtualization (KubeVirt) | EC2 / no direct K8s-native equivalent | EC2 | 🚧 If customer runs VMs on KubeVirt, those are usually NOT containerized — separate workstream |
| ODF (OpenShift Data Foundation, Ceph) | EBS / EFS / FSx for Lustre / S3 | Same | Block / file / object split on AWS; redesign storage tiering |
| HyperShift / Hosted Control Planes | EKS hosted control planes (default) | — | EKS already runs HCP-style; no work needed |

## Notes

- **Routes vs Ingress vs Gateway API:** Routes are *not* identical to k8s Ingress. Multi-host TLS
  rules and re-encrypt behavior need explicit translation. Gateway API is the modern idiom on EKS;
  for like-for-like, ALB + Ingress works.
- **SCC mapping:** if customer has custom SCCs, each one needs a PSA / Kyverno equivalent. Skipping
  this leaves workloads broken (they'll fail PSA admission).
- **OLM Operators** range from "trivial" (cert-manager — same operator on EKS) to "blocker"
  (proprietary operators with Red Hat-licensed components). Audit during Assess.
