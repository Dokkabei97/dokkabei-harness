---
title: Disable Refresh/Replicas During Initial Bulk Load
impact: HIGH
impactDescription: 2-5x faster initial data loading
tags: indexing, initial-load, refresh, replica, bulk-load
---

## Disable Refresh/Replicas During Initial Bulk Load

During initial bulk loading, the default 1-second refresh interval creates a new Lucene segment every second, and replicas duplicate every write operation across the cluster. Both are wasted work when no one is searching the index yet. On a 100M+ document initial load, disabling refresh and replicas cuts indexing time by 2-5x and reduces I/O pressure across all data nodes.

**Incorrect (bulk loading with default settings):**

```json
// Default: refresh_interval=1s, number_of_replicas=1
// Every second creates a new segment → segment merge overhead during load
// Every document written twice (primary + replica) → 2x write amplification
// 100M docs at 5KB each: ~1TB of unnecessary replica writes during load

PUT /orders
{
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 1
  },
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "order_id": { "type": "keyword" },
      "customer_id": { "type": "keyword" },
      "total_amount": { "type": "double" },
      "status": { "type": "keyword" },
      "created_at": { "type": "date" }
    }
  }
}

// Start bulk loading immediately → refresh + replica overhead from first document
POST /_bulk
{ "index": { "_index": "orders", "_id": "ORD-100001" } }
{ "order_id": "ORD-100001", "customer_id": "C-5001", "total_amount": 149.99, "status": "completed", "created_at": "2024-01-15T10:30:00Z" }
// ... millions more documents, all refreshed every 1s with replicas
```

**Correct (3-step process: disable, load, restore):**

**Step 1 — Disable refresh and replicas before loading:**

```json
// Create index with loading-optimized settings
// refresh_interval=-1 → no automatic segment creation during load
// number_of_replicas=0 → writes go to primary shards only
PUT /orders
{
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 0,
    "refresh_interval": "-1",
    "index.translog.durability": "async",
    "index.translog.flush_threshold_size": "1gb"
  },
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "order_id": { "type": "keyword" },
      "customer_id": { "type": "keyword" },
      "total_amount": { "type": "double" },
      "status": { "type": "keyword" },
      "created_at": { "type": "date" }
    }
  }
}
```

**Step 2 — Bulk load at maximum throughput:**

```json
// Multiple parallel bulk requests, no refresh/replica overhead
// Use 5-15MB per bulk request with multiple ingest threads
POST /_bulk
{ "index": { "_index": "orders", "_id": "ORD-100001" } }
{ "order_id": "ORD-100001", "customer_id": "C-5001", "total_amount": 149.99, "status": "completed", "created_at": "2024-01-15T10:30:00Z" }
{ "index": { "_index": "orders", "_id": "ORD-100002" } }
{ "order_id": "ORD-100002", "customer_id": "C-5002", "total_amount": 89.50, "status": "shipped", "created_at": "2024-01-15T11:45:00Z" }
// ... continue with parallel bulk threads until all data loaded
```

**Step 3 — Restore production settings and optimize:**

```json
// Restore replicas and refresh interval for production readiness
PUT /orders/_settings
{
  "index": {
    "number_of_replicas": 1,
    "refresh_interval": "1s",
    "translog.durability": "request",
    "translog.flush_threshold_size": "512mb"
  }
}

// Force merge to optimal segment count after load completes
// Reduces segment count → faster searches, less memory for segment metadata
// max_num_segments=1 per shard for static data, 5 for indices still receiving writes
POST /orders/_forcemerge?max_num_segments=5

// Verify cluster health returns green (all replicas allocated)
GET /_cluster/health/orders?wait_for_status=green&timeout=5m
```

**Performance impact on 100M document load (5 primary shards, 10-node cluster):**

| Setting | Default | Optimized | Improvement |
|---------|---------|-----------|-------------|
| Refresh during load | Every 1s | Disabled | No segment churn |
| Replica writes | 2x write amplification | Primary only | 50% less I/O |
| Translog durability | sync per request | async | Fewer fsync calls |
| Total load time | ~4 hours | ~1 hour | **~4x faster** |

Always restore `translog.durability` to `"request"` (the default) after loading. Async durability during normal operation risks data loss on node failure.

Reference: [Tune for indexing speed](https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-indexing-speed.html)
