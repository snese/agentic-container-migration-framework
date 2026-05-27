# Anthos-on-Bare-Metal → AWS Feature Mapping

| Anthos / bare-metal feature | AWS Equivalent (EKS) | Migration Notes |
|---|---|---|
| Bare-metal node | EC2 (general or `*.metal` instance) | Use `*.metal` only when PCI passthrough / GPU passthrough is required |
| Anthos Config Management (Config Sync) | Flux v2 / ArgoCD on EKS | Same migration as Anthos-on-VMware |
| Anthos Service Mesh | Istio on EKS / App Mesh | Same migration; in-tree mesh |
| Policy Controller (Gatekeeper) | Kyverno / Gatekeeper on EKS | Choose one |
| Local-path provisioner | EBS gp3 (RWO) / EFS (RWX) | Local-path is single-node; needs replication strategy on AWS |
| MetalLB / kube-vip | NLB / ALB | LoadBalancer Service → AWS Load Balancer Controller |
| Direct hardware access (NIC, GPU) | Bottlerocket + EC2 metal | 🚧 Needs SME review per workload |
| GPU workloads (NVIDIA Operator) | EKS + NVIDIA Operator on g5/p4/p5 EC2 | Driver versions usually match; instance choice is the call |
| DPDK / SR-IOV / hostNetwork=true workloads | EKS + ENA / EFA / specialized AMI | 🚧 Each workload needs a separate design — not a 1:1 swap |
| Multi-NIC pods (Multus) | 🚧 Limited — EKS supports VPC CNI primary + secondary; Multus on AWS is community-supported | SME review |
| Anthos Identity (LDAP/AD/OIDC) | Cognito / IAM Identity Center / external IdP via OIDC | Identity provider migration is a separate work stream |
| Anthos Connect (registration) | EKS Connector | Different model; on AWS, EKS Connector is for cross-account view, not management |
| Local container registry | ECR with VPC endpoint or pull-through cache | Air-gap → ECR public + private replication |

## Notes

- **PCI passthrough / GPU**: bare-metal customers often have these. Confirm AWS EC2 instance family supports the device class before promising drop-in.
- **Networking model**: bare-metal often uses BGP + MetalLB; on AWS this becomes ALB/NLB or Global Accelerator. The IP-allocation contract changes — pods get VPC IPs via VPC CNI.
- **Disk model**: local NVMe (`local-path`) is fastest on bare-metal; EBS gp3 is closest equivalent on EC2 but has different IOPS limits per volume.
