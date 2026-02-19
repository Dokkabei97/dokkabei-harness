---
title: "Control Terms Aggregation Cardinality to Prevent OOM"
impact: MEDIUM-HIGH
impactDescription: "Prevents heap explosion and circuit breaker trips on high-cardinality fields"
tags: agg, terms, cardinality, memory, circuit-breaker
---

## Control Terms Aggregation Cardinality to Prevent OOM

A `terms` aggregation on a high-cardinality field (e.g., user_id with 50M unique values) builds a bucket for every unique value across all shards, then merges them on the coordinating node. With `size: 100000` on a field with millions of unique values, each shard returns 100K+ buckets, and the coordinating node holds N_shards x 100K buckets in heap simultaneously. This regularly trips the `request` circuit breaker or causes full GC pauses that destabilize the cluster.

**Incorrect (blind terms aggregation on high-cardinality field):**

```json
// BAD: user_id has 50 million unique values
// BAD: Each shard builds and returns 50000 buckets
// BAD: Coordinating node merges 50000 x 20 shards = 1M buckets in heap
GET /user-activities/_search
{
  "size": 0,
  "aggs": {
    "active_users": {
      "terms": {
        "field": "user_id",
        "size": 50000
      },
      "aggs": {
        "total_actions": {
          "value_count": { "field": "action_type" }
        },
        "last_seen": {
          "max": { "field": "timestamp" }
        }
      }
    }
  }
}
// Result: CircuitBreakingException [request] (limit: 6GB, estimated: 8.2GB)
// Or: 60-second response time with full GC pauses
```

**Correct (check cardinality first, then choose appropriate strategy):**

Step 1: Always check field cardinality before running terms aggregation.

```json
// Fast cardinality estimate using HyperLogLog++ (constant memory, ~2% error)
GET /user-activities/_search
{
  "size": 0,
  "aggs": {
    "unique_users": {
      "cardinality": {
        "field": "user_id",
        "precision_threshold": 10000
      }
    }
  }
}
// Response: { "value": 48293741 } -> 48M unique users
// Decision: Too high for terms -> use composite aggregation instead
```

Step 2: Choose strategy based on cardinality.

```
Cardinality       | Strategy
------------------|-------------------------------------------------
< 1,000           | terms with size=1000 (safe, full coverage)
1,000 - 10,000    | terms with reasonable size (monitor memory)
10,000 - 100,000  | terms with caution + sampler, or composite
> 100,000         | composite aggregation (mandatory for safety)
```

Step 3a: For moderate cardinality, use `sampler` to limit documents processed.

```json
// Limit to top 10K documents per shard before aggregating
// Reduces both memory and latency for exploratory analysis
GET /user-activities/_search
{
  "size": 0,
  "aggs": {
    "sample": {
      "sampler": {
        "shard_size": 10000
      },
      "aggs": {
        "top_users": {
          "terms": {
            "field": "user_id",
            "size": 100
          },
          "aggs": {
            "total_actions": {
              "value_count": { "field": "action_type" }
            }
          }
        }
      }
    }
  }
}
```

Step 3b: For high cardinality (100K+), switch to composite aggregation.

```json
// Paginate through all users with constant memory
GET /user-activities/_search
{
  "size": 0,
  "aggs": {
    "all_users": {
      "composite": {
        "size": 2000,
        "sources": [
          { "user": { "terms": { "field": "user_id" } } }
        ]
      },
      "aggs": {
        "total_actions": {
          "value_count": { "field": "action_type" }
        },
        "last_seen": {
          "max": { "field": "timestamp" }
        }
      }
    }
  }
}
// Paginate with "after" until all 48M users are processed
```

Step 3c: Use `shard_size` to control per-shard memory when terms is needed.

```json
// shard_size controls how many buckets each shard returns to the coordinator
// Default: shard_size = size * 1.5 + 10
// Lower shard_size = less memory on coordinator, but less accurate results
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "top_products": {
      "terms": {
        "field": "product_id",
        "size": 100,
        "shard_size": 200
      }
    }
  }
}
// Each shard returns 200 buckets (not default 160)
// Coordinator merges 200 x N_shards, returns top 100
// Trade-off: lower shard_size = less accuracy for long-tail terms
```

**Memory estimation formula:**

```
coordinator_memory = shard_size x num_shards x (key_size + 24 bytes + sub_agg_size)

Example: terms on user_id (keyword, avg 20 bytes) with 1 sub-agg
  shard_size = 50000
  num_shards = 20
  per_bucket = 20 (key) + 24 (overhead) + 32 (sub-agg) = 76 bytes

  memory = 50000 x 20 x 76 = ~76MB
  With 3 sub-aggs: 50000 x 20 x 140 = ~140MB

  This is per-request — 10 concurrent requests = 1.4GB heap
```

**Key rules:**

- Always run a `cardinality` aggregation before running `terms` on unknown or high-cardinality fields.
- For cardinality above 100K, use `composite` aggregation instead of `terms` — no exceptions.
- Set `shard_size` explicitly when you need terms on moderate-cardinality fields (10K-100K) to control coordinator memory.
- Wrap exploratory terms in a `sampler` aggregation to bound the documents processed per shard.
- Monitor the `request` circuit breaker: `GET /_nodes/stats/breaker` — repeated trips indicate oversized aggregations.
- Consider pre-aggregating high-cardinality metrics into a separate summary index using transforms.

Reference:
[Terms Aggregation](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-terms-aggregation.html) |
[Cardinality Aggregation](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-metrics-cardinality-aggregation.html)
