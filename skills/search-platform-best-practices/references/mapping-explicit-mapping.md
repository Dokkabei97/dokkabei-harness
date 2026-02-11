---
title: Disable Dynamic Mapping and Use dynamic: strict
impact: CRITICAL
impactDescription: Prevents field explosion, mapping conflicts, and uncontrolled schema drift in production
tags: mapping, dynamic, strict, schema-design, field-explosion
---

## Disable Dynamic Mapping and Use dynamic: strict

Dynamic mapping silently creates fields from any ingested document, leading to mapping explosions (thousands of unplanned fields), type conflicts, and degraded cluster performance. In production, every field must be intentionally designed.

**Incorrect (default dynamic mapping allows any field):**

```json
// Dynamic mapping is "true" by default — any new field is auto-mapped
PUT /orders
{
  "mappings": {
    "properties": {
      "order_id": { "type": "keyword" },
      "amount": { "type": "double" }
    }
  }
}

// Ingesting a document with unexpected fields silently creates new mappings
POST /orders/_doc
{
  "order_id": "ORD-001",
  "amount": 150.00,
  "customer_metadata": {
    "preference_a": "value",
    "preference_b": "value",
    "random_field_xyz": "value"
  }
}
// customer_metadata.* fields are all auto-mapped — mapping grows uncontrollably
```

**Correct (dynamic: strict rejects unmapped fields):**

```json
// strict mode rejects documents containing unmapped fields
PUT /orders
{
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "order_id": { "type": "keyword" },
      "amount": { "type": "double" },
      "status": { "type": "keyword" },
      "created_at": { "type": "date" }
    }
  }
}

// Attempting to index a document with an unmapped field returns an error
POST /orders/_doc
{
  "order_id": "ORD-001",
  "amount": 150.00,
  "unknown_field": "oops"
}
// Returns 400: "mapping set to strict, dynamic introduction of [unknown_field] ... is not allowed"
```

For subobjects that genuinely need flexibility (e.g., user-defined tags), use `dynamic: true` or `dynamic: runtime` at the subobject level only:

```json
PUT /orders
{
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "order_id": { "type": "keyword" },
      "amount": { "type": "double" },
      "tags": {
        "type": "object",
        "dynamic": "true"
      }
    }
  }
}
```

If you want to accept unknown fields without indexing them, use `dynamic: false` (stored in `_source` but not searchable) or `dynamic: runtime` (queryable on-demand without index overhead).

Reference: [Dynamic Mapping](https://www.elastic.co/guide/en/elasticsearch/reference/current/dynamic.html)
