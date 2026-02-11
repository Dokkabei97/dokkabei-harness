---
title: Use Data Streams for Time-Series Data Instead of Manual Index Management
impact: MEDIUM
impactDescription: Simplifies time-series index management with automatic rollover and append-only semantics
tags: lifecycle, data-stream, time-series, rollover, append-only
---

## Use Data Streams for Time-Series Data Instead of Manual Index Management

Data streams (ES 7.9+) provide a built-in abstraction for append-only time-series data. They automatically handle backing index creation, rollover, and read/write routing, eliminating the need for manual alias management.

**Incorrect (manual alias management for time-series):**

```json
// Manual setup: create index, configure alias, track write index
PUT /logs-000001
{ "aliases": { "logs-write": { "is_write_index": true }, "logs-read": {} } }

// Must manually handle rollover triggers
POST /logs-write/_rollover
{ "conditions": { "max_primary_shard_size": "40gb" } }
// Easy to forget, error-prone, requires application awareness
```

**Correct (data stream — automatic management):**

```json
// Step 1: Create index template with data_stream enabled
PUT /_index_template/logs-template
{
  "index_patterns": ["logs-*"],
  "data_stream": {},
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.lifecycle.name": "logs-policy"
    },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "message": { "type": "text" },
        "level": { "type": "keyword" },
        "service": { "type": "keyword" }
      }
    }
  }
}

// Step 2: Index directly to the data stream name (auto-creates)
POST /logs-app/_doc
{
  "@timestamp": "2024-01-15T10:00:00Z",
  "message": "Application started",
  "level": "INFO",
  "service": "api-gateway"
}
// Data stream "logs-app" is automatically created
// Backing index ".ds-logs-app-2024.01.15-000001" is created

// Step 3: Search across all backing indices transparently
GET /logs-app/_search
{
  "query": { "match": { "service": "api-gateway" } }
}

// View backing indices
GET /_data_stream/logs-app
```

Data stream requirements:
- Documents must have a `@timestamp` field (or configured timestamp field)
- Append-only (no update/delete by document ID — use update_by_query for corrections)
- ILM/ISM handles rollover automatically

Reference: [Data streams](https://www.elastic.co/guide/en/elasticsearch/reference/current/data-streams.html)
