# Anthos manifest test fixtures

These three samples cover the most common Anthos-specific constructs that
need translation when migrating to EKS. They are inputs for the rules
defined in [`adapters/source/anthos-vmware/manifest-transforms.yaml`](../../adapters/source/anthos-vmware/manifest-transforms.yaml).

| File | Anthos features exercised | Rules applied |
|---|---|---|
| `01-deployment-workload-identity.yaml` | Workload Identity SA, ASM revision label, ASM managed-proxy annotation, GCR image, Anthos addon labels | `workload_identity_to_pod_identity`, `asm_revision_label_strip`, `asm_managed_dataplane_annotation`, `registry_gcr_to_ecr`, `drop_anthos_managed_labels` |
| `02-ingress-gce.yaml` | NEG annotation, BackendConfig CRD, app-protocols, `gce-internal` ingress class, GKE managed certs | `drop_neg_annotation`, `drop_backend_config`, `drop_app_protocols`, `ingress_class_to_alb`, `ingress_alb_annotations` |
| `03-statefulset-vsphere-csi.yaml` | vSphere CSI StorageClass, deprecated zone label, GCR image | `storageclass_vsphere_to_ebs_gp3`, `nodeselector_zone_topology`, `registry_gcr_to_ecr` |

For a worked end-to-end example showing the *output* of these rules, see
[`examples/anthos-vmware-to-eks/`](../anthos-vmware-to-eks/).

## Smoke test

```bash
# Apply a single rule with yq:
yq '.metadata.annotations["eks.amazonaws.com/role-arn"] =
    ("arn:aws:iam::123456789012:role/" + (.metadata.annotations["iam.gke.io/gcp-service-account"] | split("@")[0]) + "-role")
    | del(.metadata.annotations["iam.gke.io/gcp-service-account"])' \
  examples/anthos-manifests/01-deployment-workload-identity.yaml
```
