# The 7 Rs for Container Workloads

AWS's classic 7 Rs were articulated for VMs and applications. They still apply to container workloads — but the *meaning* shifts. "Rehost" is not a VM lift; it's a manifest port. "Relocate" is not VMware Cloud on AWS; it's EKS Anywhere or ROSA on AWS. This page is the container-native interpretation ACMF uses end-to-end.

## TL;DR

| R | Container meaning | AWS target |
|---|---|---|
| **Retire** | Delete unused workloads / namespaces / CronJobs | _(none — turn it off)_ |
| **Retain** | Keep on source platform for now (compliance, contract, latency) | Source stays |
| **Rehost** | Port manifests as-is; same container image; same shape | EKS (default) |
| **Relocate** | Move the K8s distribution itself, mostly unchanged | ROSA on AWS, EKS Anywhere → EKS |
| **Replatform** | Swap infra-adjacent components for AWS managed services | EKS + RDS / ElastiCache / MSK / EFS |
| **Repurchase** | Replace home-built workload with SaaS or managed AWS service | Managed service (e.g. Bedrock, OpenSearch) |
| **Refactor** | Re-architect the workload itself (often to serverless) | Lambda, Step Functions, Fargate-native |

## Retire

**Definition.** Switch the workload off. For containers this is *the easiest R you'll ever do* — `kubectl delete` is cheap — but it requires confidence the workload is unused.

**Container example.** A CronJob nobody owns; a Deployment scaled to 1 replica with zero traffic for 90 days; a namespace from a finished POC.

**When to use.** Discovery shows zero ingress traffic, zero outbound calls, zero dependencies pointing at it. Ownership is unclear. No one objects when you propose deletion.

**When NOT to use.** Anything with regulatory data retention obligations. Workloads that look idle but run quarterly (always check 90+ days of metrics).

**AWS target.** None. Just stop running it.

## Retain

**Definition.** Leave the workload on the source platform for now. Not "never migrate" — just "not in this wave."

**Container example.** A workload tightly coupled to on-prem licensed software. A regulated workload pending data residency review. A vendor product that runs only on OpenShift.

**When to use.** Migration cost / risk currently exceeds value. Compliance constraints aren't yet resolved. A planned modernization will obsolete the workload in <12 months.

**When NOT to use.** As an excuse to dodge hard workloads. Retain decisions need an explicit revisit date.

**AWS target.** None. Source platform persists, possibly with new hybrid connectivity to AWS.

## Rehost

**Definition.** Port manifests to AWS Kubernetes (EKS) or ECS with minimal changes. Same container image. Equivalent Deployment / StatefulSet / Service shape. Source-specific bits (Workload Identity → IRSA, OpenShift Routes → ALB Ingress) get translated, but the workload's logical shape doesn't change.

**Container example.** A Java microservice running on GDC for VMware (formerly Anthos on VMware) with a Helm chart, talking to an external Postgres. Helm chart → re-tagged image in ECR → IRSA replaces Workload Identity → Postgres endpoint flipped to RDS or stays external. No code change.

**When to use.** Workload is healthy, stateless or simply stateful, no urgent modernization driver. You want migration speed over architectural purity. The default for most container workloads.

**When NOT to use.** Workload depends on source-specific features that have no clean AWS equivalent (deep OpenShift Operator chains, niche GDC config). Replatform or Refactor instead.

**AWS target.** EKS (primary). ECS Fargate when the workload is simple and a customer is reducing K8s ops surface.

## Relocate

**Definition.** Move the *Kubernetes distribution itself* to AWS, with the workloads riding along largely unchanged. This is the unusual R for containers: it preserves the source distribution rather than translating away from it.

Container Relocate is rarer than VM Relocate (which uses VMware Cloud on AWS). For containers, the realistic relocate paths are:

- **EKS Anywhere → EKS.** Same control-plane shape and tooling, on-prem to cloud.
- **ROSA on-prem (or self-managed OpenShift) → ROSA on AWS.** Managed OpenShift, jointly operated by AWS and Red Hat. Operators, Routes, SCCs all keep working.

**Container example.** A regulated bank with deep OpenShift investment moves their cluster fleet from on-prem to ROSA on AWS. Operators, Helm charts, GitOps pipelines, developer experience — all preserved. The point of Relocate is *operational continuity*, not infrastructure transformation.

**When to use.** Strong investment in the source distribution that the customer is unwilling or unable to walk away from. Need cloud benefits (elasticity, AWS service integration) without retraining the entire platform team. Compliance sign-off depends on the existing platform shape.

**When NOT to use.** When the source distribution itself is the problem (cost, features, fit). When the customer is open to EKS — Rehost is faster and cheaper. Don't sell Relocate as a hedge against decision-making.

**AWS target.** ROSA on AWS, EKS Anywhere → EKS.

## Replatform

**Definition.** Keep the workload running in containers, but swap *infrastructure-adjacent components* for AWS managed services. The application code is mostly untouched; the operational footprint shrinks.

**Container example.** Workload running on GDC for VMware with self-hosted Postgres in a StatefulSet → on EKS with RDS Postgres. Self-hosted Kafka StatefulSet → MSK. Self-hosted Redis → ElastiCache. Self-managed cert-manager + Let's Encrypt → ACM + ALB.

**When to use.** The managed equivalent is materially better (cost, ops burden, security posture). The workload accepts the connection-string change without a redesign. You're already touching the manifests, so the marginal cost is low.

**When NOT to use.** Custom database extensions or version pins managed services don't support. Latency-sensitive workloads where in-cluster co-location actually matters. When Replatform turns into Refactor by stealth.

**AWS target.** EKS / ECS for the workload, plus RDS, ElastiCache, MSK, EFS, ACM, Secrets Manager, etc.

## Repurchase

**Definition.** Replace the home-built containerized workload with a SaaS product or fully managed AWS service. The container goes away.

**Container example.** Self-hosted Elasticsearch StatefulSet → Amazon OpenSearch Service. Self-hosted Grafana → Amazon Managed Grafana. Self-hosted GitLab Runners → CodeBuild / GitHub Actions. Custom-built ML inference service → Bedrock or SageMaker endpoint.

**When to use.** Maintaining the workload distracts from the customer's actual product. A managed/SaaS option meets functional needs and the migration cost pays back inside 12–18 months.

**When NOT to use.** Workload is a strategic differentiator. Customizations are deep enough that the managed product can't host them. Data egress / residency makes SaaS a non-starter.

**AWS target.** Managed AWS service (OpenSearch, Managed Grafana, MQ, Bedrock, etc.) or third-party SaaS.

## Refactor

**Definition.** Redesign the workload itself for cloud-native AWS — often *out of containers entirely*, into serverless or managed runtimes. This is the highest-cost / highest-value R.

**Container example.** Synchronous Python container behind ALB → Lambda + API Gateway. Long-running container processing queue → Step Functions + Lambda + SQS. Stateful container batch job → AWS Batch or Glue.

**When to use.** The current architecture is the problem (cost, scale ceiling, ops burden). There is engineering capacity and product appetite for non-trivial change. Modernization ROI is in the business case.

**When NOT to use.** Tight migration deadline. Team isn't ready for serverless / event-driven model. The benefit is purely aesthetic (resume-driven architecture).

**AWS target.** Lambda, Step Functions, Fargate-native (no EKS/ECS), AWS Batch, EventBridge, Glue.

## Decision tree

```
For each workload in the discovery bundle:

is workload still in use?
├─ no  ──────────────────────────────────────────────→ Retire
└─ yes
   │
   must it stay on the source platform (now)?
   ├─ yes ──────────────────────────────────────────→ Retain
   └─ no
      │
      is there a SaaS / managed AWS service that replaces it?
      ├─ yes, and it's a fit ─────────────────────────→ Repurchase
      └─ no
         │
         is the customer keeping the source K8s distribution itself?
         ├─ yes (e.g. OpenShift, EKS Anywhere) ───────→ Relocate (ROSA / EKS-A → EKS)
         └─ no
            │
            does it benefit from a managed AWS data/infra service swap?
            ├─ yes (DB / cache / queue / cert) ───────→ Replatform (EKS + managed svc)
            └─ no
               │
               is there budget + appetite to redesign?
               ├─ yes, big payoff ──────────────────→ Refactor (Lambda / Fargate / SFN)
               └─ no, just get it on AWS ────────────→ Rehost (EKS, sometimes ECS)
```

The 7 Rs are not a value ladder — Refactor is not "better" than Rehost. The right R is the one that maximizes value at acceptable risk for *this* workload, in *this* wave.
