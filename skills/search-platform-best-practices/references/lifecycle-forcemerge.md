---
title: Force Merge Read-Only Indices to Optimize Segment Count
impact: MEDIUM
impactDescription: 20-30% faster search on read-only indices, reduced heap and file handle usage
tags: lifecycle, forcemerge, segment, optimization, read-only
---

## Force Merge Read-Only Indices to Optimize Segment Count

Active indices accumulate many small segments. Once an index becomes read-only (e.g., after rollover to warm tier), force merging reduces segments to 1, improving search speed and reducing resource usage.

**Incorrect (force merge on active write index):**

```json
// DON'T force merge indices that are still receiving writes
POST /logs-current/_forcemerge?max_num_segments=1
// This blocks new segments from being created efficiently
// New writes create new segments, immediately fragmenting again
// The merge itself competes with indexing for I/O
```

**Correct (force merge on read-only indices in warm/cold phase):**

```json
// First ensure the index is read-only
PUT /logs-2024-01/_settings
{ "index.blocks.write": true }

// Then force merge
POST /logs-2024-01/_forcemerge?max_num_segments=1

// Best practice: include in ILM warm phase
PUT /_ilm/policy/logs
{
  "policy": {
    "phases": {
      "warm": {
        "min_age": "7d",
        "actions": {
          "forcemerge": { "max_num_segments": 1 },
          "shrink": { "number_of_shards": 1 }
        }
      }
    }
  }
}
```

Monitor segment health:

```json
GET /_cat/segments/logs-2024-01?v&h=index,shard,segment,size
// Before force merge: 50+ segments
// After force merge: 1 segment per shard
```

Important: Force merge is I/O intensive. Schedule during off-peak hours or let ILM handle timing automatically.

Reference: [Force merge API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-forcemerge.html)
