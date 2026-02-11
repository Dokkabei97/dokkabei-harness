---
title: Keep Shard Count Below 1,000 Per Node to Prevent Cluster Instability
impact: CRITICAL
impactDescription: Excessive shards cause slow cluster state updates, high memory overhead, and master node instability
tags: cluster, shard, limit, oversharding, cluster-state, stability
---

## Keep Shard Count Below 1,000 Per Node to Prevent Cluster Instability

Every shard consumes memory on every node (cluster state) and on the data node hosting it (segment metadata, file handles). Clusters with too many shards experience slow cluster state propagation, master instability, and degraded query performance as the coordinating node must merge results from every targeted shard.

**Incorrect (thousands of tiny shards per node):**

```json
// Creating a daily index per microservice with defaults
// 20 microservices × 365 days × 1 primary × 1 replica = 14,600 shards
// On a 5-node cluster = ~2,920 shards per node

// Each daily index is only ~500MB but has its own shard overhead
PUT /service-orders-2024-01-01
{ "settings": { "number_of_shards": 1, "number_of_replicas": 1 } }

PUT /service-payments-2024-01-01
{ "settings": { "number_of_shards": 1, "number_of_replicas": 1 } }

// ... 20 services × 365 days = micro-shards everywhere
// Cluster state metadata: 14,600 shards × ~3KB each ≈ 44MB (updated atomically across all nodes)
// Master publishing cluster state takes 5-10 seconds → delayed shard allocation
```

**Correct (consolidated indices with rollover, controlled shard count):**

```json
// Use index templates with ILM rollover instead of daily indices
PUT /_index_template/service-logs
{
  "index_patterns": ["logs-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.lifecycle.name": "logs-policy",
      "index.lifecycle.rollover_alias": "logs-write"
    }
  }
}

// ILM rolls over based on shard size (not time), creating fewer, right-sized shards
PUT /_ilm/policy/logs-policy
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_primary_shard_size": "30gb",
            "max_age": "7d"
          }
        }
      }
    }
  }
}
```

Monitor and audit shard counts:

```json
// Check total shards per node
GET /_cat/allocation?v&h=node,shards,disk.percent
// node     shards disk.percent
// data-1   450    62
// data-2   480    58
// data-3   520    71

// Check total shard count
GET /_cluster/health?filter_path=active_primary_shards,active_shards
// { "active_primary_shards": 725, "active_shards": 1450 }

// Set cluster-level shard limit as a safety net
PUT /_cluster/settings
{
  "persistent": {
    "cluster.max_shards_per_node": 1000
  }
}
// New index creation will be rejected if it would exceed this limit
```

Rules of thumb:
- Target **20 shards per GB of heap** (e.g., 31GB heap → ~600 shards max)
- Each shard should be **10-50GB** (see `shard-sizing.md`)
- Prefer fewer, larger shards over many small shards
- Use Data Streams or ILM rollover instead of time-based index naming with fixed schedules
- Regularly audit with `_cat/shards?v` and delete/close stale indices

Per-shard memory overhead:
- ~10KB cluster state per shard (multiplied across all nodes)
- ~50-100MB heap per shard on the hosting data node (segment metadata, file handles)
- Each search hits every shard in the target index — more shards = more fan-out

Reference: [Size your shards](https://www.elastic.co/guide/en/elasticsearch/reference/current/size-your-shards.html)
