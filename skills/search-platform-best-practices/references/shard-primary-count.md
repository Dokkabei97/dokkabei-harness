---
title: Design Primary Shard Count at Index Creation — It Cannot Be Changed Later
impact: CRITICAL
impactDescription: Wrong primary shard count requires full reindex to fix, affects all future query and indexing performance
tags: shard, primary, count, design, immutable, capacity-planning
---

## Design Primary Shard Count at Index Creation — It Cannot Be Changed Later

The number of primary shards is set at index creation and **cannot be changed** without reindexing (or using the shrink/split API with restrictions). Under-sharding limits write throughput and query parallelism; over-sharding wastes resources. This is the single most important capacity planning decision.

**Incorrect (using defaults without planning):**

```json
// Elasticsearch 7+ default: 1 primary shard
// Fine for small indices, but a 500GB index on 1 shard = disaster
PUT /products
{
  "settings": {
    "number_of_replicas": 1
  }
}
// number_of_shards defaults to 1
// 500GB in 1 shard → no query parallelism, slow recovery, merge bottleneck

// The opposite extreme — blindly over-sharding
PUT /tiny-config
{
  "settings": {
    "number_of_shards": 10,
    "number_of_replicas": 1
  }
}
// 200KB of config data in 10 shards — 20 total shards for trivial data
```

**Correct (calculated shard count based on expected data volume):**

```json
// Step 1: Estimate total data volume at peak
// Products: ~200GB, growing ~20GB/year

// Step 2: Calculate shard count (target 30-50GB per shard)
// 200GB / 40GB = 5 primary shards

PUT /products-v1
{
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 1
  }
}
// 10 total shards, each ~40GB at peak — well within limits

// For time-series data, use ILM rollover instead of fixed shard count
// One shard per rollover period, rollover at size threshold
PUT /_index_template/logs-template
{
  "index_patterns": ["logs-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "index.lifecycle.name": "logs-policy"
    }
  }
}
```

Decision matrix:

| Expected Index Size | Primary Shards | Reasoning |
|-------------------|---------------|-----------|
| < 1GB | 1 | Minimal data, no parallelism needed |
| 1-10GB | 1 | Single shard sufficient |
| 10-50GB | 1-2 | Approaching shard size limit |
| 50-200GB | 2-5 | Balance parallelism and overhead |
| 200GB-1TB | 5-20 | Scale with data nodes |
| > 1TB | 20+ | Match to available data nodes |

Additional factors:
- **Write throughput**: Each primary shard handles writes independently; more shards = more parallel writes
- **Search parallelism**: Each shard is searched concurrently; ensure shard count <= data node count for optimal distribution
- **Data node count**: Shards should be evenly distributable across data nodes (e.g., 6 shards on 3 nodes = 2 per node)

Reference: [Index settings](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-modules.html#_static_index_settings)
