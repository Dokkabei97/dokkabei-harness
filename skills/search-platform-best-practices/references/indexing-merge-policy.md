---
title: Tune Merge Policy to Balance Indexing Throughput and Search Performance
impact: MEDIUM
impactDescription: Reduces merge-related I/O contention during peak indexing, improves search latency on read-heavy indices
tags: indexing, merge, policy, segments, lucene, performance
---

## Tune Merge Policy to Balance Indexing Throughput and Search Performance

Lucene stores data in immutable segments. As new data is indexed, small segments are created and periodically merged into larger ones. Merging improves search performance (fewer segments to scan) but competes for I/O and CPU with indexing and search. Tuning the merge policy balances these competing demands.

**Incorrect (default merge settings on high-throughput indexing — I/O contention):**

```json
// Default merge policy aggressively merges segments
// On a high-throughput indexing node, merges compete with bulk indexing for disk I/O
// Symptoms:
// - Indexing throughput drops periodically (during large merges)
// - Search latency spikes during merge I/O
// - "merge throttling" messages in logs
```

**Correct (tune merge throttle and policy for workload):**

```json
// For write-heavy indices: increase merge throttle to prevent indexing stalls
PUT /logs/_settings
{
  "index.merge.scheduler.max_thread_count": 1,
  "index.merge.policy.max_merged_segment": "5gb",
  "index.merge.policy.segments_per_tier": 10,
  "index.merge.policy.max_merge_at_once": 10
}
// max_thread_count: 1 for spinning disks, higher for SSD
// max_merged_segment: caps segment size to prevent very long merges
// segments_per_tier: higher = fewer merges (more segments tolerated)
```

```json
// Cluster-level merge throttle (bytes/sec available for merging)
PUT /_cluster/settings
{
  "persistent": {
    "indices.store.throttle.max_bytes_per_sec": "100mb"
  }
}
// Default is 20mb — increase for NVMe SSD, decrease for HDD
```

For read-optimized indices (after bulk load), force merge to reduce segments:

```json
// After data loading is complete, merge down to fewer segments
POST /products/_forcemerge?max_num_segments=1
// Warning: Very I/O intensive — run during off-peak hours
// Only for read-only or rarely-written indices

// For warm/cold tier indices (ILM), include forcemerge in the policy
PUT /_ilm/policy/logs-policy
{
  "policy": {
    "phases": {
      "warm": {
        "actions": {
          "forcemerge": {
            "max_num_segments": 1
          }
        }
      }
    }
  }
}
```

Monitor segment health:

```json
// Check segment count per shard
GET /_cat/segments/products?v&h=index,shard,segment,size
// Many small segments = merge falling behind
// Few large segments = optimal for search

// Check merge activity
GET /_cat/nodes?v&h=name,merges.current,merges.total,merges.total_size
```

Merge policy guidelines:

| Workload | max_thread_count | segments_per_tier | Force merge? |
|----------|-----------------|-------------------|-------------|
| Write-heavy (SSD) | 4-6 | 10-15 | No (always writing) |
| Write-heavy (HDD) | 1 | 15-20 | No |
| Read-heavy (search) | Default | Default (10) | Yes, after load |
| Mixed | 2-3 | 10 | On warm tier only |

Reference: [Merge](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-modules-merge.html)
