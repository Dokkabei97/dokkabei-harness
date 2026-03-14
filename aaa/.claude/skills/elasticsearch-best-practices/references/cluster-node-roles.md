---
title: "Separate Node Roles for Stability at Scale"
impact: CRITICAL
impactDescription: "Prevents cluster instability and master election failures"
tags: cluster, node-roles, master, data, architecture
---

## Separate Node Roles for Stability at Scale

When all nodes share every role (master + data + ingest), a heavy indexing or search spike on a data node can starve the master process of CPU and memory, triggering master election failures and potential cluster-wide outages. Dedicated roles isolate failure domains so that master stability is never compromised by data workloads.

**Incorrect (all nodes with all roles, no role separation):**

```yaml
# elasticsearch.yml - same config on every node
# Default: all roles enabled, master competes with data for resources
cluster.name: ecommerce-prod
node.name: node-1
# node.roles not set → defaults to all roles
# On a 10-node cluster, any heavy query can destabilize master election
```

In this configuration, a single runaway aggregation or bulk indexing burst can cause GC pauses on a node that is also acting as master, leading to master election timeouts and potential split-brain scenarios.

**Correct (dedicated master, data, and coordinating nodes):**

```yaml
# elasticsearch.yml - Dedicated Master Node (deploy exactly 3)
cluster.name: ecommerce-prod
node.name: master-1
node.roles: [ master ]
# Lightweight: 4 CPU, 8GB RAM is sufficient
# 3 dedicated masters ensure quorum (2 of 3) survives single node failure
```

```yaml
# elasticsearch.yml - Dedicated Data Node
cluster.name: ecommerce-prod
node.name: data-hot-1
node.roles: [ data_hot ]
# Heavy resources: 32+ CPU, 64GB RAM, NVMe SSD
# Handles indexing and search execution
```

```yaml
# elasticsearch.yml - Dedicated Warm Data Node
cluster.name: ecommerce-prod
node.name: data-warm-1
node.roles: [ data_warm ]
# Moderate resources: 16 CPU, 64GB RAM, large HDD
# Read-only older data, force-merged segments
```

```yaml
# elasticsearch.yml - Dedicated Coordinating Node (search load balancer)
cluster.name: ecommerce-prod
node.name: coord-1
node.roles: [ ]
# Empty roles list = coordinating-only
# Handles scatter-gather, aggregation reduction, and client connections
# 16+ CPU, 32GB RAM for merge-sorting large result sets
```

**Minimum production topology for enterprise (10+ nodes):**

| Role | Count | CPU | RAM | Storage | Purpose |
|------|-------|-----|-----|---------|---------|
| Master-eligible | 3 | 4 | 8GB | 10GB SSD | Cluster state, shard allocation |
| Data (hot) | 3+ | 32+ | 64GB | NVMe SSD | Active indexing and search |
| Data (warm) | 2+ | 16 | 64GB | Large HDD | Read-only older data |
| Coordinating | 2+ | 16 | 32GB | Minimal | Query routing, result reduction |
| Ingest | 2+ | 16 | 16GB | Minimal | Pipeline processing (if needed) |

**Key rules:**

- Always deploy exactly 3 dedicated master nodes for quorum. Never 2 (no fault tolerance) or an even number (split-brain risk).
- Never co-locate master and data roles in production clusters with 10+ nodes.
- Coordinating-only nodes protect data nodes from expensive scatter-gather operations on high-QPS clusters (1000+ QPS).
- Use `cluster.routing.allocation.awareness.attributes` to spread replicas across availability zones.

Reference:
[Node Roles](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html)
