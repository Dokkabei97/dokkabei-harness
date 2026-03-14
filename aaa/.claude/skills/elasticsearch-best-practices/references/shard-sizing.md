---
title: "Target 30-50GB Per Shard for Optimal Performance"
impact: HIGH
impactDescription: "2-5x search performance improvement with right-sized shards"
tags: shard, sizing, performance, capacity-planning
---

## Target 30-50GB Per Shard for Optimal Performance

Each shard is a self-contained Lucene index with its own file handles, memory overhead, and cluster state cost. Shards that are too small (< 1GB) waste master resources tracking thousands of tiny indices, while shards that are too large (> 50GB) cause slow recoveries, unbalanced search parallelism, and risk uneven data distribution. The sweet spot of 30-50GB per shard balances recovery speed, search parallelism, and resource overhead.

**Incorrect (default 1 shard for a 500GB index):**

```json
// Single shard for a massive index - recovery takes hours, no search parallelism
PUT /order-history
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 1
  }
}
// Result: 1 shard at 500GB
// - Shard recovery after node failure: 30-60 minutes
// - Search limited to single thread per shard
// - Cannot distribute across multiple data nodes
```

```json
// Opposite extreme: 500 shards for a 500GB index
PUT /order-history
{
  "settings": {
    "number_of_shards": 500,
    "number_of_replicas": 1
  }
}
// Result: 500 shards at 1GB each
// - 1000 total shards (primary + replica) tracked in cluster state
// - Master node overwhelmed managing shard allocation
// - Each search fans out to 500 shards → massive coordination overhead
```

**Correct (calculate shard count from data volume):**

```json
// 500GB index → target 40GB per shard → ceil(500/40) = 13 primary shards
PUT /order-history
{
  "settings": {
    "number_of_shards": 13,
    "number_of_replicas": 1
  }
}
// Result: 13 shards at ~38GB each
// - Recovery per shard: 2-5 minutes
// - Search parallelism across 13 threads
// - 26 total shards (primary + replica) fit comfortably on 5+ data nodes
```

**Shard sizing formula:**

```
num_primary_shards = ceil(total_data_size / target_shard_size)

Where:
  target_shard_size = 30-50GB (default: 40GB as middle ground)
  total_data_size   = current data + projected growth within reindex cycle
```

**Sizing reference table:**

| Total Data Size | Target Shard Size | Primary Shards | Total Shards (1 replica) |
|----------------|-------------------|----------------|--------------------------|
| 10GB | 10GB (min viable) | 1 | 2 |
| 50GB | 50GB | 1-2 | 2-4 |
| 100GB | 40GB | 3 | 6 |
| 250GB | 40GB | 7 | 14 |
| 500GB | 40GB | 13 | 26 |
| 1TB | 40GB | 26 | 52 |
| 5TB | 50GB | 100 | 200 |
| 10TB | 50GB | 200 | 400 |

**Verification commands:**

```json
// Check current shard sizes across indices
GET _cat/shards?v&s=store:desc&h=index,shard,prirep,store,node

// Monitor cluster-wide shard count (stay under 1000 shards per data node)
GET _cluster/health?filter_path=active_primary_shards,active_shards

// Check for oversharded small indices
GET _cat/indices?v&s=store.size:asc&h=index,pri,rep,docs.count,store.size
```

**Key rules:**

- Target 30-50GB per shard. Use 40GB as a safe default for most workloads.
- Never let a single shard exceed 50GB — recovery and rebalancing times become unacceptable.
- Aim for fewer than 1000 shards per data node to avoid cluster state overhead.
- For indices smaller than 10GB, a single primary shard is usually sufficient.
- Account for projected data growth: if a 100GB index will double in 6 months, plan for 200GB at reindex time.
- Shard count cannot be changed after index creation — either reindex or use ILM rollover for time-series data.

Reference:
[Size Your Shards](https://www.elastic.co/guide/en/elasticsearch/reference/current/size-your-shards.html)
