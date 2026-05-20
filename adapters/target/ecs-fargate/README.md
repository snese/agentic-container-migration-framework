# Target Adapter: Amazon ECS on Fargate

## When to choose ECS Fargate

- Stateless services, batch jobs
- Team wants minimal K8s/ops overhead
- Cost-sensitive workloads
- Single-tenant simplicity

## Patterns

- **Service definition:** one Task Definition per microservice
- **Service discovery:** ECS Service Connect (replaces in-cluster DNS + mesh basics)
- **Scaling:** Application Auto Scaling on ECS Service
- **Identity:** Task Role (replaces ServiceAccount + Workload Identity)
- **Storage:** EFS for shared state; otherwise stateless
- **Logging:** awslogs driver → CloudWatch Logs / Firehose to S3
- **Deploy:** Blue/Green via CodeDeploy

## What you LOSE coming from GKE Enterprise on VMware (or any K8s source)

- Pod-level lifecycle (init containers map fine, but no `preStop` semantic in some cases)
- DaemonSet equivalent — handled by Fargate platform side
- Custom CNI / NetworkPolicies — limited

## Recommended components for a migration landing zone

- **Application Load Balancer (ALB)** — replaces Ingress; via AWS Load Balancer Controller or native console ([docs](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html))
- **ECS Service Connect** — replaces Istio/service mesh for inter-service routing ([docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html))
- **AWS Fargate Spot** — ~70% cost reduction for interruption-tolerant workloads ([pricing](https://aws.amazon.com/fargate/pricing/))
- **Amazon EFS** — for stateful workloads that need shared storage ([docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/efs-volumes.html))
- **AWS X-Ray / ADOT** — distributed tracing for microservices ([docs](https://docs.aws.amazon.com/xray/latest/devguide/xray-services-ecs.html))
- **Amazon ECR** — container registry; enforce immutable tags for production ([docs](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html))

## Reference implementations

Per Constitution §4 this repo ships no IaC; use upstream references:

- [ECS Best Practices Guide (AWS)](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/intro.html)
- [ECS Workshop](https://ecsworkshop.com/)
- [CDK ECS Patterns](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_ecs_patterns-readme.html)

## Migration-specific configuration notes

- **Fargate does not support DaemonSets** — any DaemonSet workload (log collectors, security agents) must use the Fargate sidecar pattern or be moved to ECS on EC2.
- **Fargate does not support privileged containers** — validate source workloads for `securityContext.privileged: true` during the Assess phase before migration.
- **Fargate ephemeral storage:** default 20 GiB, expandable up to 200 GiB via `ephemeralStorage.sizeInGiB` in the task definition. Source workloads with large temp footprints need explicit sizing ([docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-storage.html)).
- **Service Connect namespace:** provision the ECS namespace before wave 1; budget ~2 hours in the migration timeline for namespace setup and health validation.
- **Blue/Green via CodeDeploy:** requires `deploymentController.type=CODE_DEPLOY` on the ECS service **at creation** — this cannot be changed after the fact. Plan this decision during the Mobilize phase.

## Planned additions

Reference Terraform module and ECS Service Connect migration recipe from Istio are tracked in [`ROADMAP.md`](../../../ROADMAP.md).
