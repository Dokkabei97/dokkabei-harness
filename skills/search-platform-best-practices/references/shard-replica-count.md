---
title: Set Replica Count Based on Availability and Search Throughput Trade-offs
impact: HIGH
impactDescription: Replicas provide fault tolerance and search throughput at the cost of storage and indexing speed
tags: shard, replica, availability, throughput, trade-off
---

## Set Replica Count Based on Availability and Search Throughput Trade-offs

Replicas serve two purposes: fault tolerance (data survives node loss) and search throughput (replicas serve read requests). But each replica doubles (or triples) storage and adds write overhead since every document is indexed on all copies.

**Incorrect (no replicas in production — data loss on node failure):**

```json
PUT /critical-data
{
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 0
  }
}
// Node failure = permanent data loss for shards on that node
// Cluster health: RED until node recovers
```

**Incorrect (too many replicas — wasteful for low-traffic index):**

```json
PUT /internal-config
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 3
  }
}
// 4 copies of 500MB = 2GB total for a rarely-searched config index
// Every write is replicated 3 times — slows indexing for no benefit
```

**Correct (replicas aligned with requirements):**

```json
// Production search index — 1 replica for availability + read scaling
PUT /products
{
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 1
  }
}
// Can survive 1 node failure, doubles search throughput

// High-traffic search index — 2 replicas for extra read throughput
PUT /products-popular
{
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 2
  }
}
// Survives 2 simultaneous node failures, 3x search throughput

// Replicas are dynamic — adjust without reindexing
PUT /products/_settings
{
  "number_of_replicas": 2
}
```

Trade-off matrix:

| Replicas | Storage | Write Speed | Read Throughput | Fault Tolerance |
|----------|---------|-------------|-----------------|-----------------|
| 0 | 1x | Fastest | 1x | None |
| 1 | 2x | ~30% slower | 2x | 1 node loss |
| 2 | 3x | ~50% slower | 3x | 2 node loss |

Special cases:

```json
// During initial bulk load — temporarily disable replicas for speed
PUT /products/_settings
{ "number_of_replicas": 0 }

// ... bulk load ...

// Re-enable replicas after load completes
PUT /products/_settings
{ "number_of_replicas": 1 }

// For cross-AZ deployments — ensure at least 1 replica survives AZ failure
PUT /_cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.awareness.attributes": "zone",
    "cluster.routing.allocation.awareness.force.zone.values": "az-a,az-b"
  }
}
// Ensures primary and replica are in different AZs
```

Guidelines:
- **Production**: Minimum 1 replica
- **High-traffic search**: 2 replicas
- **Batch processing / initial load**: 0 replicas temporarily
- **Dev/test**: 0 replicas acceptable
- Never set replicas > (number of data nodes - 1); excess replicas stay unassigned (yellow health)

Reference: [Replica shards](https://www.elastic.co/guide/en/elasticsearch/reference/current/scalability.html)
