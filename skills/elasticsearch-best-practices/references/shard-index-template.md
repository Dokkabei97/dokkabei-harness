---
title: "Use Index Templates and ILM Rollover for Time-Series"
impact: MEDIUM-HIGH
impactDescription: "Automated shard lifecycle management, prevents unbounded index growth"
tags: shard, index-template, ILM, rollover, time-series
---

## Use Index Templates and ILM Rollover for Time-Series

Time-series data (logs, metrics, events, audit trails) grows continuously and indefinitely. Without a rollover strategy, a single index grows until shards become too large for efficient recovery and search, and old data cannot be independently managed or deleted. Composable index templates with ILM rollover automatically create new indices at size or age thresholds, maintaining optimal shard sizes and enabling tier-based data management.

**Incorrect (single index growing forever with no rollover):**

```json
// Creating a single index for all application logs
PUT /application-logs
{
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 1
  }
}

// Indexing documents indefinitely into the same index
POST /application-logs/_doc
{
  "@timestamp": "2025-06-15T10:30:00Z",
  "level": "ERROR",
  "service": "payment-service",
  "message": "Connection timeout to payment gateway"
}

// Problems:
// - Index grows to terabytes with no way to split
// - Cannot delete old data without reindexing
// - Shard sizes become 200GB+ → recovery takes hours
// - No way to move old data to cheaper storage tiers
// - Mapping changes require full reindex of entire dataset
```

**Correct (composable index template + ILM rollover with data streams):**

Step 1: Create an ILM policy with size-based and age-based rollover.

```json
PUT _ilm/policy/application-logs-policy
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "50gb",
            "max_age": "1d",
            "max_docs": 500000000
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "3d",
        "actions": {
          "shrink": {
            "number_of_shards": 1
          },
          "forcemerge": {
            "max_num_segments": 1
          },
          "allocate": {
            "number_of_replicas": 1
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
            "snapshot_repository": "logs-snapshots"
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

Step 2: Create a component template for shared settings.

```json
PUT _component_template/application-logs-settings
{
  "template": {
    "settings": {
      "number_of_shards": 5,
      "number_of_replicas": 1,
      "index.lifecycle.name": "application-logs-policy",
      "index.routing.allocation.include._tier_preference": "data_hot",
      "index.codec": "best_compression"
    }
  }
}
```

```json
PUT _component_template/application-logs-mappings
{
  "template": {
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "level": { "type": "keyword" },
        "service": { "type": "keyword" },
        "message": { "type": "text" },
        "trace_id": { "type": "keyword" },
        "duration_ms": { "type": "long" }
      }
    }
  }
}
```

Step 3: Create a composable index template using data streams (ES 7.9+).

```json
PUT _index_template/application-logs-template
{
  "index_patterns": ["application-logs"],
  "data_stream": {},
  "composed_of": [
    "application-logs-settings",
    "application-logs-mappings"
  ],
  "priority": 200,
  "_meta": {
    "description": "Template for application log data stream with ILM rollover"
  }
}
```

Step 4: Index documents using the data stream name.

```json
// Data stream auto-creates backing indices on first write
POST /application-logs/_doc
{
  "@timestamp": "2025-06-15T10:30:00Z",
  "level": "ERROR",
  "service": "payment-service",
  "message": "Connection timeout to payment gateway",
  "trace_id": "abc-123-def-456",
  "duration_ms": 30000
}

// ILM automatically rolls over when:
// - Any primary shard reaches 50GB, OR
// - Index age reaches 1 day, OR
// - Document count reaches 500 million
// New backing index: .ds-application-logs-2025.06.16-000002
```

**Verification and monitoring:**

```json
// Check data stream and its backing indices
GET _data_stream/application-logs

// Monitor ILM status for all managed indices
GET /application-logs/_ilm/explain?filter_path=indices.*.managed,indices.*.phase,indices.*.age

// Check rollover conditions
GET _cat/indices/.ds-application-logs-*?v&h=index,pri,docs.count,store.size,creation.date.string&s=creation.date
```

**Data stream vs. classic rollover alias:**

| Feature | Data Stream (ES 7.9+) | Rollover Alias (Legacy) |
|---------|----------------------|------------------------|
| Setup complexity | Lower (auto-managed) | Higher (manual alias + bootstrap) |
| Append-only | Yes (enforced) | No (allows updates/deletes) |
| `@timestamp` required | Yes | No |
| Update/delete documents | Via `_update_by_query` only | Direct operations |
| Recommended for | Logs, metrics, events | Mutable time-series data |

**Key rules:**

- Use data streams (ES 7.9+) for append-only time-series data — simpler setup and built-in conventions.
- Set `max_primary_shard_size: 50gb` as the primary rollover condition to maintain optimal shard sizes.
- Add `max_age: 1d` as a secondary condition so that even low-volume indices roll over daily for consistent ILM progression.
- Use component templates to share settings and mappings across multiple data streams.
- Always include a `delete` phase to prevent unbounded storage growth.
- Use `priority` on index templates to control which template applies when patterns overlap.

Reference:
[Data Streams](https://www.elastic.co/guide/en/elasticsearch/reference/current/data-streams.html)
[Index Templates](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-templates.html)
[ILM Rollover](https://www.elastic.co/guide/en/elasticsearch/reference/current/ilm-rollover.html)
