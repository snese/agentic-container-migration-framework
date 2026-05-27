#!/usr/bin/env python3
"""
scripts/discovery/_gen-fixtures.py

Dev tool: regenerate the 12 platform fixtures
(adapters/source/<platform>/fixtures/<platform>-{small,realistic}.json).

Customers do NOT run this — they consume the committed JSON. This file is
kept in the repo so anyone can rebuild fixtures if the schema evolves.

Run:  python3 scripts/discovery/_gen-fixtures.py
"""
from __future__ import annotations
import json
import pathlib
import datetime as _dt

ROOT = pathlib.Path(__file__).resolve().parents[2]
NOW = _dt.datetime.now(tz=_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
SCHEMA_VERSION = "1.0.0"

PLATFORMS = [
    "anthos-vmware",
    "anthos-gcp",
    "anthos-baremetal",
    "openshift",
    "rancher",
    "vanilla-k8s",
]


def cluster(name: str, version: str, platform: str, location: str, extras: dict | None = None) -> dict:
    base = {
        "name": name,
        "version": version,
        "platform": platform,
        "location": location,
        "control_plane": {"ha": True},
        "node_pools": [
            {"name": "default", "count": 3, "k8s_version": version, "os_image": "Ubuntu 22.04"}
        ],
    }
    if extras:
        base.update(extras)
    return base


def workload(cluster_name: str, ns: str, kind: str, name: str, *, classification: str,
             replicas: int = 2, image: str = "registry.example.com/app:1.0",
             stateful_volume: bool = False) -> dict:
    wl: dict = {
        "cluster": cluster_name,
        "namespace": ns,
        "kind": kind,
        "name": name,
        "classification": classification,
        "replicas": {"desired": replicas, "current": replicas},
        "containers": [
            {"name": "main", "image": image,
             "resources": {"requests": {"cpu": "100m", "memory": "256Mi"},
                           "limits": {"cpu": "500m", "memory": "512Mi"}}}
        ],
        "labels": {"app": name},
        "volumes": [],
    }
    if stateful_volume:
        wl["volumes"] = [{"name": f"{name}-data"}]
    return wl


def make_small(platform: str) -> dict:
    """One cluster, 10 services — monolithic-ish e-commerce app."""
    cname = f"{platform}-small-cluster-1"
    workloads: list[dict] = []
    namespaces = ["default", "shop"]
    services = [
        ("frontend",       "Deployment",  "stateless", 3, "nginx:1.27"),
        ("api-gateway",    "Deployment",  "stateless", 2, "registry.example.com/api-gw:2.4"),
        ("catalog",        "Deployment",  "stateless", 2, "registry.example.com/catalog:1.8"),
        ("orders",         "Deployment",  "stateless", 2, "registry.example.com/orders:1.5"),
        ("payments",       "Deployment",  "stateless", 2, "registry.example.com/payments:1.2"),
        ("postgres",       "StatefulSet", "stateful",  1, "postgres:16"),
        ("redis",          "StatefulSet", "stateful",  1, "redis:7"),
        ("cron-pricing",   "CronJob",     "batch",     1, "registry.example.com/pricing:1.0"),
        ("log-shipper",    "DaemonSet",   "system",    1, "fluent/fluent-bit:3.1"),
        ("backup-job",     "Job",         "batch",     1, "registry.example.com/backup:1.0"),
    ]
    for name, kind, cls, reps, img in services:
        ns = "shop" if cls in ("stateless", "stateful") and name != "log-shipper" else "default"
        workloads.append(workload(cname, ns, kind, name,
                                  classification=cls, replicas=reps, image=img,
                                  stateful_volume=(cls == "stateful")))

    bundle = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": NOW,
        "generated_by": "self-export-script",
        "source_platform": platform,
        "scope": {
            "clusters": [cname],
            "namespaces_included": namespaces,
            "namespaces_excluded": ["kube-system"],
        },
        "clusters": [cluster(cname, "v1.30.4", platform, _location(platform))],
        "workloads": workloads,
        "networking": {
            "services_total": 10,
            "services_by_type": {"ClusterIP": 8, "LoadBalancer": 2},
            "ingress_total": 1,
            "network_policies_total": 0,
        },
        "storage": {
            "storage_classes": _storage_classes(platform),
            "pv_count": 2,
            "pvc_count": 2,
            "provisioners_in_use": _provisioners(platform),
        },
        "identity": {
            "service_accounts_total": 12,
            "cluster_role_bindings_total": 8,
        },
        "external_dependencies": [
            {"host": "smtp.sendgrid.net", "port": 587, "protocol": "tcp",
             "used_by": ["payments"]},
            {"host": "stripe.com", "port": 443, "protocol": "https",
             "used_by": ["payments"]},
        ],
        "crds": _baseline_crds(platform),
        "skipped": [],
        "warnings": [
            f"fixture: {platform}-small — synthetic data, not derived from a live cluster",
        ],
    }
    _platform_overlay(bundle, platform, size="small")
    return bundle


def make_realistic(platform: str) -> dict:
    """Two clusters, 50+ services, mesh + stateful + custom CRDs."""
    clusters = [
        f"{platform}-prod-east",
        f"{platform}-prod-west",
    ]
    workloads: list[dict] = []
    # 25 services per cluster
    namespaces = ["frontend", "backend", "data", "platform", "observability"]
    sample_services = [
        # (name, kind, classification, replicas, image)
        ("web",          "Deployment", "stateless", 5, "nginx:1.27"),
        ("auth",         "Deployment", "stateless", 4, "registry.example.com/auth:3.1"),
        ("checkout",     "Deployment", "stateless", 6, "registry.example.com/checkout:2.0"),
        ("cart",         "Deployment", "stateless", 4, "registry.example.com/cart:1.4"),
        ("recommend",    "Deployment", "stateless", 3, "registry.example.com/recommend:0.9"),
        ("search",       "Deployment", "stateless", 4, "registry.example.com/search:2.2"),
        ("ml-inference", "Deployment", "stateless", 2, "registry.example.com/ml-infer:0.5"),
        ("kafka",        "StatefulSet","stateful", 3, "confluentinc/cp-kafka:7.6.1"),
        ("zookeeper",    "StatefulSet","stateful", 3, "confluentinc/cp-zookeeper:7.6.1"),
        ("postgres",     "StatefulSet","stateful", 3, "postgres:16"),
        ("redis",        "StatefulSet","stateful", 3, "redis:7"),
        ("elasticsearch","StatefulSet","stateful", 3, "elasticsearch:8.13"),
        ("nightly-etl",  "CronJob",    "batch",    1, "registry.example.com/etl:1.6"),
        ("warmer",       "CronJob",    "batch",    1, "registry.example.com/warmer:1.0"),
        ("backup",       "Job",        "batch",    1, "registry.example.com/backup:1.0"),
        ("fluent-bit",   "DaemonSet",  "system",   1, "fluent/fluent-bit:3.1"),
        ("node-exporter","DaemonSet",  "system",   1, "prom/node-exporter:1.8"),
        ("calico-node",  "DaemonSet",  "system",   1, "calico/node:v3.27"),
        ("admin-ui",     "Deployment", "stateless", 1, "registry.example.com/admin:1.0"),
        ("billing",      "Deployment", "stateless", 3, "registry.example.com/billing:2.7"),
        ("notify",       "Deployment", "stateless", 2, "registry.example.com/notify:1.2"),
        ("audit-log",    "Deployment", "stateless", 2, "registry.example.com/audit:1.0"),
        ("prometheus",   "StatefulSet","stateful", 1, "prom/prometheus:v2.52"),
        ("grafana",      "Deployment", "stateless", 1, "grafana/grafana:11.0"),
        ("loki",         "StatefulSet","stateful", 2, "grafana/loki:3.0"),
    ]
    for c in clusters:
        for i, (name, kind, cls, reps, img) in enumerate(sample_services):
            ns = namespaces[i % len(namespaces)]
            workloads.append(workload(c, ns, kind, name,
                                      classification=cls, replicas=reps, image=img,
                                      stateful_volume=(cls == "stateful")))

    bundle = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": NOW,
        "generated_by": "self-export-script",
        "source_platform": platform,
        "scope": {
            "clusters": clusters,
            "namespaces_included": namespaces,
            "namespaces_excluded": ["kube-system", "kube-public"],
        },
        "clusters": [
            cluster(clusters[0], "v1.30.4", platform, _location(platform)),
            cluster(clusters[1], "v1.30.4", platform, _location(platform)),
        ],
        "workloads": workloads,
        "networking": {
            "services_total": 60,
            "services_by_type": {"ClusterIP": 52, "LoadBalancer": 6, "NodePort": 2},
            "ingress_total": 8,
            "network_policies_total": 12,
            "service_mesh": {"engine": "istio", "version": "1.22"},
        },
        "storage": {
            "storage_classes": _storage_classes(platform),
            "pv_count": 18,
            "pvc_count": 18,
            "provisioners_in_use": _provisioners(platform),
        },
        "identity": {
            "service_accounts_total": 65,
            "cluster_role_bindings_total": 27,
            "workload_identity_enabled": platform in ("anthos-gcp", "anthos-vmware"),
        },
        "external_dependencies": [
            {"host": "smtp.sendgrid.net", "port": 587, "protocol": "tcp",
             "used_by": ["notify", "billing"]},
            {"host": "stripe.com", "port": 443, "protocol": "https",
             "used_by": ["checkout", "billing"]},
            {"host": "snowflake-prod.us-east-1.aws", "port": 443, "protocol": "https",
             "used_by": ["nightly-etl"]},
            {"host": "datadoghq.com", "port": 443, "protocol": "https",
             "used_by": ["fluent-bit"]},
        ],
        "crds": _baseline_crds(platform) + _extended_crds(platform),
        "skipped": [],
        "warnings": [
            f"fixture: {platform}-realistic — synthetic data, two clusters, mesh + stateful + custom CRDs",
        ],
    }
    _platform_overlay(bundle, platform, size="realistic")
    return bundle


def _location(platform: str) -> str:
    return {
        "anthos-vmware":    "on-prem-vmware-dc1",
        "anthos-gcp":       "us-central1",
        "anthos-baremetal": "on-prem-baremetal-rack1",
        "openshift":        "on-prem-openshift-dc1",
        "rancher":          "on-prem-rancher-dc1",
        "vanilla-k8s":      "self-managed-dc1",
    }[platform]


def _storage_classes(platform: str) -> list[dict]:
    return {
        "anthos-vmware":    [{"name": "vsphere-csi", "provisioner": "csi.vsphere.vmware.com"}],
        "anthos-gcp":       [{"name": "standard-rwo", "provisioner": "pd.csi.storage.gke.io"},
                             {"name": "premium-rwo", "provisioner": "pd.csi.storage.gke.io"}],
        "anthos-baremetal": [{"name": "local-path", "provisioner": "rancher.io/local-path"}],
        "openshift":        [{"name": "ocs-storagecluster-ceph-rbd", "provisioner": "openshift-storage.rbd.csi.ceph.com"}],
        "rancher":          [{"name": "longhorn", "provisioner": "driver.longhorn.io"}],
        "vanilla-k8s":      [{"name": "local-path", "provisioner": "rancher.io/local-path"}],
    }[platform]


def _provisioners(platform: str) -> list[str]:
    return [sc["provisioner"] for sc in _storage_classes(platform)]


def _baseline_crds(platform: str) -> list[dict]:
    return [
        {"name": "certificates.cert-manager.io",     "group": "cert-manager.io",     "versions": ["v1"], "scope": "Namespaced"},
        {"name": "issuers.cert-manager.io",          "group": "cert-manager.io",     "versions": ["v1"], "scope": "Namespaced"},
        {"name": "servicemonitors.monitoring.coreos.com", "group": "monitoring.coreos.com", "versions": ["v1"], "scope": "Namespaced"},
    ]


def _extended_crds(platform: str) -> list[dict]:
    common = [
        {"name": "virtualservices.networking.istio.io",  "group": "networking.istio.io", "versions": ["v1beta1"], "scope": "Namespaced"},
        {"name": "destinationrules.networking.istio.io", "group": "networking.istio.io", "versions": ["v1beta1"], "scope": "Namespaced"},
        {"name": "gateways.networking.istio.io",         "group": "networking.istio.io", "versions": ["v1beta1"], "scope": "Namespaced"},
        {"name": "kafkas.kafka.strimzi.io",              "group": "kafka.strimzi.io",    "versions": ["v1beta2"], "scope": "Namespaced"},
        {"name": "applications.argoproj.io",             "group": "argoproj.io",         "versions": ["v1alpha1"], "scope": "Namespaced"},
    ]
    extra = {
        "anthos-vmware":    [{"name": "rootsyncs.configsync.gke.io", "group": "configsync.gke.io", "versions": ["v1beta1"], "scope": "Namespaced"}],
        "anthos-gcp":       [{"name": "rootsyncs.configsync.gke.io", "group": "configsync.gke.io", "versions": ["v1beta1"], "scope": "Namespaced"}],
        "anthos-baremetal": [{"name": "rootsyncs.configsync.gke.io", "group": "configsync.gke.io", "versions": ["v1beta1"], "scope": "Namespaced"}],
        "openshift":        [{"name": "subscriptions.operators.coreos.com",   "group": "operators.coreos.com", "versions": ["v1alpha1"], "scope": "Namespaced"},
                             {"name": "operatorgroups.operators.coreos.com",  "group": "operators.coreos.com", "versions": ["v1"],       "scope": "Namespaced"},
                             {"name": "routes.route.openshift.io",            "group": "route.openshift.io",   "versions": ["v1"],       "scope": "Namespaced"}],
        "rancher":          [{"name": "bundles.fleet.cattle.io",     "group": "fleet.cattle.io",      "versions": ["v1alpha1"], "scope": "Namespaced"},
                             {"name": "clusters.fleet.cattle.io",    "group": "fleet.cattle.io",      "versions": ["v1alpha1"], "scope": "Namespaced"}],
        "vanilla-k8s":      [],
    }[platform]
    return common + extra


def _platform_overlay(bundle: dict, platform: str, *, size: str) -> None:
    """Inject platform-specific top-level metadata blocks."""
    if platform == "anthos-vmware":
        bundle["vmware"] = {"hosts_count": 6, "datastores_count": 3,
                            "vcenter_version": "8.0u2"}
        bundle["clusters"][0]["anthos"] = {"version": "1.16.5",
                                           "service_mesh": {"istio_version": "1.22"}}
        if size == "realistic":
            bundle["clusters"][1]["anthos"] = {"version": "1.16.5",
                                               "service_mesh": {"istio_version": "1.22"}}
    elif platform == "anthos-gcp":
        bundle["clusters"][0]["anthos"] = {"version": "1.30.4-gke.1147",
                                           "release_channel": "REGULAR"}
        if size == "realistic":
            bundle["clusters"][1]["anthos"] = {"version": "1.30.4-gke.1147",
                                               "release_channel": "REGULAR"}
    elif platform == "anthos-baremetal":
        bundle["clusters"][0]["anthos"] = {"version": "1.16.4",
                                           "baremetal_cluster_count": 1}
        if size == "realistic":
            bundle["clusters"][1]["anthos"] = {"version": "1.16.4",
                                               "baremetal_cluster_count": 1}
    elif platform == "openshift":
        for c in bundle["clusters"]:
            c["openshift"] = {"current_version": "4.15.10", "channel": "stable-4.15"}
        bundle["openshift"] = {
            "image_streams_total": 24,
            "build_configs_total": 11 if size == "realistic" else 3,
            "subscriptions": [
                {"namespace": "openshift-operators", "name": "cert-manager-operator",
                 "package": "cert-manager-operator", "channel": "stable-v1", "source": "redhat-operators"},
                {"namespace": "openshift-operators", "name": "openshift-pipelines-operator-rh",
                 "package": "openshift-pipelines-operator-rh", "channel": "latest", "source": "redhat-operators"},
            ],
            "machine_config_pools": [
                {"name": "master", "ready": 3, "total": 3},
                {"name": "worker", "ready": 6 if size == "realistic" else 3,
                 "total": 6 if size == "realistic" else 3},
            ],
        }
    elif platform == "rancher":
        for c in bundle["clusters"]:
            c["rancher"] = {"distribution": "rke2",
                            "fleet_clusters_total": 2 if size == "realistic" else 1,
                            "fleet_bundles_total": 18 if size == "realistic" else 4}
    elif platform == "vanilla-k8s":
        for c in bundle["clusters"]:
            c["bootstrap"] = "kubeadm"
        bundle["networking"]["cni"] = "calico"
        bundle["networking"]["ingress_controller"] = "ingress-nginx"


def main() -> None:
    for platform in PLATFORMS:
        out_dir = ROOT / "adapters" / "source" / platform / "fixtures"
        out_dir.mkdir(parents=True, exist_ok=True)
        for size, builder in (("small", make_small), ("realistic", make_realistic)):
            path = out_dir / f"{platform}-{size}.json"
            bundle = builder(platform)
            with path.open("w", encoding="utf-8") as fh:
                json.dump(bundle, fh, indent=2, sort_keys=False)
                fh.write("\n")
            print(f"  wrote {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
