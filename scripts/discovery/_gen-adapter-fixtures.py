#!/usr/bin/env python3
"""
Generate adapter fixtures for the new platform adapters by adapting main's
canonical example bundle. Each fixture is a small, realistic discovery bundle
that validates against schemas/discovery-bundle.schema.json.

NOT shipped — used once at adapter-port time. Output:
  adapters/source/<platform>/fixtures/<platform>-small.json

Run from repo root:
  python3 scripts/discovery/_gen-adapter-fixtures.py
"""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SCHEMA = json.loads((ROOT / "schemas/discovery-bundle.schema.json").read_text())

try:
    import jsonschema  # type: ignore
except ImportError:
    print("ERROR: python3-jsonschema required", file=sys.stderr)
    sys.exit(2)


def base_bundle(generated_by: str) -> dict:
    """Return a schema-valid skeleton matching main's example structure."""
    return {
        "schema_version": "0.2.0",
        "generated_at": "2026-06-01T00:00:00Z",
        "generated_by": generated_by,
        "scope": {
            "clusters": [],
            "namespaces_included": ["app-a"],
            "namespaces_excluded": ["kube-system"],
        },
        "clusters": [],
        "workloads": [],
        "networking": {
            "services": [],
            "ingress": [],
            "network_policies": {"count": 0, "samples": []},
            "service_mesh": {
                "virtual_services": {"count": 0, "samples": []},
                "destination_rules": {"count": 0, "samples": []},
                "authorization_policies": {"count": 0, "samples": []},
            },
        },
        "storage": {
            "storage_classes": [],
            "persistent_volumes": [],
            "persistent_volume_claims": [],
        },
        "identity": {
            "service_accounts": {"total_count": 0, "with_non_default_tokens": []},
            "cluster_role_bindings": [],
            "workload_identity_bindings": [],
        },
        "external_dependencies": [],
        "crds": [],
        "vmware": {
            "clusters": [],
            "hosts": [],
            "datastores": [],
            "vm_to_node_mapping": [],
        },
        "utilization": {
            "nodes": [],
            "pods": [],
            "summary": {
                "cluster_cpu_utilization_pct": 0.0,
                "cluster_memory_utilization_pct": 0.0,
                "over_provisioning_ratio": 0.0,
                "metrics_source": None,
            },
        },
        "traffic": {
            "pairs": [],
            "summary": {
                "east_west_bytes_per_sec": 0,
                "north_south_bytes_per_sec": 0,
                "total_service_pairs": 0,
                "telemetry_source": None,
            },
        },
        "skipped": [],
        "warnings": ["fixture: synthetic data, not derived from a live cluster"],
    }


def cluster_block(name: str, platform: str, location: str = "unknown", **extras) -> dict:
    block = {
        "name": name,
        "version": "v1.30.4",
        "location": location,
        "platform": platform,
        "control_plane": {"ha_mode": "unknown", "node_count": 3},
        "node_pools": [{"name": "default", "count": 3, "k8s_version": "v1.30.4"}],
        "anthos_version": None,
        "anthos_config_management_version": None,
        "service_mesh": {"enabled": False, "type": "none", "version": None},
    }
    block.update(extras)
    return block


def workload_block(cluster: str, ns: str, kind: str, name: str, classification: str) -> dict:
    return {
        "cluster": cluster,
        "namespace": ns,
        "kind": kind,
        "name": name,
        "classification": classification,
        "replicas": {"desired": 2, "current": 2},
        "images": [f"registry.example.com/{name}:1.0"],
        "resources": {
            "requests": {"cpu": "100m", "memory": "256Mi"},
            "limits": {"cpu": "500m", "memory": "512Mi"},
        },
        "env_summary": [],
        "volume_mounts": [],
    }


def fixture_openshift() -> dict:
    b = base_bundle("self-export-script")
    cluster = "ocp-small-cluster-1"
    b["scope"]["clusters"] = [cluster]
    b["scope"]["namespaces_included"] = ["shop"]
    b["clusters"] = [cluster_block(cluster, platform="other", location="on-prem-ocp-dc1",
                                   openshift={"current_version": "4.15.10", "channel": "stable-4.15"})]
    b["workloads"] = [
        workload_block(cluster, "shop", "Deployment", "frontend", "stateless"),
        workload_block(cluster, "shop", "StatefulSet", "postgres", "stateful"),
    ]
    b["openshift"] = {
        "is_rosa": False,
        "infrastructure_provider": "BareMetal",
        "image_streams_total": 24,
        "build_configs_total": 3,
        "openshift_routes_total": 4,
        "scc_total": 8,
        "subscriptions": [
            {
                "namespace": "openshift-operators",
                "name": "cert-manager-operator",
                "package": "cert-manager-operator",
                "channel": "stable-v1",
                "source": "redhat-operators",
                "migration_rating": {
                    "rating": "easy",
                    "aws_target": "AWS Certificate Manager (ACM) for public certs; cert-manager-on-EKS for in-cluster",
                    "rationale": "cert-manager runs on EKS unchanged; ACM replaces public-facing TLS issuance",
                },
            },
            {
                "namespace": "openshift-operators",
                "name": "ocs-operator",
                "package": "ocs-operator",
                "channel": "stable",
                "source": "redhat-operators",
                "migration_rating": {
                    "rating": "blocker",
                    "aws_target": "Amazon EBS / EFS / FSx for Lustre / Amazon S3 (per-tier redesign)",
                    "rationale": "Ceph/ODF is converged storage; AWS splits block/file/object — storage tiering must be redesigned",
                },
            },
        ],
        "machine_config_pools": [
            {"name": "master", "ready": 3, "total": 3},
            {"name": "worker", "ready": 3, "total": 3},
        ],
        "scc_usage": [
            {
                "scc": "anyuid",
                "namespace": "shop",
                "binding_name": "shop-anyuid",
                "subjects": [
                    {"kind": "ServiceAccount", "name": "default", "namespace": "shop"}
                ],
            }
        ],
    }
    b["warnings"] += [
        "OpenShift: 1 effective SCC binding(s) detected — each must map to PodSecurity Admission (PSA) label on EKS.",
    ]
    return b


def fixture_rancher() -> dict:
    b = base_bundle("self-export-script")
    cluster = "rancher-rke2-cluster-1"
    b["scope"]["clusters"] = [cluster]
    b["scope"]["namespaces_included"] = ["shop"]
    b["clusters"] = [cluster_block(cluster, platform="other", location="on-prem-rancher",
                                   rancher={
                                       "distribution": "rke2",
                                       "server_version": "v1.30.4+rke2r1",
                                       "is_management_cluster": True,
                                       "fleet_clusters_total": 4,
                                       "fleet_bundles_total": 12,
                                   })]
    b["workloads"] = [workload_block(cluster, "shop", "Deployment", "frontend", "stateless")]
    b["rancher"] = {
        "is_management_cluster": True,
        "downstream_clusters_total": 4,
    }
    b["warnings"] += [
        "Rancher: this is the management cluster — Fleet bundles and cluster templates are visible here.",
    ]
    return b


def fixture_vanilla_k8s() -> dict:
    b = base_bundle("self-export-script")
    cluster = "vanilla-kubeadm-cluster-1"
    b["scope"]["clusters"] = [cluster]
    b["scope"]["namespaces_included"] = ["app-a"]
    b["clusters"] = [cluster_block(cluster, platform="other", location="on-prem-dc",
                                   bootstrap="kubeadm",
                                   vanilla={
                                       "cni": "calico",
                                       "ingress_controller": "ingress-nginx",
                                       "os_images": [{"os_image": "Ubuntu 22.04", "count": 3}],
                                       "kubelet_versions": ["v1.30.4"],
                                       "kubelet_skew_detected": False,
                                       "admission_webhooks_total": 2,
                                       "admission_webhooks_validating": 1,
                                       "admission_webhooks_mutating": 1,
                                   })]
    b["workloads"] = [workload_block(cluster, "app-a", "Deployment", "web", "stateless")]
    b["vanilla"] = {"bootstrapper": "kubeadm"}
    b["warnings"] += [
        "Vanilla-k8s: 2 admission webhook(s) — each must be redeployed on EKS.",
    ]
    return b


def fixture_gke_enterprise_gcp() -> dict:
    b = base_bundle("self-export-script")
    cluster = "gke-enterprise-gcp-cluster-1"
    b["scope"]["clusters"] = [cluster]
    b["scope"]["namespaces_included"] = ["payments"]
    b["clusters"] = [cluster_block(cluster, platform="gcp", location="us-central1",
                                   service_mesh={"enabled": True, "type": "asm", "version": "1.20.2"},
                                   anthos={
                                       "release_channel": "STABLE",
                                       "workload_identity_pool": "proj.svc.id.goog",
                                       "config_connector": {
                                           "installed": True,
                                           "crd_count": 3,
                                           "managed_resource_kinds": ["StorageBucket", "PubSubTopic", "SQLInstance"],
                                       },
                                   })]
    b["workloads"] = [workload_block(cluster, "payments", "Deployment", "payment-api", "stateless")]
    b["identity"]["workload_identity_bindings"] = [
        {
            "cluster": cluster,
            "namespace": "payments",
            "k8s_service_account": "payment-api-sa",
            "external_identity": "gsa:payment-api@proj.iam.gserviceaccount.com",
        }
    ]
    b["warnings"] += [
        "GKE Enterprise on GCP: 1 Workload Identity binding(s) — each KSA→GSA pair must be rewritten as IRSA on EKS.",
        "GKE Enterprise on GCP: Config Connector (KCC) detected with 3 managed CRD kinds — translate to ACK or Terraform/CDK.",
    ]
    return b


def fixture_gke_enterprise_baremetal() -> dict:
    b = base_bundle("self-export-script")
    cluster = "gke-enterprise-bm-cluster-1"
    b["scope"]["clusters"] = [cluster]
    b["scope"]["namespaces_included"] = ["telco"]
    b["clusters"] = [cluster_block(cluster, platform="baremetal", location="on-prem-baremetal",
                                   anthos={
                                       "baremetal_cluster_count": 1,
                                       "baremetal_cluster_names": [cluster],
                                   })]
    b["workloads"] = [
        workload_block(cluster, "telco", "Deployment", "edge-gateway", "stateless"),
        workload_block(cluster, "telco", "DaemonSet", "sriov-cni", "system"),
    ]
    b["workloads_hardware_bound"] = [
        {
            "namespace": "telco",
            "name": "edge-gateway",
            "kind": "Deployment",
            "reasons": ["hostNetwork", "sriov"],
            "detail": "Detected: hostNetwork, sriov",
        }
    ]
    b["warnings"] += [
        "GKE Enterprise on Bare Metal: 1 hardware-bound workload(s) detected — each needs SME triage for AWS placement.",
    ]
    return b


def main():
    fixtures = {
        "openshift": fixture_openshift(),
        "rancher": fixture_rancher(),
        "vanilla-k8s": fixture_vanilla_k8s(),
        "gke-enterprise-gcp": fixture_gke_enterprise_gcp(),
        "gke-enterprise-baremetal": fixture_gke_enterprise_baremetal(),
    }
    failures = 0
    for platform, bundle in fixtures.items():
        try:
            jsonschema.validate(bundle, SCHEMA)
        except jsonschema.ValidationError as e:
            print(f"  ✗ {platform}: {e.message}", file=sys.stderr)
            failures += 1
            continue
        out = ROOT / f"adapters/source/{platform}/fixtures/{platform}-small.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(bundle, indent=2) + "\n")
        print(f"  ✓ {platform} → {out.relative_to(ROOT)}")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
