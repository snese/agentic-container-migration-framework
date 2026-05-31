# Anthos-on-VMware — Known Gotchas

## vSphere CSI is the #1 migration blocker

Persistent volumes provisioned by `csi.vsphere.vmware.com` are bound to vSphere datastores.
Migrating these PVs is non-trivial:

- Block volumes (databases) → use DMS or app-level replication; cannot just `kubectl apply`
- RWX (NFS via vSphere CSI) → migrate to EFS or FSx; mount path changes
- Snapshot lineage (vSphere snapshots vs EBS snapshots) → not portable

**Action:** during discovery, surface every PV with `csi.vsphere.vmware.com` driver and tag with
"data migration plan needed." Customers consistently underestimate this.

## Sidecars come back

Anthos clusters are full of injected sidecars: ASM (`istio-proxy`), Config Management
(`gatekeeper`), Cloud Operations (`fluentbit-otel`), etc. Workload manifests don't show them.

**Action:** sample one running pod (`kubectl get pod -o yaml`) and compare to the source
Deployment. Differences = injected sidecars. On EKS, decide for each: bring it (Istio), drop it
(Anthos-only agents), or replace with AWS-native (CloudWatch agent for logs).

## Multi-cluster Service Mesh becomes single-cluster on AWS

Anthos customers often run a federated Istio mesh across multiple Anthos clusters. On AWS,
the typical pattern is one EKS cluster per VPC, with cross-VPC service via PrivateLink or
Transit Gateway — not mesh federation.

**Migration impact:** the mesh-federation routing rules (DNS, mTLS chain, traffic shifting)
need redesign. Customers who designed for "any cluster, any service" find the AWS pattern
restrictive. Plan time for this.

## Private Artifact Registry mirror

Many Anthos-on-VMware customers run Google Artifact Registry's on-prem mirror. On AWS this
becomes ECR. Migration:

1. Set up ECR replication (or ECR pull-through cache for read-only consumption)
2. Update `imagePullSecrets` in workloads
3. Re-tag images for ECR repository naming convention
4. Validate registry-side scanning and signing replicate (Inspector + Signer on AWS)

This is several days of work per registry; budget accordingly.

## vCenter inventory probing requires `govc` credentials

The `govc` integration in `anthos-vmware-export.sh` needs `GOVC_URL`, `GOVC_USERNAME`,
`GOVC_PASSWORD`, and a vSphere read-only role. Customers in regulated environments may not
grant this on first pass — degrade gracefully (log to `skipped[]`) rather than fail the run.

## Anthos Config Management vs Flux

Config Sync supports `RootSync` (cluster-scoped) and `RepoSync` (namespace-scoped). Flux v2
uses `Kustomization` resources, all cluster-scoped but with `targetNamespace` field. Multi-tenant
namespace-scoped sync semantics need a redesign — usually involves giving each tenant its own
Flux source/Kustomization.

## Workload Identity rewrite

`iam.gke.io/gcp-service-account` annotation → `eks.amazonaws.com/role-arn` annotation. Plus
each workload needs a corresponding IAM role + IRSA trust policy. Bulk-rewrite tooling exists
but the IAM trust policy must be customer-specific.

## 🚧 v0.8: Not yet covered (true SME items)

- vSphere fault-domain → AWS AZ topology mapping
- F5 BIG-IP / SeeSaw → AWS Load Balancer Controller migration playbook
- Detailed DMS configuration for typical Anthos databases (Postgres, MySQL, MongoDB)
- Anthos Identity Service → IAM Identity Center / Cognito mapping
