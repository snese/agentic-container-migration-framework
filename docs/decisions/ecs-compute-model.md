# ECS Compute Model — Fargate vs EC2 vs Fargate Spot

> Once you've decided on ECS over EKS (see [`ecs-vs-eks.md`](./ecs-vs-eks.md)), the next decision is which **launch type** to run tasks on. Don't default to Fargate-everywhere.

## Decision matrix

| Factor | → Fargate (on-demand) | → Fargate Spot | → EC2 launch type |
|---|---|---|---|
| Steady-state utilization | Low / spiky | Interruption-tolerant batch | High (>50% sustained) |
| Cost sensitivity | Medium | High (up to ~70% off on-demand) | High at scale |
| GPU / accelerated workloads | ❌ Not supported | ❌ Not supported | ✅ Required |
| Windows containers | ✅ Supported | ❌ Not supported | ✅ Supported |
| Custom AMIs (kernel, drivers) | ❌ | ❌ | ✅ Required |
| Privileged containers / `--privileged` | ❌ | ❌ | ✅ Required |
| `host` networking mode | ❌ | ❌ | ✅ Required |
| Daemon-style sidecars (one per host) | ❌ | ❌ | ✅ (Daemon scheduling strategy) |
| Patching / OS management | AWS-managed | AWS-managed | Customer (or ECS-optimized AMI auto-updates) |
| Task startup latency | ~30–60s (cold) | ~30–60s (cold) | seconds (warm pool) |
| Bin-packing efficiency | N/A (per-task billing) | N/A | High (multiple tasks per instance) |

## When EC2 wins (vs Fargate)

Use the EC2 launch type when **at least one** of these applies:

1. **GPU / accelerated compute.** Fargate has no GPU SKUs. ML inference, transcoding,
   CUDA workloads → EC2 with a GPU instance family (e.g. `g5`, `g6`).
2. **High steady-state utilization.** A long-running service that pins CPU/memory at
   >50% is cheaper on a right-sized EC2 fleet than on per-task Fargate billing.
   Run a per-workload cost model before defaulting to Fargate.
3. **Spot-aggressive batch.** EC2 Spot offers a wider instance selection than Fargate Spot
   and works with [Capacity Providers](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-capacity-providers.html)
   for graceful drains.
4. **Windows containers with custom drivers** or process-isolation modes Fargate
   doesn't expose.
5. **Custom AMI requirements.** Custom kernel modules, FIPS images, customer-mandated
   hardening baselines, or compliance scanners that must live on the host.
6. **Daemon workloads** (one task per host: log shippers, security agents, eBPF probes).
   Fargate has no host concept; use the EC2 `DAEMON` scheduling strategy instead.
7. **Privileged / `host` networking** — required by some legacy lift-and-shift workloads.
   Fargate explicitly disallows both.

## When Fargate Spot wins

- Stateless **batch** jobs that can be replayed (data pipelines, image processing).
- Async queue consumers (SQS, Kinesis) that resume from checkpoint.
- CI runners and ephemeral build agents.
- 2-minute interruption notice is sufficient to drain.

Avoid Fargate Spot for: anything user-facing with strict tail-latency SLOs, stateful tasks,
or workloads without idempotent restart semantics.

## When Fargate (on-demand) wins

Default for **stateless services** that:

- Have spiky / unpredictable load.
- Don't need GPU, custom AMI, privileged mode, or host networking.
- Benefit from per-task isolation and zero capacity-planning overhead.

## References

- [Amazon ECS pricing](https://aws.amazon.com/ecs/pricing/) — Fargate vs EC2 vs Fargate Spot pricing model.
- [AWS Fargate Spot announcement (re:Invent 2019)](https://aws.amazon.com/blogs/aws/aws-fargate-spot-now-generally-available/) — cost discount and interruption semantics.
- [ECS Capacity Providers](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-capacity-providers.html) — strategy for blending Fargate, Fargate Spot, and EC2.
- [ECS launch type comparison](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/launch_types.html) — official feature matrix.
