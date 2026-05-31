# OpenShift → AWS Feature Mapping

## OpenShift platform features → AWS

| OpenShift Feature | AWS Equivalent (EKS) | AWS Equivalent (ECS) | Migration Notes |
|---|---|---|---|
| Project (= Namespace + extras) | Namespace | — | OpenShift Projects add default network policy + LimitRange + SCC. Recreate explicitly on EKS. |
| Route (`route.openshift.io/v1`) | Ingress (ALB Controller) | ALB / Service Connect | TLS edge/passthrough/reencrypt → matching ALB listener config |
| ImageStream + BuildConfig (S2I) | ECR + CodeBuild | ECR + CodeBuild | S2I scripts → Dockerfile or buildpacks; CI moves out of cluster |
| Source-to-Image (S2I) | CodeBuild + custom image | CodeBuild | Most teams happily move CI out of K8s during migration |
| OLM Subscriptions | Helm + flux/argo | Helm | Each Operator becomes either a Helm chart or a managed AWS service — see rating table below |
| MachineConfigPool / MachineSet | Karpenter / Managed Node Groups | — | Cluster-as-code → IaC (Terraform/CDK) + Karpenter |
| SecurityContextConstraints (SCC) | Pod Security Admission (PSA) | — | OCP `restricted-v2` ≈ PSA `restricted`; `anyuid` mostly disappears in cloud-native rewrites. Effective SCC bindings are now auto-collected as `.openshift.scc_usage[]` |
| OAuth (built-in IdP) | Cognito / IAM Identity Center / external OIDC | Same | Identity provider migration is its own work stream |
| Internal image registry | ECR | ECR | Pull-through cache for read-mostly use cases |
| Cluster Logging Operator | OTel Collector + CloudWatch / OpenSearch | CloudWatch | Loki on EKS is a popular open-source equivalent if customer wants to stay open |
| Cluster Monitoring (Prometheus Operator) | AMP + AMG | CloudWatch Container Insights | AMP is AWS Managed Prometheus; AMG is AWS Managed Grafana |
| OpenShift Pipelines (Tekton) | CodePipeline + CodeBuild / Tekton on EKS | CodePipeline | Tekton → Tekton works; or ditch for AWS-native pipelines |
| OpenShift GitOps (Argo CD) | Argo CD on EKS / Flux | Argo CD | 1:1 |
| OpenShift Service Mesh (Istio/Maistra) | Istio on EKS | App Mesh / Service Connect | Maistra-specific extensions need rewrite |
| OpenShift Virtualization (KubeVirt) | EC2 / no direct K8s-native equivalent | EC2 | 🚧 If customer runs VMs on KubeVirt, those are usually NOT containerized — separate workstream |
| ODF (OpenShift Data Foundation, Ceph) | EBS / EFS / FSx for Lustre / S3 | Same | Block / file / object split on AWS; redesign storage tiering |
| HyperShift / Hosted Control Planes | EKS hosted control planes (default) | — | EKS already runs HCP-style; no work needed |

## Operator → AWS migration rating table

The export script tags every detected OLM `Subscription` with one of `easy / hard / blocker / unknown`. The rating reflects "what does it take to land this Operator's workload on AWS?" — drop-in equivalent (`easy`), significant rewrite but feasible (`hard`), or no AWS equivalent (`blocker`). Items not in this table land as `unknown` and surface a single SME warning so they don't get silently lost.

> **Sources of truth.** AWS-managed equivalents are linked in the AWS docs (Amazon EKS, Amazon RDS, Amazon MSK, AMP/AMG, etc.). Where AWS has no native equivalent (KubeVirt, ODF/Ceph, MetalLB, Windows Machine Config Operator, SR-IOV/PTP), we mark `blocker` rather than guess. Operators that run unchanged on EKS are marked `easy` only when they're in upstream/community packaging without OCP-only dependencies.

### easy (drop-in or 1:1 with AWS-managed equivalent)

| Operator package | AWS target | Rationale |
|---|---|---|
| `cert-manager-operator` / `cert-manager` | AWS Certificate Manager (ACM) for public certs; cert-manager on EKS for in-cluster | cert-manager runs on EKS unchanged; ACM replaces public-facing TLS issuance |
| `openshift-pipelines-operator-rh` (Tekton) | AWS CodePipeline + CodeBuild, or Tekton on EKS | Tekton CRDs portable; AWS-native CI is the typical move |
| `openshift-gitops-operator` / `argocd-operator` | Argo CD on EKS | Drop-in; manifests portable |
| `cluster-logging` / `loki-operator` / `elasticsearch-operator` | CloudWatch Logs / OpenSearch / Loki on EKS | Logging stack swap is mechanical; data retention needs SME review |
| `cluster-monitoring-operator` / `prometheus-operator` | Amazon Managed Prometheus (AMP) + Amazon Managed Grafana (AMG) | ServiceMonitor/PodMonitor CRDs portable |
| `external-dns-operator` | external-dns on EKS with Route 53 provider | Drop-in; switch provider flag |
| `nfd-operator` (Node Feature Discovery) | NFD on EKS | Same operator runs on EKS |
| `gpu-operator-certified` / `nvidia-gpu-operator` | NVIDIA GPU Operator on EKS (g5/p4/p5 instances) | Driver versions usually match between OCP and EKS-optimized AMI |
| `redhat-oadp-operator` (Velero) | AWS Backup for Amazon EKS or Velero on EKS | Velero portable; AWS Backup integrates with IAM |
| `kasten-k10` | AWS Backup for Amazon EKS, Velero on EKS, or Kasten K10 on EKS | Same Kasten product runs on EKS |

### hard (significant rewrite required, but feasible)

| Operator package | AWS target | Rationale |
|---|---|---|
| `rhsso-operator` / `keycloak-operator` | Cognito / IAM Identity Center, or Keycloak on EKS | IdP migration is its own work stream; URL/realm/client config rebuild |
| `strimzi-kafka-operator` / `amq-streams` | Amazon MSK, or Strimzi on EKS | Topic/ACL replication via MirrorMaker2; broker-to-MSK semantics differ on storage |
| `crunchy-postgres-operator` / `cloud-native-postgresql` | Amazon RDS / Aurora PostgreSQL, or Postgres Operator on EKS | Operator-managed Postgres → managed RDS; failover, backup, PITR semantics change |
| `mongodb-enterprise` | DocumentDB or MongoDB Atlas | API compatibility caveats with DocumentDB; Atlas is 1:1 but external |
| `serverless-operator` (Knative) | AWS Lambda, App Runner, or Knative on EKS | Knative Service → App Runner is closest match for HTTP; Eventing → EventBridge |
| `servicemeshoperator` (OpenShift Service Mesh / Maistra) | Istio on EKS, VPC Lattice, or App Mesh | Istio CRDs portable; Maistra extensions need rewrite |
| `jaeger-operator` / `opentelemetry-operator` | AWS X-Ray or OTel Collector on EKS | OTel collector portable; X-Ray as native target requires exporter swap |
| `redis-enterprise-operator` | ElastiCache for Redis, or Redis Enterprise on EKS | Failover/persistence semantics differ |
| `rabbitmq-cluster-operator` | Amazon MQ for RabbitMQ, or RabbitMQ Operator on EKS | Managed AMQ has version constraints |
| `compliance-operator` / `file-integrity-operator` | Inspector + AWS Config + Audit Manager | Compliance scan model differs (agent vs API) |

### blocker (no native AWS equivalent — redesign required)

| Operator package | AWS target | Rationale |
|---|---|---|
| `kubevirt-hyperconverged` / `cnv-operator` | EC2 (no K8s-native VM platform on EKS) | KubeVirt VMs are not containers; lift to EC2 or refactor — separate work stream |
| `metallb-operator` / `metallb` | AWS Load Balancer Controller (ALB/NLB) | MetalLB BGP/L2 model has no AWS equivalent |
| `ocs-operator` / `odf-operator` (Ceph) / `local-storage-operator` | EBS / EFS / FSx for Lustre / S3 (per-tier redesign) | Ceph/ODF is converged storage; AWS splits block/file/object — storage tiering must be redesigned |
| `windows-machine-config-operator` (WMCO) | Windows worker nodes on EKS | EKS supports Windows but provisioning/AMI model differs from MCO |
| `ptp-operator` / `sriov-network-operator` | EC2 with EFA / ENA | Telco/NFV hardware features are not exposed identically on EKS |
| `nmstate-operator` | VPC + EC2 networking primitives | Bare-metal NIC bonding/VLAN config replaced by VPC + ENI patterns |

### unknown

Any Operator whose package name is not in the table lands as `migration_rating.rating == "unknown"`. The script emits one aggregated warning so the count is visible without spamming the bundle. SME review must triage each one.

## SCC effective binding extraction (script behaviour)

For each `RoleBinding` and `ClusterRoleBinding` whose `roleRef.name` starts with `system:openshift:scc:`, the script writes one `.openshift.scc_usage[]` entry capturing:

- `scc` (e.g. `anyuid`, `privileged`, `restricted-v2`)
- `namespace` (or `null` for cluster-scoped binding)
- `binding_name`
- `subjects[]` (kind/name/namespace tuples)

Use this to map every Project's effective SCC → PodSecurity Admission (PSA) label on EKS.

## Notes

- **Routes vs Ingress vs Gateway API:** Routes are *not* identical to k8s Ingress. Multi-host TLS
  rules and re-encrypt behavior need explicit translation. Gateway API is the modern idiom on EKS;
  for like-for-like, ALB + Ingress works.
- **SCC mapping:** if customer has custom SCCs, each one needs a PSA / Kyverno equivalent. Skipping
  this leaves workloads broken (they'll fail PSA admission).
- **OLM Operators** range from "trivial" (cert-manager — same operator on EKS) to "blocker"
  (KubeVirt, ODF, MetalLB). The rating table above is the script's source of truth — extend it
  there when new operators are encountered.
