---
title: Implement Hot-Warm-Cold Architecture for Cost-Effective Data Tiering
impact: HIGH
impactDescription: 50-70% storage cost reduction by moving aging data to cheaper hardware tiers
tags: cluster, hot-warm-cold, tiering, data-lifecycle, storage, cost
---

## Implement Hot-Warm-Cold Architecture for Cost-Effective Data Tiering

Not all data needs the same performance. Recent, frequently searched data belongs on fast NVMe SSDs (hot tier), while older data can move to cheaper SATA SSDs (warm) or HDDs (cold). This architecture reduces infrastructure costs by 50-70% without sacrificing search quality for current data.

**Incorrect (all data on same tier — expensive and wasteful):**

```yaml
# All nodes use NVMe SSD — 90-day-old logs get the same expensive storage as today's data
# $2000/TB NVMe for data that's searched once a month
# No differentiation between hot and cold data
node.roles: [data]
# Every index competes for the same high-performance resources
```

**Correct (data tiered by access pattern):**

```yaml
# Hot node — NVMe SSD, high CPU, high RAM
node.name: data-hot-1
node.roles: [data_hot, data_content]
node.attr.data: hot

# Warm node — SATA SSD, moderate CPU, moderate RAM
node.name: data-warm-1
node.roles: [data_warm]
node.attr.data: warm

# Cold node — HDD, low CPU, lower RAM (or searchable snapshots)
node.name: data-cold-1
node.roles: [data_cold]
node.attr.data: cold
```

```json
// Configure ILM policy to automatically move data between tiers
PUT /_ilm/policy/logs-lifecycle
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
          "set_priority": { "priority": 100 }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 },
          "set_priority": { "priority": 50 },
          "allocate": {
            "number_of_replicas": 1
          }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "set_priority": { "priority": 0 },
          "allocate": {
            "number_of_replicas": 0
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

// Apply ILM policy via index template
PUT /_index_template/logs-template
{
  "index_patterns": ["logs-*"],
  "template": {
    "settings": {
      "index.lifecycle.name": "logs-lifecycle",
      "index.lifecycle.rollover_alias": "logs-write",
      "index.routing.allocation.include._tier_preference": "data_hot"
    }
  }
}
```

Tier comparison:

| Tier | Storage | Cost | Search Latency | Use Case |
|------|---------|------|----------------|----------|
| Hot | NVMe SSD | $$$ | <100ms | Active writes, real-time search |
| Warm | SATA SSD | $$ | 100-500ms | Recent historical, moderate search |
| Cold | HDD | $ | 500ms-2s | Compliance, rare search |
| Frozen | Object store (S3) | ¢ | 2-10s | Archive, searchable snapshots |

For Elasticsearch 7.12+, use `_tier_preference` for automatic tier-based allocation:

```json
// ES automatically routes to the preferred tier
PUT /my-index/_settings
{
  "index.routing.allocation.include._tier_preference": "data_warm,data_hot"
}
// Prefers warm tier; falls back to hot if warm is unavailable
```

Reference: [Data tiers](https://www.elastic.co/guide/en/elasticsearch/reference/current/data-tiers.html), [ILM](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-lifecycle-management.html)
