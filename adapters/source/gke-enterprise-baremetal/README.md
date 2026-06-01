# Source Adapter: GKE Enterprise on Bare Metal (formerly Anthos clusters on bare metal)

**Status:** ✅ Phase 1 enrichment complete on main's `lib/` architecture.

> **Naming note.** This adapter follows main's `gke-enterprise-*` taxonomy
> (introduced when `anthos-vmware` → `gke-enterprise-vmware` shipped). The
> Anthos product name persists for the bare-metal SKU in some Google docs.

The gke-enterprise-baremetal-export.sh script collects bare-metal-specific
signals on top of the shared K8s core layer:

- **Anthos bare-metal admin CRDs** (`cluster.baremetal.cluster.gke.io`)
  when present →
  `clusters[0].anthos.{baremetal_cluster_count, baremetal_cluster_names}`
- **Hardware-bound workload mining** — every workload using `hostNetwork`,
  `privileged`, GPU, SR-IOV, Multus annotations, `hostPath`, `hostPID`,
  `hostIPC`, RDMA, FPGA, or hugepages → top-level `workloads_hardware_bound[]`.
  Each requires SME triage for AWS placement (EC2 `*.metal` vs ENA/EFA vs
  redesign).

No hypervisor / vCenter layer (bare-metal). BMC-level inventory (Redfish,
IPMI) and driver-version compatibility matrices remain SME items.

## Scope

GKE Enterprise on customer-managed bare metal. Customer owns the OS,
hardware, and networking; GKE Enterprise provides the K8s control plane +
Anthos software (Config Management, Service Mesh, Policy Controller).

## What this adapter provides

- Self-export script: [`scripts/discovery/gke-enterprise-baremetal-export.sh`](../../../scripts/discovery/gke-enterprise-baremetal-export.sh)
- Feature mapping: [`mapping.md`](mapping.md)
- Known gotchas: [`gotchas.md`](gotchas.md)
- Fixtures (small) for offline schema validation: [`fixtures/`](fixtures/)

## Distinguishing signals

| Signal | What we check |
|---|---|
| GKE Enterprise bare-metal admin | `cluster.baremetal.cluster.gke.io` CRD present |
| Hardware-bound workloads | Pods with `nvidia.com/gpu`, `*sriov*`, `hostNetwork: true`, `hostPath`, etc. (mined in jq) |
| Local storage path | StorageClass `provisioner: rancher.io/local-path` or `kubernetes.io/no-provisioner` |
| Connect agent | `gke-connect-agent` Deployment in `gke-connect` namespace |

## Migration target priority

1. **EKS** — primary. Likely-target node group: bare-metal-equivalent EC2
   (Metal instances `i3en.metal`, `r5n.metal`) only if customer needs PCI
   passthrough; otherwise standard EC2.
2. **EKS Anywhere** — relevant if customer wants to *stay* on bare metal but
   move off GKE Enterprise. Out of scope for this adapter (different framework
   path).
3. **ECS** — only viable for stateless portions of the portfolio.

See [`mapping.md`](mapping.md) for details. SME triage required for
hardware-bound services.
