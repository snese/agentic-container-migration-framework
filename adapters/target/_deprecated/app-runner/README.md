# Target Adapter: AWS App Runner — ⛔ DEPRECATED

> **⚠️ DEPRECATION NOTICE — App Runner Maintenance Mode (2026-04-30)**
>
> AWS App Runner has entered **maintenance mode** as of 2026-04-30: no new customers, no new feature development. ACMF no longer recommends App Runner as a target for container migrations.
>
> - **For new HTTP-only services** → use **ECS Fargate behind ALB** (or behind API Gateway HTTP API for low-volume APIs).
> - **For existing App Runner workloads** → plan a move to ECS Fargate; the patterns in this adapter remain valid as historical reference and as a guide for "App Runner → Fargate" replatform work.
> - Tracking issue: [#37](https://github.com/snese/agentic-container-migration-framework/issues/37).
>
> This adapter is retained under `adapters/target/_deprecated/` so historical engagements that already chose App Runner have a documented baseline.

---

## When App Runner was chosen (historical context)

- Single-purpose HTTP service
- Stateless
- Minimal ops appetite
- Acceptable per-request pricing model

## When App Runner was NOT a fit

- Long-lived TCP / WebSocket connections (cold-start risk)
- Egress-heavy workloads (NAT cost)
- Need for sidecars
- Need for custom networking

## Patterns (legacy)

- Container image source from ECR
- Auto scaling per concurrency
- VPC connector for private dependencies
- Custom domain via Route 53

## Recommended replacement

ECS Fargate behind ALB delivers the same "no node management, container-only" model with active investment, sidecar support, and richer networking. See [`adapters/target/ecs-fargate/`](../../ecs-fargate/).
