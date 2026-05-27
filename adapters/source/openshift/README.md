# Source Adapter: OpenShift (OCP 4.x)

**Status:** 🚧 v0.7-rc — Routes / ImageStreams / OLM Subscriptions covered. Operator-to-AWS mapping rated `easy / hard / blocker` is partial; needs SME review for stateful operators (Strimzi, postgres-operator, KubeVirt, etc.).

## Scope

Red Hat OpenShift Container Platform 4.x — both customer-managed (UPI/IPI on bare-metal, vSphere,
or AWS) and Red Hat-managed (ROSA, ARO). This adapter targets workload + cluster discovery,
*not* the OpenShift control-plane installation method.

## What this adapter provides

- Discovery prompt: [`prompts/discovery/openshift.prompt.md`](../../../prompts/discovery/openshift.prompt.md)
- Self-export script: [`scripts/discovery/openshift-export.sh`](../../../scripts/discovery/openshift-export.sh)
- Feature mapping: [`mapping.md`](mapping.md)
- Known gotchas: [`gotchas.md`](gotchas.md)
- Fixtures (small + realistic) for offline testing

## Distinguishing signals

| Signal | What we check |
|---|---|
| OpenShift control plane | `clusterversion` resource |
| Routes (Ingress dialect) | `route.openshift.io/v1` API group |
| ImageStreams + BuildConfigs | S2I usage signal |
| OLM Subscriptions | Installed Operators (`operators.coreos.com`) |
| MachineConfigPools | Cluster-as-code declarative node config |
| SecurityContextConstraints (SCCs) | OpenShift's stricter PodSecurity model |

## Migration target priority

1. **EKS** — primary target. Most OpenShift workloads carry K8s-native dependencies (CRDs, operators)
   that are easier to translate to EKS than to ECS.
2. **ROSA → EKS** is also a valid path if the customer is already on AWS but wants out of OpenShift's
   licensing model.
3. **ECS Fargate** — viable for portfolios that are predominantly stateless 12-factor apps.

See [`mapping.md`](mapping.md) for the feature matrix and [`gotchas.md`](gotchas.md) for the
running list of known surprises.
