---
title: Establish Red and Yellow Cluster Health Response Procedures
impact: MEDIUM
impactDescription: Rapid diagnosis and resolution of cluster health issues prevents data loss and extended outages
tags: resilience, cluster-health, red, yellow, troubleshooting, recovery
---

## Establish Red and Yellow Cluster Health Response Procedures

Cluster health indicates overall data availability. Yellow means some replicas are unassigned. Red means some primary shards are unassigned — data loss is possible. Both require immediate diagnosis and action.

**Yellow cluster diagnosis and response:**

```json
// Step 1: Identify unassigned shards
GET /_cat/shards?v&h=index,shard,prirep,state,unassigned.reason&s=state

// Step 2: Check allocation explanation
GET /_cluster/allocation/explain
{
  "index": "products",
  "shard": 0,
  "primary": false
}
// Common reasons:
// - "no valid shard copy" → node with replica is down
// - "node does not match allocation rules" → awareness or filter prevents allocation
// - "not enough nodes" → replicas > nodes - 1

// Step 3: Common fixes
// Not enough nodes for replicas:
PUT /products/_settings
{ "number_of_replicas": 0 }

// Disk watermark exceeded:
PUT /_cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.disk.watermark.low": "85%",
    "cluster.routing.allocation.disk.watermark.high": "90%"
  }
}
```

**Red cluster — emergency response:**

```json
// Step 1: Identify missing primary shards
GET /_cat/indices?v&health=red
GET /_cat/shards?v&h=index,shard,prirep,state,unassigned.reason&s=state

// Step 2: Check if node with primary is recoverable
GET /_cat/nodes?v

// Step 3: If node is permanently lost, allocate stale primary (LAST RESORT — may lose recent data)
POST /_cluster/reroute
{
  "commands": [
    {
      "allocate_stale_primary": {
        "index": "products",
        "shard": 0,
        "node": "data-2",
        "accept_data_loss": true
      }
    }
  ]
}
// WARNING: This may result in data loss — only use when the original node cannot recover
```

Proactive monitoring:

```json
// Set up alerting on cluster health
GET /_cluster/health?wait_for_status=green&timeout=30s
// Returns immediately if green, waits up to 30s otherwise
// Use in monitoring scripts: non-green status triggers alert
```

Reference: [Cluster health](https://www.elastic.co/guide/en/elasticsearch/reference/current/cluster-health.html)
