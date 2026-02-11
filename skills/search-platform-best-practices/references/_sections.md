# Section Definitions

This file defines the rule categories for Elasticsearch/OpenSearch best practices. Rules are automatically assigned to sections based on their filename prefix.

---

## 1. Mapping & Schema Design (mapping)
**Impact:** CRITICAL
**Description:** Field types, dynamic mapping pitfalls, nested vs object, keyword vs text, and multi-field strategies. The foundation of all search performance — wrong mappings cause cascading problems across queries, indexing, and storage.

## 2. Query Performance (query)
**Impact:** CRITICAL
**Description:** Query DSL optimization, filter context vs query context, bool query composition, script elimination, and search profiling. The most direct lever for user-facing latency.

## 3. Cluster & Node Architecture (cluster)
**Impact:** CRITICAL
**Description:** Node roles (master/data/coordinating/ingest), heap sizing, hardware planning, and cluster topology. Misconfiguration here causes cluster-wide instability or outages.

## 4. Index & Shard Strategy (shard)
**Impact:** HIGH
**Description:** Shard count, shard sizing (30-50GB target), over-sharding prevention, shrink/split operations, and rollover strategies. Directly impacts cluster overhead and query parallelism.

## 5. Indexing Performance (indexing)
**Impact:** HIGH
**Description:** Bulk API usage, refresh interval tuning, translog settings, ingest pipelines, and reindex strategies. Critical for write-heavy workloads and data ingestion throughput.

## 6. Korean/CJK Search & Analyzers (analyzer)
**Impact:** HIGH
**Description:** Nori analyzer configuration, custom token filters, synonym management, ICU normalization, and CJK-specific tokenization strategies. Essential for Korean/Japanese/Chinese language search quality.

## 7. Security (security)
**Impact:** MEDIUM-HIGH
**Description:** TLS/SSL configuration, role-based access control, field/document level security, API key management, and audit logging.

## 8. Aggregation Optimization (agg)
**Impact:** MEDIUM-HIGH
**Description:** Terms aggregation cardinality, composite aggregations for pagination, pipeline aggregations, and memory-efficient patterns. Common source of OOM and slow responses.

## 9. Resilience & Recovery (resilience)
**Impact:** MEDIUM
**Description:** Snapshot/restore, replica strategies, cluster health recovery, shard allocation awareness, and disaster recovery patterns.

## 10. Data Lifecycle (lifecycle)
**Impact:** MEDIUM
**Description:** Index Lifecycle Management (ILM), data tiers (hot/warm/cold/frozen), rollover policies, and retention strategies. Essential for cost-efficient long-term data management.

## 11. Cross-Cluster (crosscluster)
**Impact:** MEDIUM
**Description:** Cross-cluster search (CCS), cross-cluster replication (CCR), remote cluster configuration, and multi-cluster architecture patterns.

## 12. Monitoring & Diagnostics (monitor)
**Impact:** LOW-MEDIUM
**Description:** _cat APIs, cluster stats, node stats, slow logs, task management, and hot threads analysis. Essential for diagnosing production issues.

## 13. Kubernetes / ECK Operations (k8s)
**Impact:** LOW-MEDIUM
**Description:** Elastic Cloud on Kubernetes (ECK) operator, StatefulSet strategies, persistent volume management, rolling upgrades, and resource quotas.

## 14. Advanced Features (advanced)
**Impact:** LOW
**Description:** Vector search (kNN), Learning to Rank, semantic search, runtime fields, search templates, and async search patterns.
