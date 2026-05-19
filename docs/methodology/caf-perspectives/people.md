# CAF Perspective: People

The People perspective addresses skills, roles, and culture. Container migrations have a specific failure mode here: the team that runs GDC for VMware (formerly Anthos on VMware) or OpenShift today is *not* automatically ready to run EKS tomorrow, even though it's "all Kubernetes." The shape of operational responsibility shifts.

## Stakeholders

- Platform engineering / SRE leads
- Application development team leads
- HR / L&D for formal training enablement
- Engineering managers who own on-call rotations

## Container-specific capabilities

- **K8s-distribution skill mapping.** Identify what Anthos Config Sync / OpenShift Operators / Rancher Fleet skills translate directly to AWS (Argo CD, EKS Add-ons, Karpenter) and what is genuinely new (IRSA, AWS VPC CNI, ECS task definitions).
- **Shared-responsibility re-education.** GDC and OpenShift are heavily managed in opinionated ways; EKS gives more control and therefore more responsibility (node patching strategy, add-on lifecycle, networking choices). Teams must re-learn where the line is.
- **Platform team vs application team boundary.** Container migrations are a chance to redraw the platform/app contract — what's a self-service paved road, what's an exception path.
- **Agent-assisted operations enablement.** Train operators to use ACMF agentic playbooks for diagnostics, drift detection, and runbook execution rather than memorizing kubectl one-liners.

## Key deliverables

- Skills gap matrix (current capabilities × required capabilities, per role)
- Training plan — AWS Skill Builder paths, EKS Workshop assignments, hands-on labs
- Updated org chart / RACI for the AWS target operating model
- Cutover-period staffing plan (who's on-call during waves, vendor support coverage)

## Anti-patterns to avoid

- Assuming "Kubernetes is Kubernetes" — GDC operators do not automatically know IRSA, VPC CNI quirks, or Karpenter.
- Migrating workloads before the operating team has run a non-prod EKS cluster end-to-end.
- Letting the platform team migrate everything in isolation, then handing surprise on-call to app teams.
- Skipping training budget in the business case "because the team already does Kubernetes."

## How agentic discovery contributes

The discovery bundle surfaces concrete signals about team practice: how many distinct deployment patterns exist, whether GitOps is actually adopted, which namespaces have NetworkPolicies vs which don't, how diverse the operator/CRD inventory is. This converts vague "the team is mature in K8s" claims into a measurable readiness baseline that drives a real training plan, not a checkbox course list.
