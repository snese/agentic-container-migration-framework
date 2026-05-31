# Anthos-on-GCP — Known Gotchas

## Workload Identity is annotation-only — easy to miss

GKE Workload Identity binds a Kubernetes ServiceAccount to a GCP service account purely via the
`iam.gke.io/gcp-service-account` annotation. There is no associated Kubernetes object to grep for.

**Detection:** `kubectl get sa -A -o json | jq '.items[] | select(.metadata.annotations["iam.gke.io/gcp-service-account"])'`

**Migration impact:** Every such ServiceAccount needs an IAM role + IRSA trust policy on AWS. Pod
spec must drop the GCP annotation and set `eks.amazonaws.com/role-arn` instead.

## Config Sync `RootSync` is cluster-scoped, `RepoSync` is namespace-scoped

Customers often have **both**. Migrating to Flux v2 means:
- `RootSync` → `Kustomization` in `flux-system` namespace targeting `cluster: default`
- `RepoSync` → `Kustomization` per namespace, scoped via `kustomization.spec.serviceAccountName`

Multi-tenant policy boundaries are rebuilt, not auto-translated. 🚧 Worth a design review.

## Anthos Service Mesh managed control plane has no AWS equivalent

GKE's *managed* Istio means Google patches `istiod`. On EKS we either:
- Run Istio in-cluster ourselves (operational burden returns)
- Switch to App Mesh (in flux as a product line)
- Switch to ECS Service Connect (different API; not a drop-in for Istio CRs)

**Recommendation:** Istio on EKS for like-for-like; budget for an SRE on-call rotation that didn't exist on Anthos.

## GKE Autopilot resource overhead

Autopilot pods run with platform-managed sidecars (logging, security agent). On EKS these become
your responsibility — fluent-bit, GuardDuty agent, etc. — and your pod resource requests should be
re-baselined: customers consistently underestimate by ~10-15% when only the app container is sized.

## Cluster-level features that need explicit re-creation

| Anthos / GKE feature | Survives migration? |
|---|---|
| Cluster auto-upgrade | EKS has cluster + node-group versioning, but no auto-upgrade by default |
| Cloud Armor (via GKE Ingress) | Becomes AWS WAF + ALB |
| GKE Backup | Becomes Velero or AWS Backup for EKS (preview) |
| Anthos Connect Gateway | EKS Connector exists but workflows differ (no `gcloud container fleet memberships`) |

## Networking surprises

- **GKE alias IPs** — pod IPs come from a secondary subnet range. EKS VPC CNI gives pods primary VPC IPs by default. Subnet sizing math is different.
- **Cloud DNS for GKE** — DNS is solved by the GCP project. On AWS, every cluster needs CoreDNS sized + Route 53 patterns picked.
- **Private GKE cluster** — control-plane endpoint is private. Equivalent on EKS is "Private Endpoint" + VPC peering / Transit Gateway; review jump-box / IDE access.

## 🚧 v0.8: Not yet covered (true SME items)

- Backup-for-GKE-encrypted-with-CMEK → AWS Backup-equivalent KMS migration
- GKE Sandbox (gVisor) → no direct AWS equivalent; needs SME triage per workload
- Workload Identity Federation **cross-project** trust → IAM Identity Center / SAML federation
