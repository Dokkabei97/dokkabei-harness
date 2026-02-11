---
title: Optimize Initial Bulk Load with refresh_interval -1 and Replicas 0
impact: HIGH
impactDescription: 2-5x faster initial data load by eliminating refresh and replication overhead
tags: indexing, bulk-load, refresh-interval, replica, initial-load, migration
---

## Optimize Initial Bulk Load with refresh_interval -1 and Replicas 0

During initial data population (migration, full reindex, disaster recovery), normal index settings optimized for search latency waste resources. Disabling refresh and replicas during load, then restoring them after, dramatically improves throughput.

**Incorrect (loading with production settings — slow):**

```json
// Default settings: refresh every 1s, 1 replica
PUT /products
{
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 1,
    "refresh_interval": "1s"
  }
}

// Bulk loading 100M documents with search-optimized settings
// Every 1 second: create new Lucene segment (expensive)
// Every document: replicated to replica shard (doubles write work)
// Estimated load time: 4 hours
```

**Correct (disable refresh and replicas during load):**

```json
// Step 1: Create index with load-optimized settings
PUT /products
{
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 0,
    "refresh_interval": "-1",
    "index.translog.durability": "async",
    "index.translog.flush_threshold_size": "1gb"
  }
}

// Step 2: Bulk load data (multiple parallel threads)
POST /_bulk
{"index":{"_index":"products"}}
{"name":"상품 1","price":10000}
{"index":{"_index":"products"}}
{"name":"상품 2","price":20000}
// ... millions of documents

// Step 3: After load completes, trigger manual refresh and restore settings
POST /products/_refresh

PUT /products/_settings
{
  "number_of_replicas": 1,
  "refresh_interval": "1s",
  "index.translog.durability": "request"
}

// Step 4: Wait for replica allocation to complete
GET /_cat/recovery/products?v&active_only=true

// Step 5: Force merge for optimal read performance
POST /products/_forcemerge?max_num_segments=5
```

Impact comparison:

| Setting | During Load | After Load | Impact |
|---------|------------|------------|--------|
| `refresh_interval` | `-1` (disabled) | `1s` | Eliminates segment creation overhead |
| `number_of_replicas` | `0` | `1` | Halves write work |
| `translog.durability` | `async` | `request` | Reduces fsync overhead |
| `translog.flush_threshold_size` | `1gb` | `512mb` (default) | Fewer flushes |

Additional optimizations for extreme load speeds:

```json
// Increase indexing buffer per shard
PUT /products/_settings
{
  "index.indexing.memory.index_buffer_size": "512mb"
}

// Use index sorting to improve compression (if applicable)
PUT /products
{
  "settings": {
    "index.sort.field": ["category", "created_at"],
    "index.sort.order": ["asc", "desc"]
  },
  "mappings": {
    "properties": {
      "category": { "type": "keyword" },
      "created_at": { "type": "date" }
    }
  }
}
```

Important: After restoring `number_of_replicas`, monitor cluster health until all replicas are allocated (yellow → green). Do not direct production traffic until the cluster is green.

Reference: [Tune for indexing speed](https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-indexing-speed.html)
