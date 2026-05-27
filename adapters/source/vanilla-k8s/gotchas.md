# Vanilla K8s — Known Gotchas

## "Vanilla" usually has more customizations than the customer admits

Self-managed K8s clusters accumulate customizations:

- Custom kernel parameters via `kubelet --system-reserved`
- Custom CRI runtime config (containerd / CRI-O patches)
- Hand-installed device plugins (NVIDIA, intel SR-IOV)
- Webhooks deployed by name but no IaC trail

**Action:** during discovery, capture `kubelet` config (`/var/lib/kubelet/config.yaml`) if the
script is run on a node, and surface any non-default fields in `warnings[]`.

## kops-on-AWS vs EKS-on-AWS

If the customer is on kops on AWS, they're already inside AWS. "Migration" really means
"swap kops for EKS." Useful when:

- Customer wants to drop self-managed control plane ops
- AWS support gets involved (kops support is community; EKS support is AWS)
- Customer wants to use IRSA, ALB Controller managed by AWS, etc.

But it's NOT a wave-by-wave migration; it's a cluster swap. Frame the project accordingly.

## Cluster Autoscaler vs Karpenter

If the customer uses Cluster Autoscaler with explicit ASGs, they're often surprised by Karpenter's
"just-in-time provisioning" model. Karpenter:

- Doesn't pre-allocate nodes by ASG
- Picks instance type based on pending pod requirements
- Scales down faster (and more aggressively)

**Action:** flag CA usage in discovery; recommend Karpenter as default but call out the
operational mental model shift.

## Custom AMIs / kernel modules

Self-managed customers sometimes have:

- Custom kernel modules (eBPF programs, custom security agents)
- Hand-rolled OS hardening
- BYO kernel version (RHEL ELS, Ubuntu HWE)

EKS-managed nodes use AWS-curated AMIs (Bottlerocket, Amazon Linux 2023). Customizations need to
be either:
- Built into a custom AMI (added to Image Builder pipeline)
- Replaced with Bottlerocket settings (limited surface)
- Dropped (if the customization is no longer needed in cloud)

## Prometheus on customer-managed storage

Self-managed Prometheus often runs with an emptyDir or local-path volume because it's stateful
but treated as ephemeral. On EKS, the same volume choice still works — but if the customer
expects **Prometheus durability**, they need to plan EBS / EFS / AMP.

**Common pitfall:** moving Prometheus to EKS without picking the right storage tier → metrics
get lost on node replacement.

## etcd backup discipline disappears

Self-managed customers usually have an etcd backup cron job. On EKS, AWS owns etcd backups.
The customer's etcd backup script should be retired during cutover — leaving it running creates
confused operators wondering where the backups go.

## Air-gap

Vanilla K8s in air-gapped environments uses a private registry (Harbor / Nexus / Artifactory).
On AWS, this becomes ECR with VPC endpoints. Migration requires:

- Image mirror set up before cutover (replication or pull-through cache)
- Pull credentials updated in workloads (often hardcoded `imagePullSecrets`)
- Air-gap → public AWS may not be acceptable; surface as a constraint early

## 🚧 v0.7-rc: Not yet covered

- Talos-specific configuration (`machineconfig`) → AMI translation
- CAPI-managed cluster → CAPI-managed EKS migration playbook
- Hand-rolled GitOps (yamls in a repo + `kubectl apply` cron) → Flux/ArgoCD onboarding
