---
title: Design ILM/ISM Policies with Clear Phase Transitions
impact: MEDIUM
impactDescription: Automates index lifecycle management, reducing manual operations and ensuring consistent data handling
tags: lifecycle, ilm, ism, policy, phase, automation
---

## Design ILM/ISM Policies with Clear Phase Transitions

Without lifecycle management, indices accumulate indefinitely, consuming storage and degrading cluster performance. ILM (Elasticsearch) / ISM (OpenSearch) policies automate phase transitions based on age, size, or document count.

**Incorrect (no lifecycle policy — manual index management):**

```json
// Indices accumulate forever
// Operations team must remember to delete old indices manually
// No automatic tiering — 3-year-old data sits on hot tier NVMe SSDs
```

**Correct (ILM policy with clear phases):**

```json
PUT /_ilm/policy/application-logs
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "40gb",
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
          "allocate": { "number_of_replicas": 1 },
          "set_priority": { "priority": 50 }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "allocate": { "number_of_replicas": 0 },
          "set_priority": { "priority": 0 }
        }
      },
      "frozen": {
        "min_age": "90d",
        "actions": {
          "searchable_snapshot": {
            "snapshot_repository": "s3_repo"
          }
        }
      },
      "delete": {
        "min_age": "365d",
        "actions": { "delete": {} }
      }
    }
  }
}

// Monitor ILM status
GET /logs-*/_ilm/explain?filter_path=indices.*.managed,indices.*.phase,indices.*.age
```

Reference: [Index lifecycle management](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-lifecycle-management.html)
