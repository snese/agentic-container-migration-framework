# CAF Perspective: Security

Security in a container migration is where careless lift-and-shift gets ugly fast. GDC Workload Identity does not exist on EKS. OpenShift SCCs do not translate to PodSecurityStandards 1:1. Network policies that worked under Calico may behave differently under VPC CNI. Treat security as a Day-0 design exercise, not a hardening pass.

## Stakeholders

- CISO / security architect
- Application security / AppSec engineering
- Compliance & audit
- IAM / identity team

## Container-specific capabilities

- **Workload identity translation.** Mapping GCP Workload Identity / OpenShift ServiceAccount tokens / Rancher's auth model to IRSA or Pod Identity on EKS, or task IAM roles on ECS.
- **Pod security standards.** Replacing OpenShift SCCs and Anthos Policy Controller constraints with PodSecurityStandards + Gatekeeper / Kyverno on EKS, or task-definition hardening on ECS.
- **Image supply chain.** ECR scanning, signing (cosign / AWS Signer / Notation), admission control (Kyverno verify-images), SBOM generation in CI.
- **Network policy and segmentation.** Translating Calico / Cilium / OpenShift NetworkPolicies to AWS VPC CNI Network Policy, security groups for pods, and where applicable, service mesh mTLS.
- **Secrets and data protection.** Migrating from Vault / Sealed Secrets / OpenShift Secrets to AWS Secrets Manager / Parameter Store + External Secrets Operator, with rotation policy reviewed.
- **Compliance mapping.** Re-mapping existing controls (PCI / HIPAA / SOC2 / ISO27001) to AWS services and Config rules.

## Key deliverables

- Threat model for the target architecture (per cluster pattern)
- IAM / IRSA / Pod Identity design, including least-privilege role catalog
- Image supply chain design (scan, sign, verify, SBOM)
- Network policy design (segmentation, egress controls, mTLS posture)
- Compliance traceability matrix — control → AWS implementation → evidence source
- Incident response runbooks for container-specific incidents (compromised pod, malicious image, runaway workload)

## Anti-patterns to avoid

- Granting wildcard IAM to a single "cluster role" instead of per-workload IRSA.
- Skipping PodSecurityStandards on the assumption that "the network is private enough."
- Continuing to rely on the source platform's built-in admission controllers without picking a replacement before cutover.
- Migrating secrets by `kubectl get secret -o yaml` and importing — leaks plaintext into git history if anyone is sloppy.

## How agentic discovery contributes

Agent-driven manifest analysis builds an evidence-backed security inventory: every ServiceAccount and its bindings, every NetworkPolicy, every PodSecurityContext, every image registry referenced, every Secret consumer. This becomes the input for the IRSA role catalog, the policy translation matrix, and the supply chain design — instead of security teams chasing this data manually under cutover pressure.
