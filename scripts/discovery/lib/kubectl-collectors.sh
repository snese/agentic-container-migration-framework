#!/usr/bin/env bash
# scripts/discovery/lib/kubectl-collectors.sh
#
# Source-agnostic kubectl-based collectors. These build the cluster /
# workload / networking / storage / identity sections of a discovery
# bundle in a way that works against any conformant Kubernetes cluster
# (GKE, GKE Enterprise, AKS, OpenShift, Rancher, vanilla K8s).
#
# Per-adapter scripts source this file and may overwrite individual
# sections (e.g. the GKE Enterprise adapter overwrites `clusters` to
# include Anthos / ASM metadata).
#
# Public functions:
#   acmf::k8s::collect_workloads      NS_LIST CLUSTER_NAME -> echoes JSON
#   acmf::k8s::collect_networking     NS_LIST CLUSTER_NAME -> echoes JSON
#   acmf::k8s::collect_storage        NS_LIST CLUSTER_NAME -> echoes JSON
#   acmf::k8s::collect_identity       NS_LIST CLUSTER_NAME -> echoes JSON
#   acmf::k8s::collect_crds                                 -> echoes JSON

# shellcheck disable=SC2034

acmf::k8s::collect_workloads() {
  local ns_list="$1" cluster_name="$2"
  local out="[]" ns kind raw classification add
  for ns in ${ns_list}; do
    for kind in Deployment StatefulSet DaemonSet Job CronJob; do
      raw="$(kubectl -n "$ns" get "$kind" -o json 2>/dev/null || echo '{"items":[]}')"
      classification="stateless"
      case "$kind" in
        StatefulSet) classification="stateful" ;;
        Job|CronJob) classification="batch" ;;
        DaemonSet)   classification="system" ;;
      esac
      add="$(echo "$raw" | jq --arg c "$cluster_name" --arg ns "$ns" --arg k "$kind" --arg cls "$classification" '
        [ .items[] | {
          cluster: $c, namespace: $ns, kind: $k, name: .metadata.name, classification: $cls,
          replicas: { desired: (.spec.replicas // null), current: (.status.replicas // .status.currentReplicas // null) },
          images: [ (.spec.template.spec.containers // [])[].image ],
          resources: {
            requests: ( (.spec.template.spec.containers // [])[0].resources.requests // {} ),
            limits:   ( (.spec.template.spec.containers // [])[0].resources.limits   // {} )
          },
          env_summary: [ (.spec.template.spec.containers // [])[].env[]? | (.name + "=" + (if .valueFrom then "<ref:" + ((.valueFrom|keys[0])|tostring) + ">" else "<REDACTED>" end)) ],
          volume_mounts: [ (.spec.template.spec.containers // [])[].volumeMounts[]? | { name: .name, mount_path: .mountPath, read_only: (.readOnly // false) } ]
        } ]')"
      out="$(jq -n --argjson a "$out" --argjson b "$add" '$a + $b')"
    done
  done
  echo "$out"
}

acmf::k8s::collect_networking() {
  local ns_list="$1" cluster_name="$2"
  local svcs="[]" ing="[]" ns add s i
  for ns in ${ns_list}; do
    s="$(kubectl -n "$ns" get svc -o json 2>/dev/null || echo '{"items":[]}')"
    add="$(echo "$s" | jq --arg c "$cluster_name" --arg ns "$ns" '
      [ .items[] | {
        cluster:$c, namespace:$ns, name:.metadata.name, type:.spec.type,
        selectors:(.spec.selector // {}),
        external_ips:(.spec.externalIPs // []),
        ports:[ (.spec.ports // [])[] | { name:(.name // ""), port:.port, target_port:(.targetPort|tostring), protocol:(.protocol // "TCP") } ]
      } ]')"
    svcs="$(jq -n --argjson a "$svcs" --argjson b "$add" '$a + $b')"

    i="$(kubectl -n "$ns" get ingress -o json 2>/dev/null || echo '{"items":[]}')"
    add="$(echo "$i" | jq --arg c "$cluster_name" --arg ns "$ns" '
      [ .items[] | {
        cluster:$c, namespace:$ns, name:.metadata.name, kind:"Ingress",
        hosts:[ (.spec.rules // [])[].host ],
        tls: ((.spec.tls // []) | length > 0)
      } ]')"
    ing="$(jq -n --argjson a "$ing" --argjson b "$add" '$a + $b')"
  done

  local np vs dr ap
  np="$(kubectl get networkpolicy -A -o json 2>/dev/null | jq '.items | length' || echo 0)"
  vs="$(kubectl get virtualservices.networking.istio.io -A -o json 2>/dev/null | jq '.items | length' || echo 0)"
  dr="$(kubectl get destinationrules.networking.istio.io -A -o json 2>/dev/null | jq '.items | length' || echo 0)"
  ap="$(kubectl get authorizationpolicies.security.istio.io -A -o json 2>/dev/null | jq '.items | length' || echo 0)"

  jq -n \
    --argjson svc "$svcs" --argjson ing "$ing" \
    --argjson np "${np:-0}" --argjson vs "${vs:-0}" \
    --argjson dr "${dr:-0}" --argjson ap "${ap:-0}" '
    { services:$svc, ingress:$ing,
      network_policies: { count:$np, samples:[] },
      service_mesh: {
        virtual_services:{ count:$vs, samples:[] },
        destination_rules:{ count:$dr, samples:[] },
        authorization_policies:{ count:$ap, samples:[] }
      } }'
}

acmf::k8s::collect_storage() {
  local ns_list="$1" cluster_name="$2"
  local sc pv pvc add ns
  sc="$(kubectl get sc -o json 2>/dev/null | jq '[ .items[] | {
    name:.metadata.name, provisioner:.provisioner, parameters:(.parameters // {}),
    reclaim_policy:(.reclaimPolicy // "Delete"), volume_binding_mode:(.volumeBindingMode // "Immediate")
  } ]' || echo '[]')"
  pv="$(kubectl get pv -o json 2>/dev/null | jq '[ .items[] | {
    name:.metadata.name, size:.spec.capacity.storage, reclaim_policy:.spec.persistentVolumeReclaimPolicy,
    access_modes:.spec.accessModes,
    source_type: ( if .spec.csi then .spec.csi.driver else (.spec | keys[] | select(. != "capacity" and . != "accessModes" and . != "persistentVolumeReclaimPolicy" and . != "storageClassName" and . != "claimRef" and . != "volumeMode" and . != "mountOptions" and . != "nodeAffinity")) end ),
    storage_class:(.spec.storageClassName // null)
  } ]' || echo '[]')"
  pvc="[]"
  for ns in ${ns_list}; do
    add="$(kubectl -n "$ns" get pvc -o json 2>/dev/null | jq --arg c "$cluster_name" --arg ns "$ns" '[ .items[] | {
      cluster:$c, namespace:$ns, name:.metadata.name, size:.spec.resources.requests.storage,
      linked_pv:(.spec.volumeName // null), mounted_by:[]
    } ]' || echo '[]')"
    pvc="$(jq -n --argjson a "$pvc" --argjson b "$add" '$a + $b')"
  done
  jq -n --argjson sc "$sc" --argjson pv "$pv" --argjson pvc "$pvc" \
    '{ storage_classes:$sc, persistent_volumes:$pv, persistent_volume_claims:$pvc }'
}

# Default identity collector. Per-adapter scripts may override with
# platform-specific workload-identity translations:
#   - GKE / GKE Enterprise: `iam.gke.io/gcp-service-account` -> GSA
#   - AKS: `azure.workload.identity/client-id` -> Azure AD app
#   - OpenShift: ServiceAccount -> OAuth client / SCC bindings
#   - Rancher: ServiceAccount -> Rancher project role-bindings
acmf::k8s::collect_identity() {
  local ns_list="$1" cluster_name="$2"
  local sa_total wi_json crb add ns
  sa_total="$(kubectl get sa -A -o json 2>/dev/null | jq '.items | length' || echo 0)"
  wi_json="[]"
  for ns in ${ns_list}; do
    add="$(kubectl -n "$ns" get sa -o json 2>/dev/null | jq --arg c "$cluster_name" --arg ns "$ns" '[
      .items[] | select(.metadata.annotations["iam.gke.io/gcp-service-account"]) | {
        cluster:$c, namespace:$ns, k8s_service_account:.metadata.name,
        external_identity:("gsa:" + .metadata.annotations["iam.gke.io/gcp-service-account"])
      } ]' || echo '[]')"
    wi_json="$(jq -n --argjson a "$wi_json" --argjson b "$add" '$a + $b')"
  done
  crb="$(kubectl get clusterrolebindings -o json 2>/dev/null | jq --arg c "$cluster_name" '[ .items[] | {
    cluster:$c, name:.metadata.name, role_ref:.roleRef.name,
    subjects:[ (.subjects // [])[] | { kind:.kind, name:.name, namespace:(.namespace // "") } ]
  } ]' || echo '[]')"
  jq -n --argjson t "${sa_total:-0}" --argjson crb "$crb" --argjson wi "$wi_json" \
    '{ service_accounts:{ total_count:$t, with_non_default_tokens:[] }, cluster_role_bindings:$crb, workload_identity_bindings:$wi }'
}

acmf::k8s::collect_crds() {
  local known='cert-manager|external-dns|prometheus|grafana|argo|flux|istio|knative|kyverno|gatekeeper|kueue|crossplane'
  kubectl get crd -o json 2>/dev/null | jq --arg known "$known" '[ .items[] | {
    group:.spec.group,
    version:(.spec.versions[0].name // "v1"),
    kind:.spec.names.kind,
    scope:.spec.scope,
    known_operator: ( if (.spec.group | test($known; "i")) then (.spec.group | split(".")[0]) else null end ),
    needs_human_review: ( (.spec.group | test($known; "i")) | not )
  } ]' || echo '[]'
}
