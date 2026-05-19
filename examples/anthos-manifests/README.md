# examples/anthos-manifests

Test fixtures for `adapters/source/anthos-vmware/manifest-transforms.yaml`.

| File | Rule exercised |
|---|---|
| `01-serviceaccount.yaml` | `workload-identity-to-pod-identity` |
| `02-ingress.yaml`        | `gce-ingress-to-alb` |
| `03-vsphere-csi-pvc.yaml`| `vsphere-csi-to-ebs-or-efs` |

`before/` is the as-discovered Anthos manifest. `after/` is the expected
result of applying the rule's automation. Diffing `before/` against `after/`
serves as the golden reference for any tooling that automates the transforms.

## Verifying transforms manually

```bash
# Pre-req: yq v4.x (mikefarah/yq), AWS_ACCOUNT_ID + ISTIO_REV exported.
export AWS_ACCOUNT_ID=123456789012
export ISTIO_REV=1-22-3

cp -r before /tmp/before && cp -r after /tmp/after
# Apply automations from manifest-transforms.yaml in-place against /tmp/before,
# then diff against /tmp/after — diffs should be empty (modulo formatting).
diff -ruN /tmp/before /tmp/after
```

The `manifest-transforms.yaml` rule body contains the exact `yq` commands;
copy them into a script as needed. These fixtures are intentionally minimal —
add more pairs for any rule you extend.
