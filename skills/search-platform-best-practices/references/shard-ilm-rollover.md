---
title: Use ILM/ISM with Automatic Rollover for Time-Series Data
impact: HIGH
impactDescription: Automates right-sized shard creation, prevents unbounded index growth
tags: shard, ilm, ism, rollover, time-series, automation
---

## Use ILM/ISM with Automatic Rollover for Time-Series Data

Manually creating daily/weekly indices leads to unpredictable shard sizes. ILM (Elasticsearch) or ISM (OpenSearch) automatically rolls over indices based on size, age, or document count, ensuring consistently right-sized shards.

**Incorrect (manual daily index creation — inconsistent shard sizes):**

```json
// Application creates daily indices directly
PUT /logs-2024-01-01
{ "settings": { "number_of_shards": 3 } }

PUT /logs-2024-01-02
{ "settings": { "number_of_shards": 3 } }

// Weekdays: 50GB/day → 3 shards × ~17GB each (ok)
// Weekends: 5GB/day → 3 shards × ~1.7GB each (micro-shards, wasteful)
// Black Friday: 500GB/day → 3 shards × ~167GB each (mega-shards, dangerous)
```

**Correct (ILM rollover based on shard size):**

```json
// Step 1: Define ILM policy
PUT /_ilm/policy/logs-policy
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "40gb",
            "max_age": "1d",
            "max_docs": 200000000
          },
          "set_priority": { "priority": 100 }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 },
          "set_priority": { "priority": 50 }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": { "delete": {} }
      }
    }
  }
}

// Step 2: Create index template with ILM
PUT /_index_template/logs-template
{
  "index_patterns": ["logs-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.lifecycle.name": "logs-policy",
      "index.lifecycle.rollover_alias": "logs-write"
    }
  }
}

// Step 3: Bootstrap the first index with write alias
PUT /logs-000001
{
  "aliases": {
    "logs-write": { "is_write_index": true },
    "logs-read": {}
  }
}

// Application writes to alias — ILM handles rollover automatically
POST /logs-write/_doc
{ "timestamp": "2024-01-15T10:00:00Z", "level": "ERROR", "message": "Connection refused" }
```

For OpenSearch, use ISM (Index State Management):

```json
PUT /_plugins/_ism/policies/logs-policy
{
  "policy": {
    "description": "Logs lifecycle management",
    "default_state": "hot",
    "states": [
      {
        "name": "hot",
        "actions": [
          {
            "rollover": {
              "min_primary_shard_size": "40gb",
              "min_index_age": "1d"
            }
          }
        ],
        "transitions": [
          { "state_name": "warm", "conditions": { "min_index_age": "7d" } }
        ]
      },
      {
        "name": "warm",
        "actions": [
          { "force_merge": { "max_num_segments": 1 } }
        ],
        "transitions": [
          { "state_name": "delete", "conditions": { "min_index_age": "90d" } }
        ]
      },
      {
        "name": "delete",
        "actions": [{ "delete": {} }]
      }
    ],
    "ism_template": [{ "index_patterns": ["logs-*"] }]
  }
}
```

Alternatively, use Data Streams (ES 7.9+) for simpler time-series management:

```json
// Data streams handle rollover index naming automatically
PUT /_index_template/logs-ds
{
  "index_patterns": ["logs-*"],
  "data_stream": {},
  "template": {
    "settings": {
      "index.lifecycle.name": "logs-policy"
    }
  }
}

// Create data stream by indexing
POST /logs-app/_doc
{ "@timestamp": "2024-01-15T10:00:00Z", "message": "Application started" }
```

Reference: [ILM Rollover](https://www.elastic.co/guide/en/elasticsearch/reference/current/ilm-rollover.html), [Data Streams](https://www.elastic.co/guide/en/elasticsearch/reference/current/data-streams.html)
