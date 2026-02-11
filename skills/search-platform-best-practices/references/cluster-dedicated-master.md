---
title: Deploy Minimum 3 Dedicated Master Nodes to Prevent Split-Brain
impact: CRITICAL
impactDescription: Prevents split-brain data corruption and ensures cluster availability during node failures
tags: cluster, master, split-brain, quorum, dedicated, high-availability
---

## Deploy Minimum 3 Dedicated Master Nodes to Prevent Split-Brain

Split-brain occurs when network partitions cause two groups of nodes to each elect their own master, leading to divergent cluster states and data corruption. Elasticsearch 7+ uses a quorum-based voting system that requires a majority of master-eligible nodes to agree, but this only works correctly with an odd number (3+) of dedicated master nodes.

**Incorrect (2 master-eligible nodes — split-brain risk):**

```yaml
# Only 2 master-eligible data nodes — quorum = 2, any network partition causes deadlock
# Node 1 (master-eligible + data)
node.roles: [master, data]

# Node 2 (master-eligible + data)
node.roles: [master, data]

# If the network between node-1 and node-2 fails:
# - Neither has a majority (need 2 of 2, but each only sees 1)
# - Cluster becomes unavailable
# OR with only 1 master-eligible node: single point of failure
```

**Incorrect (master role combined with data role — resource contention):**

```yaml
# Master-eligible nodes also serving as data nodes
node.roles: [master, data_hot]

# Heavy indexing or large aggregation causes GC pause on this node
# Master process cannot publish cluster state updates
# Other nodes suspect master is dead → unnecessary master election
# Shard rebalancing storm follows → cascade failure
```

**Correct (3 dedicated master nodes):**

```yaml
# Master-1 (dedicated — no data, no ingest)
node.name: master-1
node.roles: [master]
cluster.initial_master_nodes: ["master-1", "master-2", "master-3"]

# Master-2
node.name: master-2
node.roles: [master]

# Master-3
node.name: master-3
node.roles: [master]
```

```json
// Verify master node configuration
GET /_cat/nodes?v&h=name,node.role,master
// name      node.role master
// master-1  m         *
// master-2  m         -
// master-3  m         -
// data-1    d         -
// data-2    d         -

// Check voting configuration
GET /_cluster/state/metadata?filter_path=metadata.cluster_coordination
```

Quorum math:

| Master-eligible nodes | Quorum needed | Tolerates failures |
|----------------------|---------------|-------------------|
| 1 | 1 | 0 (no HA) |
| 2 | 2 | 0 (deadlock on partition) |
| **3** | **2** | **1** |
| 5 | 3 | 2 |
| 7 | 4 | 3 |

Dedicated master node sizing:
- **Heap**: 4-8GB (cluster state is small for most clusters)
- **CPU**: 2-4 cores (cluster state management is not CPU-intensive)
- **Disk**: Minimal (only stores cluster metadata)
- **Network**: Reliable, low-latency connectivity between all master nodes
- **JVM**: Same version as data nodes

Important: `cluster.initial_master_nodes` is only used for the first cluster bootstrap. Remove it from configuration after the cluster is formed to prevent accidental re-bootstrapping.

Reference: [Discovery and cluster formation](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-discovery.html)
