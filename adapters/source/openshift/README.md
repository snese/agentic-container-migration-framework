# Source Adapter: OpenShift (OCP 4.x)

**Status:** ✅ Phase 1 enrichment complete on main's `lib/` architecture.

The openshift-export.sh script collects OpenShift-specific signals on top of the
shared K8s core layer:

- **ClusterVersion** (`current_version`, `channel`) → `clusters[0].openshift`
- **Infrastructure / ROSA detection** → `openshift.{is_rosa, infrastructure_provider}`.
  When ROSA is detected, `clusters[0].platform` is set to `aws` (since ROSA is hosted on AWS).
- **Routes total** → `openshift.openshift_routes_total`
- **ImageStreams + BuildConfigs total** (S2I signal) → `openshift.{image_streams_total, build_configs_total}`
- **OLM Subscriptions with AWS migration rating** (easy / hard / blocker / unknown) → `openshift.subscriptions[]`
- **MachineConfigPool ready/total** → `openshift.machine_config_pools[]`
- **Effective SCC bindings per namespace** → `openshift.scc_usage[]`
- **SCC inventory size** → `openshift.scc_total`

Operators that aren't in the built-in rating table land as `unknown` and trigger
a single aggregated SME warning so they are visible without spamming the bundle.

## Scope

Red Hat OpenShift Container Platform 4.x — both customer-managed (UPI/IPI on
bare-metal, vSphere, or AWS) and Red Hat-managed (ROSA, ARO). This adapter
targets workload + cluster discovery, *not* the OpenShift control-plane
installation method.

## What this adapter provides

- Self-export script: [`scripts/discovery/openshift-export.sh`](../../../scripts/discovery/openshift-export.sh)
- Feature mapping (incl. Operator rating table): [`mapping.md`](mapping.md)
- Known gotchas: [`gotchas.md`](gotchas.md)
- Fixtures (small) for offline schema validation: [`fixtures/`](fixtures/)

## Distinguishing signals

| Signal | What we check |
|---|---|
| OpenShift control plane | `oc get clusterversion version` |
| ROSA | `oc get infrastructure cluster` → `platform=AWS` + `red-hat-managed` tag, or `controlPlaneTopology=External` |
| Routes (Ingress dialect) | `oc get route -A` |
| ImageStreams + BuildConfigs | `oc get imagestream,buildconfig -A` |
| OLM Subscriptions | `oc get subscription -A`; each rated `easy / hard / blocker / unknown` |
| MachineConfigPools | `oc get machineconfigpool` |
| SCCs | `oc get scc` + RoleBindings/ClusterRoleBindings to `system:openshift:scc:*` |

## Migration target priority

1. **EKS** — primary target. Most OpenShift workloads carry K8s-native
   dependencies (CRDs, operators) that translate to EKS more cleanly than to ECS.
2. **ROSA → EKS** — control-plane SKU swap; networking and IAM mostly stay.
   Re-scope accordingly when ROSA is detected.
3. **ECS** — viable for predominantly stateless 12-factor portfolios.

See [`mapping.md`](mapping.md) for the feature matrix and Operator rating table;
see [`gotchas.md`](gotchas.md) for the running list of known surprises.
