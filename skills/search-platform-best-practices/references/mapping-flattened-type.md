---
title: Use Flattened Type for High-Cardinality Dynamic Fields
impact: HIGH
impactDescription: Prevents mapping explosion from thousands of dynamic keys, 10x fewer field mappings
tags: mapping, flattened, dynamic-fields, cardinality, labels
---

## Use Flattened Type for High-Cardinality Dynamic Fields

When a field contains user-defined keys (labels, tags, metadata, custom attributes), each unique key creates a new field mapping. This leads to mapping explosion, excessive memory consumption, and cluster instability. The `flattened` type indexes the entire object as keyword values without creating individual field mappings.

**Incorrect (object type with dynamic keys causes mapping explosion):**

```json
PUT /servers
{
  "mappings": {
    "properties": {
      "hostname": { "type": "keyword" },
      "labels": {
        "type": "object",
        "dynamic": "true"
      }
    }
  }
}

// Each server has different label keys
POST /servers/_bulk
{"index":{}}
{"hostname": "web-01", "labels": {"region": "ap-northeast-2", "team": "platform", "cost-center": "eng-123"}}
{"index":{}}
{"hostname": "web-02", "labels": {"region": "us-east-1", "env": "prod", "pci-compliant": "true"}}
{"index":{}}
{"hostname": "db-01", "labels": {"db-engine": "mysql", "backup-policy": "daily", "owner": "dba-team"}}

// After 10,000 servers with unique labels → thousands of mapped fields
// Cluster state grows, mapping updates become slow, risk of hitting field limit
```

**Correct (flattened type — single mapping entry for all keys):**

```json
PUT /servers
{
  "mappings": {
    "properties": {
      "hostname": { "type": "keyword" },
      "labels": {
        "type": "flattened"
      }
    }
  }
}

// Any key-value pair can be indexed without creating new mappings
POST /servers/_bulk
{"index":{}}
{"hostname": "web-01", "labels": {"region": "ap-northeast-2", "team": "platform", "cost-center": "eng-123"}}
{"index":{}}
{"hostname": "web-02", "labels": {"region": "us-east-1", "env": "prod", "pci-compliant": "true"}}

// Query specific key-value pair
GET /servers/_search
{
  "query": {
    "term": { "labels.region": "ap-northeast-2" }
  }
}

// Query for existence of any value under a key
GET /servers/_search
{
  "query": {
    "exists": { "field": "labels.team" }
  }
}
```

Limitations of `flattened` type:
- All values are treated as keyword (no full-text search, no numeric range queries)
- No individual field-level analyzers
- Aggregations work but only on keyword terms
- Cannot do `range` queries on numeric values stored in flattened fields

When to use `flattened` vs alternatives:

| Scenario | Recommendation |
|----------|---------------|
| Kubernetes labels, user-defined tags | `flattened` |
| Structured data with known schema | Explicit `object` mapping |
| Need full-text search on dynamic content | `dynamic: runtime` |
| Need numeric ranges on dynamic values | Runtime fields or explicit mapping |

Reference: [Flattened field type](https://www.elastic.co/guide/en/elasticsearch/reference/current/flattened.html)
