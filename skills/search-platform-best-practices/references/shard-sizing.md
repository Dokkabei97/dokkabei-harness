---
title: Target 10-50GB Per Shard for Optimal Performance
impact: HIGH
impactDescription: Right-sized shards balance query latency, indexing throughput, and recovery time
tags: shard, sizing, performance, storage, optimization
---

## Target 10-50GB Per Shard for Optimal Performance

Shards that are too small waste overhead (memory, file handles, cluster state per shard). Shards that are too large cause slow recovery, long GC pauses during merges, and uneven query latency. The sweet spot is 10-50GB per shard.

**Incorrect (1GB micro-shards — excessive overhead):**

```json
// 500GB of data split into 500 × 1GB shards
PUT /logs-000001
{
  "settings": {
    "number_of_shards": 500,
    "number_of_replicas": 1
  }
}
// 1,000 total shards (primary + replica)
// Each shard has ~50-100MB heap overhead → 50-100GB heap just for shard metadata
// Coordinating node merges 500 partial results per search → high fan-out latency
```

**Incorrect (200GB mega-shards — slow recovery and merges):**

```json
// 500GB of data in 2 shards of ~250GB each
PUT /logs
{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1
  }
}
// Shard recovery after node failure: copying 250GB over network → hours of recovery
// Segment merges on 250GB shards → long GC pauses
// No parallelism — only 2 shards searched concurrently
```

**Correct (right-sized shards):**

```json
// 500GB of data → 10-16 shards of ~30-50GB each
PUT /logs
{
  "settings": {
    "number_of_shards": 12,
    "number_of_replicas": 1
  }
}
// 24 total shards (12 primary + 12 replica)
// Each shard ~42GB — within optimal range
// Recovery time: ~42GB per shard = reasonable
// Query parallelism: 12 shards searched concurrently
```

Calculate optimal shard count:

```
Expected Data Volume / Target Shard Size = Number of Shards

Example:
- Expected data: 600GB
- Target shard size: 40GB
- Primary shards: 600 / 40 = 15
- With 1 replica: 30 total shards

For time-based data with ILM rollover:
- Daily ingestion: 50GB/day
- Rollover at: 50GB primary shard size
- Shards per day: 1 primary (rollover handles sizing)
```

Use ILM rollover to maintain right-sized shards automatically:

```json
PUT /_ilm/policy/optimal-shard-sizing
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_primary_shard_size": "40gb",
            "max_age": "7d"
          }
        }
      }
    }
  }
}
// Rolls over when any primary shard reaches 40GB or 7 days
// Guarantees shards stay within the optimal range
```

Sizing reference:

| Shard Size | Verdict | Issue |
|-----------|---------|-------|
| < 1GB | Too small | Excessive overhead per shard |
| 1-10GB | Small | Acceptable for low-volume indices |
| **10-50GB** | **Optimal** | **Best balance of all factors** |
| 50-100GB | Large | Recovery takes longer, acceptable if stable |
| > 100GB | Too large | Slow recovery, merge pressure, GC risk |

Reference: [Size your shards](https://www.elastic.co/guide/en/elasticsearch/reference/current/size-your-shards.html)
