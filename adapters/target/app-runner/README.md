# Target Adapter: AWS App Runner

## When to choose App Runner

- Single-purpose HTTP service
- Stateless
- Minimal ops appetite
- Acceptable per-request pricing model

## When NOT

- Long-lived TCP / WebSocket connections (cold-start risk)
- Egress-heavy workloads (NAT cost)
- Need for sidecars
- Need for custom networking

## Patterns

- Container image source from ECR
- Auto scaling per concurrency
- VPC connector for private dependencies
- Custom domain via Route 53

## TBD

- IaC sample
- Anthos → App Runner migration pattern (rare but real)
