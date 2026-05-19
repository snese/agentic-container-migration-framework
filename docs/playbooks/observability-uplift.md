# Observability Uplift Playbook — GCP / Anthos → AWS

> **Scope.** Methodology-level guidance: how to map Cloud Operations
> (formerly Stackdriver) and Anthos Service Mesh telemetry onto AWS
> observability primitives, when to use [CloudWatch Container
> Insights][container-insights] vs [Amazon Managed Service for
> Prometheus (AMP)][amp], log-routing patterns, and tracing migration.
> **Not** a Grafana / Fluent Bit tutorial — every step links to upstream
> docs. Target length: 1–2 pages.
>
> **Cost-claim policy.** Cost is the single biggest trap in observability
> migrations (log volume can dominate cluster spend). Public pricing pages
> are linked; specific dollar examples are
> `[INTERNAL-REVIEW-NEEDED]` so the AWS-internal reviewer can plug in
> real ingest / retention numbers.

## 1. Source Mapping (GCP / Anthos → AWS)

| GCP / Anthos surface | AWS native equivalent | Notes |
|---|---|---|
| Cloud Logging (formerly Stackdriver Logging) | CloudWatch Logs | Log groups + retention. Use the Container Insights log groups for k8s. |
| Cloud Monitoring (formerly Stackdriver Monitoring) | CloudWatch Metrics + [Container Insights][container-insights] | Plus AMP for Prometheus-shaped data. |
| Managed Service for Prometheus (GCP) | [Amazon Managed Service for Prometheus (AMP)][amp] | Drop-in for Prometheus remote-write workloads. |
| Cloud Trace | [AWS X-Ray][xray] (or AMP+Tempo via OSS path) | See §4. |
| Anthos Service Mesh telemetry (Istio + Stackdriver adapter) | Istio + Prometheus → AMP, optionally CloudWatch via [ADOT][adot] | Keep Istio metrics shape; swap the sink. |
| Cloud Operations dashboards | Grafana on [Amazon Managed Grafana (AMG)][amg] | IaC-as-dashboards (§5). |
| Cloud Operations alerts | CloudWatch Alarms + AMG alert rules | Pick **one** alert engine per signal — do not double-alert. |

## 2. CloudWatch Container Insights vs AMP — When to Use Each

Both are valid; pick per signal type, not per cluster.

| Use [Container Insights][container-insights] when… | Use [AMP][amp] when… |
|---|---|
| You want a managed, opinionated view of cluster / node / pod health out of the box | You already speak Prometheus (alerting rules, recording rules, exporters) |
| Targets are CloudWatch alarms and AWS-native dashboards | Targets are Grafana dashboards on [AMG][amg] and PromQL alerting rules |
| You want logs + metrics + (optional) traces correlated in one console | You need long-term Prometheus retention beyond what self-hosted Prometheus offers |
| Workload count is small and stable | Workload count or cardinality is high and Prometheus-native sharding helps |
| Setup speed matters more than vendor neutrality | Vendor neutrality / portability matters (PromQL is portable; CloudWatch query language is not) |

**Pragmatic default:** run **both**. Container Insights for the
out-of-the-box cluster overview ([setup quickstart][container-insights-setup]),
AMP for the application-level metrics that Prometheus exporters already
produce, AMG as the single pane that queries both.

Cost: see [CloudWatch pricing][cw-pricing] and [AMP pricing][amp-pricing].
Specific monthly $ for a customer cluster is `[INTERNAL-REVIEW-NEEDED]`.

## 3. Log Routing Patterns — and the Cost Trap

Logs almost always dominate observability spend. Decide routing before
ingest, not after.

| Pattern | Use when | Notes |
|---|---|---|
| **Fluent Bit → CloudWatch Logs** | Incumbent on most Anthos clusters; least migration risk | Native [Fluent Bit][fluent-bit] CloudWatch output. Tune `Log_Level`, `Match`, and `Buffer_*` to drop debug noise at the source. |
| **FireLens** (ECS) / Fluent Bit sidecar (EKS) | Per-task / per-pod log routing with multiple sinks | [FireLens docs][firelens] for ECS. On EKS, run Fluent Bit as a DaemonSet. |
| **Vector** | Heavy filtering / transformation needed, mixed-sink fan-out | [Vector][vector] is OSS; useful when you need to drop a large fraction of log lines before they hit any paid sink. |
| **Direct stdout → CloudWatch via awslogs driver** | Tiny clusters, no transformation needed | No filtering — full firehose. Cheap to set up, expensive to run at scale. |

**Cost trap (universal).** A noisy `DEBUG` logger in a busy service can
multiply CloudWatch Logs ingest 10–100× overnight. Mitigations, in order:

1. **Drop at the source** (lower log level in code or config). Cheapest.
2. **Drop in the agent** (Fluent Bit `Filter`s, Vector `transforms`).
3. **Tier retention** — short retention on DEBUG/INFO log groups, longer
   on audit / WARN/ERROR.
4. **Sample** before sending to expensive sinks; keep full fidelity in S3
   (cheap) and use Athena for ad-hoc queries.

Specific dollar savings from these mitigations are
`[INTERNAL-REVIEW-NEEDED]`; see [CloudWatch pricing][cw-pricing].

## 4. Tracing — OpenTelemetry First

Default to an [OpenTelemetry Collector][otel-collector] deployment
(DaemonSet + gateway pattern). Then choose backend(s):

| Backend | Choose when |
|---|---|
| [AWS X-Ray][xray] via [ADOT][adot] | You want AWS-native sampling, service maps, and IAM-based access control |
| Self-hosted Tempo / Jaeger via OTLP | You want vendor neutrality / hybrid; willing to run the backend |
| Both | Hybrid period during migration; OTLP fan-out is one-line in the collector config |

ADOT ([AWS Distro for OpenTelemetry][adot]) is the AWS-supported
OpenTelemetry distribution; it is upstream-compatible. Migrating from
Cloud Trace = swap exporter, keep instrumentation. Do not re-instrument
applications during the migration window.

## 5. Dashboards & Alerts — IaC, Not Clicks

- Standardise on Grafana on [AMG][amg]; export source dashboards as JSON
  and check them into the same repo as the IaC.
- Define alert rules **in code** (PromQL alert files, CloudWatch alarms
  via Terraform/CDK). UI-clicked alerts are unreviewable and
  unrepeatable across environments.
- Pick a single alerting plane per signal type (e.g. AMG alerts for
  application metrics, CloudWatch alarms for AWS-service metrics) so
  on-call is not paged twice for the same condition.
- Migrate dashboards in waves matching the cutover plan in
  [`traffic-shifting.md`](./traffic-shifting.md) — there should never
  be a workload running on AWS without a working dashboard pointing at
  it.

## 6. Cost Estimation — Pointers Only

Plug real ingest / retention / metric counts into the calculators on
the pricing pages below. Do not estimate from a generic "% saving"
number — observability costs are workload-specific, not platform-
specific.

- [CloudWatch pricing][cw-pricing] — Logs ingest, storage, metrics, alarms,
  Container Insights surcharge.
- [AMP pricing][amp-pricing] — metric samples ingested, active series
  stored, query samples processed.
- [AMG pricing][amg-pricing] — per-active-user, not per-dashboard.

Specific monthly cost figures are `[INTERNAL-REVIEW-NEEDED]`. The
customer-facing AWS account team has access to AWS Pricing Calculator
templates that should be used in place of any made-up numbers here.

## 7. Validation Checklist (binary)

- [ ] **Logs:** every workload has at least one log group with documented
      retention; no workload defaults to "never expire".
- [ ] **Metrics:** Container Insights enabled or AMP scraping configured
      (or both); cluster overview dashboard exists in AMG.
- [ ] **Traces:** ADOT collector deployed; X-Ray service map populated for
      at least the top-10 services by traffic.
- [ ] **Alerts:** every Sev-1 / Sev-2 SLO has an IaC-defined alert; UI-
      created alerts archived or migrated.
- [ ] **Cost guard-rail:** budget alarm on CloudWatch Logs ingest at
      Nx baseline (N defined per cluster) so a runaway logger pages
      on-call before it bills.
- [ ] **Source decommission:** Cloud Logging / Cloud Monitoring exporters
      removed from migrated workloads; Stackdriver agents stopped.

## 8. References

- AWS docs: [CloudWatch Container Insights][container-insights] ·
  [Container Insights setup (EKS quickstart)][container-insights-setup] ·
  [Amazon Managed Service for Prometheus (AMP)][amp] ·
  [Amazon Managed Grafana (AMG)][amg] · [AWS X-Ray][xray] ·
  [FireLens (ECS)][firelens]
- Pricing: [CloudWatch][cw-pricing] · [AMP][amp-pricing] · [AMG][amg-pricing]
- OSS: [OpenTelemetry Collector][otel-collector] ·
  [AWS Distro for OpenTelemetry (ADOT)][adot] ·
  [Fluent Bit][fluent-bit] · [Vector][vector]
- ACMF: [`docs/phases/04-modernize.md`](../phases/04-modernize.md)

[container-insights]: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights.html
[container-insights-setup]: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-EKS-quickstart.html
[amp]: https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html
[amg]: https://docs.aws.amazon.com/grafana/latest/userguide/what-is-Amazon-Managed-Service-Grafana.html
[xray]: https://docs.aws.amazon.com/xray/latest/devguide/aws-xray.html
[firelens]: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_firelens.html
[adot]: https://aws-otel.github.io/
[otel-collector]: https://opentelemetry.io/docs/collector/
[fluent-bit]: https://docs.fluentbit.io/
[vector]: https://github.com/vectordotdev/vector
[cw-pricing]: https://aws.amazon.com/cloudwatch/pricing/
[amp-pricing]: https://aws.amazon.com/prometheus/pricing/
[amg-pricing]: https://aws.amazon.com/grafana/pricing/
