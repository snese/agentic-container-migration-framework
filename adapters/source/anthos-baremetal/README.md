# Source Adapter: Anthos on Bare Metal

**Status:** ✅ v0.8 — discovery complete for the K8s + Anthos software layers. Hardware-bound workloads (`hostNetwork`, `privileged`, GPU, SR-IOV, Multus annotations, hostPath, hugepages, RDMA, FPGA) are now auto-detected and surfaced in `.workloads_hardware_bound[]` with a single SME-triage warning. BMC-level hardware inventory (Redfish/IPMI) and driver-version compatibility matrices remain true SME items — bring rack/chassis docs to architecture review.

## Scope

Anthos clusters running on customer-managed bare metal (the "Anthos clusters on bare metal" SKU).
Customer owns the OS, hardware, and networking; Anthos provides the K8s control plane + Anthos
software (Config Management, Service Mesh, Policy Controller).

## What this adapter provides

- Discovery prompt: [`prompts/discovery/anthos-baremetal.prompt.md`](../../../prompts/discovery/anthos-baremetal.prompt.md)
- Self-export script: [`scripts/discovery/anthos-baremetal-export.sh`](../../../scripts/discovery/anthos-baremetal-export.sh)
- Feature mapping: [`mapping.md`](mapping.md)
- Known gotchas: [`gotchas.md`](gotchas.md)
- Fixtures (small + realistic) for offline testing

## Distinguishing signals

| Signal | What we check |
|---|---|
| Anthos bare metal admin | `cluster.baremetal.cluster.gke.io` CRD present |
| Hardware-bound workloads | Pods with `nvidia.com/gpu`, `intel.com/sriov_*`, hostNetwork: true |
| Local storage path | StorageClass `provisioner: rancher.io/local-path` or `kubernetes.io/no-provisioner` |
| Connect agent | `gke-connect-agent` Deployment in `gke-connect` namespace |

## Migration target priority

1. **EKS** — primary. Likely-target node group: bare-metal-equivalent EC2 (Metal instances `i3en.metal`, `r5n.metal`) only if customer needs PCI passthrough; otherwise standard EC2.
2. **EKS Anywhere** — relevant if customer wants to *stay* on bare metal but move off Anthos. Out of scope for this adapter (different framework path).
3. **ECS** — only viable for stateless portions of the portfolio.

See [`mapping.md`](mapping.md) for details. SME triage required for hardware-bound services.
