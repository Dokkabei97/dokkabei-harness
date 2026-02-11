---
title: Separate Node Roles for Master, Data, Coordinating, and Ingest
impact: CRITICAL
impactDescription: Prevents master instability, enables independent scaling, eliminates resource contention
tags: cluster, node-roles, master, data, coordinating, ingest, architecture
---

## Separate Node Roles for Master, Data, Coordinating, and Ingest

Running all roles on every node (the default) means a heavy indexing or search workload can starve the master process, causing cluster instability, delayed shard allocation, and potential split-brain. In production, dedicate nodes to specific roles.

**Incorrect (all roles on every node):**

```yaml
# elasticsearch.yml — default: every node does everything
# node.roles: [master, data, data_content, data_hot, data_warm, ingest, ml, remote_cluster_client, transform]

# 3-node cluster where every node is master + data + ingest
# Heavy indexing on node-1 → master process starves → cluster state updates delayed
# Large aggregation on node-2 → GC pause → master thinks node is dead → shard rebalancing storm
```

**Correct (dedicated node roles):**

```yaml
# Dedicated master node (3 nodes minimum)
# elasticsearch.yml for master-1, master-2, master-3
node.roles: [master]
# Small heap (4-8GB), minimal disk — only manages cluster state

# Dedicated data nodes (scale based on data volume)
# elasticsearch.yml for data-1 through data-N
node.roles: [data_content, data_hot]
# Large heap (up to 31GB), high-performance SSD, bulk of storage

# Dedicated coordinating-only nodes (load balancer target)
# elasticsearch.yml for coord-1, coord-2
node.roles: []
# Medium heap (16-31GB) — aggregates shard results, handles scatter-gather
# Absorbs the sort/merge/reduce phase, protecting data nodes

# Dedicated ingest nodes (for heavy pipeline processing)
# elasticsearch.yml for ingest-1, ingest-2
node.roles: [ingest]
# CPU-heavy workloads: grok, enrichment, attachment processing
```

Recommended cluster topology for production:

```
                    ┌─────────────┐
                    │  Load       │
                    │  Balancer   │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────┴─────┐ ┌───┴───┐ ┌─────┴─────┐
        │ Coord-1   │ │Coord-2│ │ Coord-3   │
        │ roles: [] │ │       │ │           │
        └─────┬─────┘ └───┬───┘ └─────┬─────┘
              │            │            │
    ┌─────────┼────────────┼────────────┼─────────┐
    │         │            │            │         │
┌───┴──┐ ┌───┴──┐ ┌───────┴──┐ ┌──────┴┐ ┌──────┴┐
│Data-1│ │Data-2│ │ Data-3   │ │Data-4 │ │Data-5 │
│ hot  │ │ hot  │ │  warm    │ │ warm  │ │ cold  │
└──────┘ └──────┘ └──────────┘ └───────┘ └───────┘

    ┌─────────┐ ┌─────────┐ ┌─────────┐
    │Master-1 │ │Master-2 │ │Master-3 │
    │(elected)│ │(standby)│ │(standby)│
    └─────────┘ └─────────┘ └─────────┘
```

| Role | CPU | Memory | Storage | Count |
|------|-----|--------|---------|-------|
| Master | Low | 4-8GB heap | Minimal | 3 (always odd) |
| Data (hot) | High | 31GB heap | NVMe SSD | Scale with data |
| Data (warm/cold) | Medium | 31GB heap | HDD/cheaper SSD | Scale with retention |
| Coordinating | Medium | 16-31GB heap | Minimal | 2-3 |
| Ingest | High CPU | 8-16GB heap | Minimal | 2+ (if pipelines used) |

Reference: [Node roles](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html)
