# Target Adapter: Amazon ECS on Fargate

## When to choose ECS Fargate

- Stateless services, batch jobs, or event-driven workloads
- Team wants minimal K8s/ops overhead
- Cost-sensitive workloads that benefit from Fargate Spot
- No K8s API requirements (no CRDs, operators, or service mesh CRs)

For workloads that depend on K8s APIs, see [EKS](../eks/README.md).

## Recommended Components (migration landing zone baseline)

| Component | Purpose | AWS Doc |
|-----------|---------|---------|
| **Application Load Balancer (ALB)** | Replaces GKE Ingress / GCE LB | [Intro](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html) |
| **ECS Service Connect** | Service-to-service routing — replaces basic Istio/mesh | [Docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html) |
| **AWS Fargate Spot** | Up to 70% cost reduction for interruption-tolerant workloads | [Pricing](https://aws.amazon.com/fargate/pricing/) |
| **Amazon EFS** | Shared persistent storage for stateful workloads | [ECS + EFS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/efs-volumes.html) |
| **AWS X-Ray / ADOT** | Distributed tracing for microservices | [X-Ray + ECS](https://docs.aws.amazon.com/xray/latest/devguide/xray-services-ecs.html) |
| **Amazon ECR** | Container registry — enforce immutable tags in production | [Tag mutability](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html) |
| **CloudWatch Container Insights** | Cluster + task metrics and logs | [Docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html) |

## Reference Implementations

ACMF does not ship Terraform/CDK modules (Constitution §4). Use these upstream references:

- **ECS Best Practices Guide:** https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/intro.html
- **ECS Workshop:** https://ecsworkshop.com/
- **CDK ECS Patterns (L3 constructs):** https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_ecs_patterns-readme.html
- **ECS reference architectures (AWS Samples):** https://github.com/aws-samples/ecs-refarch-cloudformation

## Migration-Specific Configuration Notes

- **No DaemonSet equivalent** — any source workload running as a DaemonSet (log collectors, security agents, monitoring exporters) must be converted to a sidecar container in the task definition or moved to a shared ECS service. Identify these during Assess phase.

- **No privileged containers** — Fargate rejects task definitions with `privileged: true`. Audit source workloads for `securityContext.privileged: true` during Assess; these must be refactored before migration.

- **Fargate ephemeral storage sizing** — default is 20 GiB; expandable up to 200 GiB via `ephemeralStorage.sizeInGiB` in the task definition. Source workloads with large temp files (build artifacts, model weights, caches) need explicit sizing. [Docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-storage.html)

- **ECS Service Connect namespace — provision before wave 1** — Service Connect requires an AWS Cloud Map namespace. Provision during Mobilize and budget ~2h for namespace setup + health validation before wave 1 cutover.

- **Blue/Green deployment requires planning at service creation** — ECS Blue/Green via CodeDeploy requires `deploymentController.type=CODE_DEPLOY` on the service definition. This **cannot be changed after service creation**. Decide deployment strategy during Mobilize and provision accordingly.

- **Task Role vs ServiceAccount** — ECS Task Role replaces K8s ServiceAccount + Workload Identity. One Task Role per distinct IAM permission boundary; do not share Task Roles across unrelated services.

## What you LOSE coming from GDC for VMware (or any K8s source)

- **Pod-level lifecycle hooks** — `preStop` / `postStart` hooks map roughly but semantics differ in some edge cases; test explicitly
- **DaemonSet model** — handled as sidecar containers or platform-side Fargate agents; no direct equivalent
- **Custom CNI / NetworkPolicies** — ECS Fargate uses VPC networking with Security Groups; NetworkPolicy-style L4 rules are expressed as Security Group rules, not K8s NetworkPolicy objects
- **Cluster-scoped resources** — no CRDs, no admission webhooks, no cluster-wide RBAC

## Planned Additions

ECS Fargate reference Terraform module and Service Connect migration recipe from Istio are tracked in [`ROADMAP.md`](../../../ROADMAP.md).
