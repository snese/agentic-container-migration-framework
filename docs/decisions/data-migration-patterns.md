# Data Migration Patterns — Decision Matrix

> **Scope.** Decision matrix only. Pick the right pattern + tool for each
> data type; follow the linked AWS docs for setup. **Not** a step-by-step
> guide for DMS, Velero, or DataSync.

## 1. Decision Matrix

| Data type | Zero-downtime feasible? | Recommended pattern | AWS / OSS tool | AWS doc |
|---|---|---|---|---|
| Relational DB (Oracle, PostgreSQL, MySQL, SQL Server) | Yes | CDC replication, cutover when lag ≈ 0 | [AWS DMS][dms] with CDC; managed-target = RDS / Aurora | [DMS CDC ongoing replication][dms-cdc] |
| NoSQL (DynamoDB target) | Yes | Stream-based replication, dual-read during cutover | DMS (DynamoDB target) **or** app-level dual-write | [DMS DynamoDB target][dms-ddb] |
| K8s PV — block (RWO, vSphere CSI → EBS) | Mostly no | Snapshot + restore; quiesce app for the cutover window | [Velero][velero] with EBS plugin, or per-app dump/restore | [Velero docs][velero] · [EBS CSI on EKS][ebs-csi] |
| K8s PV — file (RWX, NFS / vSAN file → EFS) | Yes | Online file sync to EFS, switch mount at cutover | [AWS DataSync][datasync-overview] (NFS source → EFS) | [DataSync NFS → EFS][datasync-nfs-efs] |
| Object storage (GCS / on-prem S3-compatible → S3) | Yes | Bulk copy + delta sync, switch readers at cutover | [AWS DataSync][datasync-overview] **or** S3 Batch / `aws s3 sync` for one-shot | [DataSync to S3][datasync-s3] |
| Message queue (Kafka, RabbitMQ, Pub/Sub) | Yes | Dual-write from producers, drain old consumers, switch consumers | [MSK][msk] (Kafka), [Amazon MQ][amq] (RabbitMQ); pattern is app-side | [MSK migration][msk-migration] |
| Cache (Redis, Memcached) | Warm-up only | Re-seed from source of truth post-cutover; do not migrate cache state | [ElastiCache][elasticache] | [ElastiCache for Redis][elasticache] |
| Search index (Elasticsearch / OpenSearch) | Yes | Reindex from source of truth, dual-write for delta, cutover | [OpenSearch Service][opensearch]; reindex is app-side | [OpenSearch migration assistant][opensearch-mig] |
| Files inside container images (don't!) | n/a | Externalize to PV / S3 first, then migrate per row above | — | — |

Anti-patterns:
- ❌ Lift-and-shift Redis state with snapshot — caches are not source of truth.
- ❌ Velero across heterogeneous CSI drivers without a restore dry-run.
- ❌ DMS full-load only (no CDC) for a system with writes during migration.
- ❌ DataSync between regions without checking egress cost first.

## 2. Downtime Estimation Formula

Use this for the **cutover** window only — bulk copy time happens online.

```
T_cutover ≈ T_quiesce + T_final_sync + T_validate + T_dns_ttl + T_buffer

where
  T_quiesce      = time to stop writers / drain in-flight requests
  T_final_sync   = remaining_delta_bytes / effective_bandwidth_bytes_per_sec
  T_validate     = row-count / checksum / smoke-test time
  T_dns_ttl      = max DNS TTL on client-facing record (or LB drain time)
  T_buffer       = 25% safety margin
```

Patterns that drive each term:
- **DMS CDC:** `T_final_sync` ≈ replication lag at cutover (target: < 60 s
  before quiesce). Track [`CDCLatencyTarget`][dms-metrics].
- **DataSync (file/object):** `T_final_sync` ≈ delta scan + transfer; run a
  pre-cutover task to shrink the delta.
- **Velero (block PV):** `T_final_sync` = full snapshot+restore for the PV
  (no online delta). Plan `T_quiesce` to cover the whole restore.
- **Dual-write queues:** `T_final_sync` ≈ time to drain old-side consumer
  lag to zero.

`T_dns_ttl` matters when cutover is via DNS — pre-lower the TTL (e.g. 60 s)
at least one TTL period before cutover.

## 3. Validation Approach (one paragraph each)

- **Relational (DMS).** Validate via DMS [data validation][dms-validation]
  (row hash, configurable sample). Block cutover until validation reports
  zero mismatches across all tables in scope; spot-check business-critical
  tables with an app-level query.
- **NoSQL (DMS / dual-write).** Compare item counts per partition and
  sample-checksum a representative key set. For dual-write, run a
  read-compare job that issues the same key to both sides for a sampling
  window before cutover.
- **Block PV (Velero).** Restore into a non-prod namespace first, run the
  app's startup probe + a smoke test. Production restore must reproduce the
  same probe + smoke result before traffic is admitted.
- **File / object (DataSync).** Use DataSync's built-in
  [verification mode][datasync-verify] (`VerifyMode: ONLY_FILES_TRANSFERRED`
  or `POINT_IN_TIME_CONSISTENT`). Spot-check file counts and a SHA-256
  sample at the destination.
- **Queues.** Confirm consumer lag = 0 on the old side, message-ID dedupe
  in the new side for a sampling window, and idempotency of consumers
  (replay-safe).
- **Cache.** Validate hit-rate returns to baseline within an agreed warm-up
  window post-cutover. Do not gate cutover on cache state.
- **Search index.** Validate document count parity and run a fixed query
  set comparing top-K results between old and new index.

## 4. References

- [AWS DMS][dms] · [DMS data validation][dms-validation] · [DMS CDC][dms-cdc]
- [AWS DataSync overview][datasync-overview] · [DataSync verification][datasync-verify]
- [Velero][velero] · [EBS CSI driver on EKS][ebs-csi]
- [Amazon MSK][msk] · [Amazon MQ][amq] · [ElastiCache][elasticache] ·
  [OpenSearch Service][opensearch]
- ACMF: [`docs/playbooks/traffic-shifting.md`](../playbooks/traffic-shifting.md)
  — the data plane must be consistent before traffic is shifted for stateful
  workloads.

[dms]: https://docs.aws.amazon.com/dms/latest/userguide/Welcome.html
[dms-cdc]: https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Task.CDC.html
[dms-ddb]: https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Target.DynamoDB.html
[dms-validation]: https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Validating.html
[dms-metrics]: https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Monitoring.html
[datasync-overview]: https://docs.aws.amazon.com/datasync/latest/userguide/what-is-datasync.html
[datasync-nfs-efs]: https://docs.aws.amazon.com/datasync/latest/userguide/tutorial_nfs-efs-fargate.html
[datasync-s3]: https://docs.aws.amazon.com/datasync/latest/userguide/create-s3-location.html
[datasync-verify]: https://docs.aws.amazon.com/datasync/latest/userguide/configure-data-verification-options.html
[velero]: https://velero.io/docs/main/
[ebs-csi]: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
[msk]: https://docs.aws.amazon.com/msk/latest/developerguide/what-is-msk.html
[msk-migration]: https://docs.aws.amazon.com/msk/latest/developerguide/migration.html
[amq]: https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/welcome.html
[elasticache]: https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/WhatIs.html
[opensearch]: https://docs.aws.amazon.com/opensearch-service/latest/developerguide/what-is.html
[opensearch-mig]: https://docs.aws.amazon.com/opensearch-service/latest/developerguide/migration-assistant.html
