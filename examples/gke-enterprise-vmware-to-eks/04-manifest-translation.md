# Manifest Translation — Before / After

This document shows ACME Corp's `payment-api` and `inventory-db` manifests
**before** (GKE Enterprise on VMware) and **after** (EKS), with each change linked back to a
rule id from
[`adapters/source/gke-enterprise-vmware/manifest-transforms.yaml`](../../adapters/source/gke-enterprise-vmware/manifest-transforms.yaml).

The "before" YAMLs are the same shape as the test fixtures in
[`examples/gke-enterprise-manifests/`](../gke-enterprise-manifests/).

---

## A. `payment-api` Deployment + ServiceAccount

### Before (GKE Enterprise on VMware)

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: payment-api-sa
  namespace: payments
  annotations:
    iam.gke.io/gcp-service-account: payment-api@acme-prod.iam.gserviceaccount.com
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-api
  namespace: payments
  labels:
    app: payment-api
    addons.gke.io/managed: "true"
spec:
  replicas: 4
  selector: { matchLabels: { app: payment-api } }
  template:
    metadata:
      labels:
        app: payment-api
        istio.io/rev: asm-1-20-2-asm-2
      annotations:
        mesh.cloud.google.com/proxy: '{"managed":"true"}'
    spec:
      serviceAccountName: payment-api-sa
      containers:
        - name: api
          image: gcr.io/acme-prod/payments/api:v1.42.0
          ports: [{ containerPort: 8080 }]
```

### After (EKS)

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: payment-api-sa
  namespace: payments
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/payment-api-role
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-api
  namespace: payments
  labels:
    app: payment-api
spec:
  replicas: 4
  selector: { matchLabels: { app: payment-api } }
  template:
    metadata:
      labels:
        app: payment-api
        istio.io/rev: default
    spec:
      serviceAccountName: payment-api-sa
      containers:
        - name: api
          image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/payments/api:v1.42.0
          ports: [{ containerPort: 8080 }]
```

### Change log

| # | Change | Rule id |
|---|---|---|
| 1 | `iam.gke.io/gcp-service-account` → `eks.amazonaws.com/role-arn` (Pod Identity / IRSA) | `workload_identity_to_pod_identity` |
| 2 | Removed `addons.gke.io/managed` label | `drop_anthos_managed_labels` |
| 3 | `istio.io/rev: asm-1-20-2-asm-2` → `istio.io/rev: default` | `asm_revision_label_strip` |
| 4 | Removed `mesh.cloud.google.com/proxy` annotation | `asm_managed_dataplane_annotation` |
| 5 | `gcr.io/acme-prod/...` → `<account>.dkr.ecr.us-east-1.amazonaws.com/...` | `registry_gcr_to_ecr` |

---

## B. `payment-api` Service + Ingress

### Before

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: payment-api
  namespace: payments
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
    cloud.google.com/backend-config: '{"default": "payment-api-bc"}'
    cloud.google.com/app-protocols: '{"https": "HTTPS"}'
spec:
  type: ClusterIP
  selector: { app: payment-api }
  ports: [{ name: https, port: 443, targetPort: 8080 }]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: payment-api-ingress
  namespace: payments
  annotations:
    kubernetes.io/ingress.class: gce-internal
spec:
  rules:
    - host: pay.acme.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: payment-api, port: { number: 443 } } }
```

### After

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: payment-api
  namespace: payments
spec:
  type: ClusterIP
  selector: { app: payment-api }
  ports: [{ name: https, port: 443, targetPort: 8080 }]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: payment-api-ingress
  namespace: payments
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
spec:
  ingressClassName: alb
  rules:
    - host: pay.acme.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: payment-api, port: { number: 443 } } }
```

### Change log

| # | Change | Rule id |
|---|---|---|
| 1 | Removed `cloud.google.com/neg` | `drop_neg_annotation` |
| 2 | Removed `cloud.google.com/backend-config`; replaced by ALB annotations | `drop_backend_config` + `ingress_alb_annotations` |
| 3 | Removed `cloud.google.com/app-protocols`; protocol on ALB instead | `drop_app_protocols` |
| 4 | `kubernetes.io/ingress.class: gce-internal` → `ingressClassName: alb` + `scheme: internal` | `ingress_class_to_alb` |
| 5 | Added `alb.ingress.kubernetes.io/scheme` + `target-type` baseline | `ingress_alb_annotations` |

---

## C. `inventory-db` StatefulSet + StorageClass

### Before

```yaml
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: vsphere-csi-fast }
provisioner: csi.vsphere.vmware.com
parameters: { storagepolicyname: gold }
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: inventory-db, namespace: inventory }
spec:
  template:
    spec:
      nodeSelector:
        failure-domain.beta.kubernetes.io/zone: dc-tpe-1a
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: vsphere-csi-fast
        resources: { requests: { storage: 100Gi } }
```

### After

```yaml
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: ebs-gp3 }
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: inventory-db, namespace: inventory }
spec:
  template:
    spec:
      nodeSelector:
        topology.kubernetes.io/zone: us-east-1a
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: ebs-gp3
        resources: { requests: { storage: 100Gi } }
```

### Change log

| # | Change | Rule id |
|---|---|---|
| 1 | StorageClass: vSphere CSI → EBS gp3 | `storageclass_vsphere_to_ebs_gp3` |
| 2 | `failure-domain.beta.kubernetes.io/zone` → `topology.kubernetes.io/zone` | `nodeselector_zone_topology` |
| 3 | Zone literal updated `dc-tpe-1a` → `us-east-1a` | manual (zone names are not portable) |

---

## Notes on data migration

Manifest translation does **not** migrate the data inside the PV. Data
movement for `inventory-db` follows the Postgres-via-DMS pattern in
[`docs/decisions/data-migration-patterns.md`](../../docs/decisions/data-migration-patterns.md).
At cutover, the `inventory-db` StatefulSet on EKS is bootstrapped from a
DMS-replicated RDS snapshot, *not* from the source PV.
