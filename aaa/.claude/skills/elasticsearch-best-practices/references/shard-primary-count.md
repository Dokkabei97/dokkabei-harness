---
title: "Calculate Primary Shard Count from Data Volume"
impact: HIGH
impactDescription: "Balanced search parallelism across data nodes"
tags: shard, primary-count, capacity-planning, parallelism
---

## Calculate Primary Shard Count from Data Volume

Primary shard count determines search parallelism and data distribution across nodes. Too few shards underutilize cluster capacity (one node does all the work), while too many create coordination overhead and bloat cluster state. The optimal count considers data volume, node count, and target shard size to ensure even distribution and maximum query throughput.

**Incorrect (default 1 primary for a growing index):**

```json
// 1TB index on a 10-node cluster with default shard count
PUT /product-catalog
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 1
  }
}
// Result: Only 2 nodes utilized (1 primary + 1 replica)
// - 8 of 10 data nodes sit idle during searches on this index
// - Single 1TB shard: extremely slow recovery, no parallelism
// - Search latency: 5-10 seconds for complex queries
```

```json
// Opposite: Blindly setting 100 shards regardless of data size
PUT /product-catalog
{
  "settings": {
    "number_of_shards": 100,
    "number_of_replicas": 1
  }
}
// 200 total shards for 50GB of data
// - Each shard is only 500MB → wasted overhead
// - Fan-out to 100 shards per query → coordination bottleneck
// - 200 shards consume master state memory unnecessarily
```

**Correct (calculate from data volume and node count):**

```
Shard count formula:

  primary_shards = max(
    ceil(data_volume / target_shard_size),
    data_node_count                         ← ensures at least 1 shard per node
  )

  Where target_shard_size = 30-50GB

Constraints:
  - primary_shards should be a multiple of data_node_count (for even distribution)
  - total_shards (primary + replica) should not exceed 1000 per node
```

**Worked example: 1TB product catalog on 10 data nodes**

```
Step 1: Calculate minimum shards from data volume
  primary_shards = ceil(1024GB / 40GB) = 26

Step 2: Round up to nearest multiple of data_node_count
  next_multiple_of_10 = 30

Step 3: Verify shard size is still in range
  1024GB / 30 shards = ~34GB per shard ✓ (within 30-50GB range)

Step 4: Verify total shards per node
  total_shards = 30 primary + 30 replica = 60
  shards_per_node = 60 / 10 = 6 per node ✓ (well under 1000)

Result: 30 primary shards, 1 replica
```

```json
PUT /product-catalog
{
  "settings": {
    "number_of_shards": 30,
    "number_of_replicas": 1
  }
}
// 30 primary shards × ~34GB each = ~1TB
// 3 primary shards per data node → balanced distribution
// Each search parallelizes across 30 shards
// Search latency: <500ms for the same complex queries
```

**Sizing reference for common scenarios:**

| Data Volume | Data Nodes | Target Shard Size | Primary Shards | Shards/Node (1 replica) |
|------------|-----------|-------------------|----------------|------------------------|
| 50GB | 3 | 50GB | 3 | 2 |
| 200GB | 5 | 40GB | 5 | 2 |
| 500GB | 5 | 40GB | 15 | 6 |
| 1TB | 10 | 34GB | 30 | 6 |
| 5TB | 20 | 50GB | 100 | 10 |
| 10TB | 30 | 50GB | 210 | 14 |

**Verification after index creation:**

```json
// Verify shard distribution across nodes
GET _cat/shards/product-catalog?v&h=index,shard,prirep,state,store,node&s=shard

// Check that shards are evenly distributed
GET _cat/allocation?v&h=node,shards,disk.indices,disk.percent

// Verify no unassigned shards
GET _cluster/health/product-catalog?filter_path=status,active_primary_shards,unassigned_shards
```

**Key rules:**

- Calculate primary shards as `ceil(data_volume / target_shard_size)`, then round up to a multiple of node count.
- Ensure at least 1 primary shard per data node to utilize full cluster parallelism.
- Account for data growth: if 500GB today will be 1TB in 6 months, plan for 1TB now (shards cannot be changed later).
- For search-heavy workloads (1000+ QPS), consider higher replica counts — each replica also serves search requests.
- Reindex or use the shrink/split API if your initial shard count estimate proves wrong.

Reference:
[Size Your Shards](https://www.elastic.co/guide/en/elasticsearch/reference/current/size-your-shards.html)
