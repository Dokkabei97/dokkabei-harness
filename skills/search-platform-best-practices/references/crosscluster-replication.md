---
title: Use Cross-Cluster Replication for Disaster Recovery and Local Read Performance
impact: MEDIUM
impactDescription: Provides near-real-time data replication for DR and reduced read latency in remote regions
tags: crosscluster, ccr, replication, disaster-recovery, multi-region
---

## Use Cross-Cluster Replication for Disaster Recovery and Local Read Performance

Cross-cluster replication (CCR) replicates indices from a leader cluster to one or more follower clusters in near-real-time. This provides disaster recovery capability and local read performance for distributed teams.

**Incorrect (manual periodic reindex between clusters):**

```json
// Manual nightly reindex from production to DR cluster
// 24-hour RPO (Recovery Point Objective) — unacceptable for many workloads
// Reindex is resource-intensive and not incremental
```

**Correct (CCR for near-real-time replication):**

```json
// Step 1: Configure remote cluster on follower
PUT /_cluster/settings
{
  "persistent": {
    "cluster.remote.leader_cluster": {
      "seeds": ["leader-node1:9300", "leader-node2:9300"]
    }
  }
}

// Step 2: Create follower index (replicates a specific leader index)
PUT /products-replica/_ccr/follow
{
  "remote_cluster": "leader_cluster",
  "leader_index": "products"
}

// Step 3: Or use auto-follow patterns for automatic replication of new indices
PUT /_ccr/auto_follow/logs-follow
{
  "remote_cluster": "leader_cluster",
  "leader_index_patterns": ["logs-*"],
  "follow_index_pattern": "{{leader_index}}-replica"
}

// Monitor replication status
GET /products-replica/_ccr/stats
// Check "operations_written" and "time_since_last_read" for lag
```

CCR characteristics:
- **Near-real-time**: Sub-second replication lag under normal conditions
- **Read-only followers**: Follower indices cannot accept writes
- **Automatic catch-up**: If connection drops, follower catches up automatically on reconnection
- **Index-level granularity**: Replicate only specific indices

Use cases:

| Scenario | Configuration |
|----------|-------------|
| Disaster Recovery | Leader in primary DC, follower in DR DC |
| Geo-distributed reads | Followers in each region for local read latency |
| Reporting isolation | Follower cluster for analytics, leader for production |

Reference: [Cross-cluster replication](https://www.elastic.co/guide/en/elasticsearch/reference/current/xpack-ccr.html)
