# CAF Perspective: Platform

Platform is the technical landing zone — accounts, networking, clusters, IaC, CI/CD plumbing. For container migrations, this is where ACMF spends the most opinionated effort, because the choice between EKS / ECS Fargate / ROSA on AWS is not a one-size answer.

## Stakeholders

- Platform / infrastructure engineering
- Cloud architect
- Network engineering
- DevEx / build & release engineering

## Container-specific capabilities

- **Multi-target reference architectures.** EKS (full K8s control), ECS Fargate (serverless containers), ROSA on AWS (managed OpenShift). Each with a documented "happy path" landing zone. (AWS App Runner entered maintenance mode 2026-04-30 and is no longer a recommended target for new workloads.)
- **GitOps-first IaC.** Argo CD or Flux as the deployment substrate, Terraform / CDK for infra, Helm or Kustomize for app shape — picked per adapter, not improvised per project.
- **Network design for K8s reality.** VPC CIDR sizing for pod IPs (VPC CNI is hungry), private API endpoints, transit between VPCs, hybrid connectivity for staged migration, egress for image pulls.
- **Image and registry strategy.** ECR pull-through cache, image scanning, signing (cosign / Notation), promotion across accounts.
- **Workload portability layer.** Adapter-driven translation: Anthos Config Sync → Argo CD, OpenShift Routes → ALB Ingress, Workload Identity → IRSA, Anthos Service Mesh → App Mesh / Istio on EKS.

## Key deliverables

- Landing zone design (Control Tower / AWS Organizations layout, account strategy)
- Per-target reference architecture (EKS / ECS Fargate) as IaC modules in `iac-skeleton/`
- Network blueprint (VPC, subnets, hybrid connectivity, DNS, egress)
- Image supply chain design (ECR, scanning, signing, promotion)
- Migration cutover patterns (blue/green, canary, dual-running)

## Anti-patterns to avoid

- One-size-fits-all "everything goes to EKS" without applying the [decision tree](../../decisions/ecs-vs-eks.md).
- Under-sizing VPC CIDRs and discovering the IP exhaustion problem after wave 2.
- Building the landing zone without GitOps from day one, then retrofitting it.
- Copying GDC / OpenShift opinions wholesale (e.g. cluster-per-team) into AWS without re-evaluating.

## How agentic discovery contributes

The discovery bundle drives target selection: workloads heavy on CRDs route to EKS; everything else is ECS Fargate. Agent-generated IaC scaffolding (Terraform / CDK starter modules per workload) gives the platform team a working baseline instead of a blank repo on Day 1 of Mobilize.
