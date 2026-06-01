# Anthos-on-Bare-Metal — Known Gotchas

## Hardware-bound workloads dominate the migration risk

Bare-metal customers run on bare metal *for a reason* — usually one or more of:

- GPU workloads (training, inference)
- Network-heavy workloads (telco, NFV, DPDK, SR-IOV)
- Latency-sensitive workloads (HFT, real-time analytics)
- Data-gravity (multi-PB local storage)

**Detection signals to surface in discovery:**
- `resources.limits."nvidia.com/gpu"` on any pod
- `resources.limits."intel.com/sriov_*"` or `"openshift.io/sriov_*"`
- `hostNetwork: true` on Deployments/DaemonSets
- DaemonSets named `multus`, `whereabouts`, `sriov-cni`, `nvidia-device-plugin`
- StorageClasses with `provisioner: kubernetes.io/no-provisioner` (raw local volumes)

**Each of these needs an architecture review BEFORE wave planning.** Do not promise lift-and-shift.

## Local-path storage is single-node

`rancher.io/local-path` and `kubernetes.io/no-provisioner` give you fast PV access — but only on
the node where the volume lives. Pod scheduling becomes node-pinned.

**Migration impact:** On EKS this becomes either:
- EBS gp3 (RWO, replicated by AWS, but slower than NVMe local)
- Instance store (NVMe, but ephemeral — pod restart on a new node loses data)
- EFS (RWX, slower, network-attached)

For databases that depended on local NVMe + replication-at-app-layer, a redesign is usually
required. 🚧 SME triage essential.

## MetalLB / kube-vip → AWS Load Balancer Controller

Bare-metal `Service: LoadBalancer` is implemented by MetalLB (BGP) or kube-vip. These are
self-contained and don't translate to anything on AWS. On EKS the AWS Load Balancer Controller
provisions ALBs / NLBs, which are managed services with different SLA + cost models.

## OS choice on AWS

Anthos bare-metal nodes run customer-chosen OS (RHEL, Ubuntu, others). On EKS the supported
node images are: Amazon Linux 2/2023, Bottlerocket, or BYO AMI. If the customer hand-built their
node OS for a reason (kernel modules, custom drivers), they need to either rebuild that as a
custom AMI or accept the AWS-curated images.

## Air-gap parity

Both Anthos bare-metal and AWS support air-gapped deployments — but the AWS air-gap story for
EKS uses **EKS Anywhere** (still K8s on customer infra) or **AWS Outposts** (EC2 in a customer
DC). Pure on-prem bare-metal Anthos → public-cloud EKS can fail the air-gap requirement.

🚧 If air-gap is a hard requirement, EKS Anywhere is a likely target instead — but ACMF doesn't
yet have an EKS Anywhere target adapter.

## Beyond v0.8 scope (true SME items)

- BMC-level inventory (Redfish, IPMI) — not collected by the export script (out-of-band channel)
- Full SR-IOV / DPDK migration playbook (script flags the workloads; design review is the next step)
- GPU driver version compatibility matrix (NVIDIA driver vs CUDA vs EKS AMI) — needs per-workload triage
- Multi-NIC (Multus) → AWS Network Load Balancer / multiple ENIs translation
