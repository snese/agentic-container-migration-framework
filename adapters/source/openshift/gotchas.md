# OpenShift — Known Gotchas

## SecurityContextConstraints (SCC) ≠ PodSecurity

OpenShift uses SCCs, which are stricter and structurally different from upstream PodSecurity
Standards (PSA). Every Project automatically gets `restricted-v2` SCC; many pods rely on
`anyuid` or custom SCCs to run.

**Detection:** `oc get scc -o name; oc get rolebinding -A -o json | jq '.items[] | select(.roleRef.name | startswith("system:openshift:scc:"))'`

**Migration impact:** On EKS, PSA admission has labels `restricted` / `baseline` / `privileged`
at namespace level. Map each Project's effective SCC → PSA label. Workloads relying on `anyuid`
typically fail under `restricted` PSA — they need to be rewritten to run as a non-root user with
explicit UID, or labelled to `baseline` namespace.

## ImageStream + BuildConfig (S2I) is a CI tool inside K8s

If the customer uses ImageStreams + BuildConfigs, they have an *in-cluster CI pipeline*. On EKS
this becomes:
- ImageStream → ECR repository
- BuildConfig (S2I) → CodeBuild project (or Tekton / Jenkins on EKS)
- Triggers (image-change, config-change) → ECR EventBridge rules / pipeline triggers

Most teams use the migration as an opportunity to move CI out of the cluster entirely.

## Routes have features Ingress doesn't

OpenShift Routes support:
- **TLS re-encrypt** (terminate at edge, re-encrypt to backend) — needs ALB listener cert + target group with HTTPS health check
- **Path-based AND host-based routing in one Route** — needs two Ingress objects on EKS
- **Wildcard routes** (`*.apps.cluster.example.com`) — ALB supports this, but DNS must be redesigned

Don't promise drop-in. Each Route → typically 1 Ingress + 1 ACM certificate + 1 ALB listener rule.

## OLM Subscriptions can hide huge dependencies

A `Subscription` is one line of YAML. Behind it can be:
- Strimzi (Kafka with persistent volumes)
- Crunchy Postgres Operator (with backups, replicas, PITR)
- Red Hat Single Sign-On (Keycloak)
- Red Hat AMQ (ActiveMQ Artemis)

Each of these is a multi-week migration on its own. Treat the OLM list as a *scope multiplier*,
not an inventory.

## MachineConfig changes the OS

`MachineConfig` lets customers ship arbitrary `systemd` units, kernel args, certificates, and
files to nodes. On EKS this becomes either:
- Custom AMI (build it via Image Builder + EKS-optimized AMI as base)
- Bottlerocket settings (if it fits the Bottlerocket setting model)
- userdata script in the Launch Template

Anything beyond stock RHCOS is a per-customer redesign. 🚧 Bring this to architecture review.

## Cluster Operators ≠ workloads

`oc get clusteroperator` shows the OpenShift control-plane operators (kube-apiserver, ingress,
authentication, etc.). These are part of OCP, not customer workloads. On EKS, AWS manages the
equivalent. **Do not add ClusterOperators to the migration scope** — confusion happens.

## ROSA-specific

If the source is **ROSA** (Red Hat OpenShift on AWS), the underlying cloud is already AWS.
"Migrating" usually means switching from the ROSA control-plane SKU to plain EKS — networking and
compute mostly stay. This is a much smaller migration than ROSA-from-scratch and should be scoped
differently.

## 🚧 v0.8: Not yet covered (true SME items)

- KubeVirt → EC2 / Nitro System workload extraction (handled as `blocker` rating only — actual extraction is a separate workstream)
- HyperShift hosted-cluster cutover patterns
- Custom OAuth IdP (LDAP, custom OIDC) → Cognito / IAM Identity Center mapping
- ODF (Ceph) → AWS storage tiering decision tree (block/file/object split)
- Operators not in the rating table — `unknown` items must be SME-triaged per engagement
