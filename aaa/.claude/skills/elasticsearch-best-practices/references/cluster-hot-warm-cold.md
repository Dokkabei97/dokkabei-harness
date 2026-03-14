---
title: "Implement Hot-Warm-Cold for Cost-Efficient Storage"
impact: HIGH
impactDescription: "50-70% storage cost reduction for time-series data"
tags: cluster, hot-warm-cold, tiered-storage, ILM, cost
---

## Implement Hot-Warm-Cold for Cost-Efficient Storage

Time-series data (logs, metrics, events) is accessed frequently when recent but rarely after days or weeks. Storing all data on expensive NVMe SSDs wastes budget, while storing everything on slow HDDs degrades query performance for recent data. A tiered hot-warm-cold architecture places data on the right hardware for its access pattern, reducing storage costs by 50-70% without sacrificing query performance for active data.

**Incorrect (all data on the same expensive SSD tier):**

```yaml
# elasticsearch.yml - Every node identical, no tier differentiation
cluster.name: logging-prod
node.name: data-1
node.roles: [ data ]
# All 500TB of logs on NVMe SSD across all nodes
# 90-day retention = 450TB of rarely-queried data on premium storage
# Monthly storage cost: ~$15,000+ for SSD that could be $3,000 on HDD
```

```json
// No ILM policy - indices grow until disk fills up
PUT /application-logs-2025.01.15
{
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 1
  }
}
// Manual index creation, no rollover, no tier migration
```

**Correct (tiered nodes with ILM-driven data migration):**

Step 1: Configure node attributes for each tier.

```yaml
# elasticsearch.yml - Hot Node (NVMe SSD, high CPU)
cluster.name: logging-prod
node.name: data-hot-1
node.roles: [ data_hot, data_content ]
# 32 CPU, 64GB RAM, 2TB NVMe SSD
# Handles active writes and recent queries (0-2 days)
```

```yaml
# elasticsearch.yml - Warm Node (large HDD, moderate CPU)
cluster.name: logging-prod
node.name: data-warm-1
node.roles: [ data_warm ]
# 16 CPU, 64GB RAM, 8TB HDD
# Read-only, force-merged older data (2-30 days)
```

```yaml
# elasticsearch.yml - Cold Node (minimal resources, large HDD or shared storage)
cluster.name: logging-prod
node.name: data-cold-1
node.roles: [ data_cold ]
# 8 CPU, 32GB RAM, 16TB HDD or mounted shared filesystem
# Rarely queried data (30-90 days), minimal replicas
```

Step 2: Create an ILM policy that moves data through tiers.

```json
PUT _ilm/policy/logging-tiered-policy
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "50gb",
            "max_age": "1d"
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "2d",
        "actions": {
          "shrink": {
            "number_of_shards": 1
          },
          "forcemerge": {
            "max_num_segments": 1
          },
          "set_priority": {
            "priority": 50
          }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "searchable_snapshot": {
            "snapshot_repository": "logging-snapshots"
          },
          "set_priority": {
            "priority": 0
          }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

Step 3: Create a composable index template that ties it together.

```json
PUT _index_template/logging-template
{
  "index_patterns": ["application-logs-*"],
  "data_stream": {},
  "template": {
    "settings": {
      "number_of_shards": 5,
      "number_of_replicas": 1,
      "index.lifecycle.name": "logging-tiered-policy",
      "index.routing.allocation.include._tier_preference": "data_hot"
    }
  },
  "priority": 200
}
```

**Cost comparison for 500TB time-series data (90-day retention):**

| Tier | Data Volume | Storage Type | Monthly Cost (est.) |
|------|-------------|-------------|---------------------|
| Hot (0-2d) | ~11TB | NVMe SSD | ~$550 |
| Warm (2-30d) | ~155TB | HDD | ~$1,550 |
| Cold (30-90d) | ~334TB | Searchable Snapshot | ~$1,000 |
| **Total (tiered)** | **500TB** | **Mixed** | **~$3,100** |
| **Total (all SSD)** | **500TB** | **All NVMe** | **~$15,000** |

**Key rules:**

- Hot tier handles active writes and the most recent queries — always use SSDs.
- Warm tier data should be read-only and force-merged to 1 segment per shard for maximum query efficiency.
- Cold tier can use searchable snapshots (ES 7.10+) to dramatically reduce local storage needs.
- Always set `index.routing.allocation.include._tier_preference` instead of legacy `node.attr` for ES 8.x.
- Include a `delete` phase to prevent unbounded storage growth.

Reference:
[Data Tiers](https://www.elastic.co/guide/en/elasticsearch/reference/current/data-tiers.html)
[ILM: Manage the Index Lifecycle](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-lifecycle-management.html)
