# Vanilla K8s → AWS Feature Mapping

| Vanilla K8s Feature | AWS Equivalent (EKS) | AWS Equivalent (ECS) | Migration Notes |
|---|---|---|---|
| Self-managed control plane | EKS managed control plane | ECS managed control plane | Big win — drop the etcd / kube-apiserver babysitting |
| `kubeadm` | (no equivalent — EKS is managed) | — | Cluster-creation tooling disappears |
| Calico (CNI) | Calico on EKS / VPC CNI | (n/a) | Calico is supported as EKS CNI; or migrate to AWS VPC CNI |
| Cilium (CNI) | Cilium on EKS | (n/a) | Cilium is community-supported on EKS |
| Flannel | VPC CNI | (n/a) | Flannel rare on AWS; usually migrate to VPC CNI |
| ingress-nginx | ALB Controller / ingress-nginx on EKS | ALB | Either keep ingress-nginx or migrate to AWS-native ALB Controller |
| Traefik | Traefik on EKS / ALB Controller | ALB | Same trade-off |
| MetalLB / kube-vip | AWS Load Balancer Controller | NLB / ALB | `Service: LoadBalancer` becomes managed |
| `local-path` provisioner | EBS gp3 / EFS | (n/a) | RWO → EBS, RWX → EFS |
| Rook-Ceph / OpenEBS | EBS / EFS / FSx | EBS / EFS | Cluster-internal storage operator → managed AWS storage |
| etcd backups | EKS managed (no action) | (n/a) | EKS handles control-plane data |
| Custom node images | EKS-optimized AMI / Bottlerocket / custom AMI | — | Rebuild as Image Builder pipeline |
| Cluster Autoscaler | Karpenter / Cluster Autoscaler on EKS | ECS service auto scaling | Karpenter is the modern choice on EKS |
| Manual cert-manager | cert-manager on EKS / ACM | ACM | Letsencrypt → ACM is the typical move |
| External-DNS | External-DNS on EKS (with Route 53) | Route 53 directly | external-dns Route53 plugin works out of the box |
| Prometheus + Grafana | AMP + AMG / self-managed Prometheus | CloudWatch Container Insights | AMP/AMG for like-for-like managed |
| Loki | Loki on EKS / CloudWatch Logs / OpenSearch | CloudWatch | Customer choice |

## Notes

- **kops on AWS:** if the customer is already using kops on AWS, "migration"
  is mostly cluster re-creation on EKS + workload move. The networking is
  already AWS-native.
- **Talos Linux:** Talos's API-only OS is unique. EKS uses Bottlerocket /
  Amazon Linux. Custom Talos modifications (Linux kernel modules, sysctl
  tuning) need to be replicated as Bottlerocket settings or a custom AMI.
- **Cluster API (CAPI):** if customer manages clusters via CAPI, they have an
  IaC discipline already. CAPI for AWS (`cluster-api-provider-aws`) can
  manage EKS clusters; this can be a valid migration target if the customer
  wants to keep the same workflow.
