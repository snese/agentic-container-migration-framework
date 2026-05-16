# CAF Perspective: Operations

Operations is what happens after the cutover party. For container migrations, "Day 2" starts the moment a wave goes live, and Day 2 is where badly-planned migrations die — costs balloon, alerts are noisy, no one knows what an `OOMKilled` pod means in the new dashboards.

## Stakeholders

- SRE / platform reliability team
- Application on-call engineers
- Observability / monitoring lead
- FinOps (overlaps with Business)

## Container-specific capabilities

- **Observability stack design.** Container Insights / Prometheus / Managed Grafana on EKS; CloudWatch Container Insights on ECS Fargate; OpenTelemetry collectors as the shared backbone. Logs / metrics / traces must work for app teams from day one.
- **SLO / SLI design.** Translating existing SLOs (often availability + latency) to a target running on different infrastructure; setting error budgets that survive the migration.
- **Autoscaling strategy.** Karpenter on EKS (vs Cluster Autoscaler) and HPA / KEDA decisions per workload class. Fargate scaling characteristics (cold-start, IP allocation) for ECS / EKS-Fargate workloads.
- **GitOps as the operating model.** Argo CD / Flux as the deploy substrate, with promotion pipelines, auto-sync policy, and drift detection. Disables Slack-driven `kubectl apply` permanently.
- **Incident response runbooks.** Container-aware runbooks: how to debug a CrashLoopBackOff, how to roll back via GitOps, how to evict a noisy neighbor on Fargate, how to capture a heap dump from a running pod.
- **Cost operations.** Kubecost / OpenCost or AWS Split Cost Allocation for K8s; weekly waste reports; right-sizing review cadence.

## Key deliverables

- Observability stack design and onboarding doc for app teams
- SLO catalog per workload + dashboards
- Autoscaling design (Karpenter NodePools, HPA / KEDA configs, Fargate strategy)
- GitOps repo layout + promotion policy
- Runbook library covering top-N container failure modes
- Day-2 operating cadence (release windows, on-call rotation, ops review)

## Anti-patterns to avoid

- Going live without dashboards the app team understands.
- Copying source-platform alerts wholesale; alert fatigue on AWS-native metrics is different.
- Standing up GitOps but still allowing direct `kubectl` access to prod clusters.
- Treating right-sizing as a one-time exercise instead of an ongoing FinOps loop.

## How agentic discovery contributes

Discovery surfaces what's *currently* observed (existing Prometheus rules, alerting policies, dashboards), what's actually *used* (which ConfigMaps reference Grafana dashboards, which alerts fire), and where the operational dark matter lives (silent CronJobs, undocumented operators, opaque ServiceMonitors). This becomes the input to the target observability stack design — so the team isn't recreating an unknown set of alerts from scratch.
