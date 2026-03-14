# Section Definitions

This file defines the rule categories for Elasticsearch best practices. Rules are automatically assigned to sections based on their filename prefix.

---

## 1. Mapping & Schema Design (mapping)
**Impact:** CRITICAL
**Description:** Field type selection, explicit mapping, nested vs object, and multi-field strategies. Foundation for search accuracy and index efficiency.

## 2. Query Performance (query)
**Impact:** CRITICAL
**Description:** Bool query optimization, filter vs must context, pagination strategies, and query profiling. The most impactful area for search latency.

## 3. Cluster Architecture (cluster)
**Impact:** CRITICAL
**Description:** Node role separation, JVM heap sizing, and tiered storage architecture. Essential for cluster stability at scale.

## 4. Shard Strategy (shard)
**Impact:** HIGH
**Description:** Shard sizing, primary count calculation, and index template with ILM rollover. Determines search parallelism and resource utilization.

## 5. Indexing & Bulk (indexing)
**Impact:** HIGH
**Description:** Bulk API usage, BulkIngester migration, initial load optimization, and refresh interval tuning. Critical for write throughput.

## 6. Analyzer (analyzer)
**Impact:** HIGH
**Description:** Custom analyzer chains, Korean morphological analysis with Nori, and edge n-gram for autocomplete. Determines search quality.

## 7. Client & Framework (client)
**Impact:** HIGH
**Description:** Spring Data ES pitfalls, elasticsearch-java client usage, and connection pool configuration. Bridges application code to cluster.

## 8. Streaming & Integration (streaming)
**Impact:** MEDIUM-HIGH
**Description:** Kafka/MQ consuming strategies for bulk indexing and backpressure patterns. Essential for event-driven architectures.

## 9. Aggregation (agg)
**Impact:** MEDIUM
**Description:** Composite aggregation pagination and terms cardinality control. Prevents OOM and optimizes analytics queries.

## 10. Monitoring (monitor)
**Impact:** LOW-MEDIUM
**Description:** Slow log configuration for production query diagnosis. Foundational for ongoing performance management.
