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

## What you LOSE coming from Anthos

- Pod-level lifecycle (init containers map fine, but no `preStop` semantic in some cases)
- DaemonSet equivalent — handled by Fargate platform side
- Custom CNI / NetworkPolicies — limited

## TBD

- Reference Terraform module
- ECS Service Connect migration recipe from Istio
