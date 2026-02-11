---
title: Choose text vs keyword Type Based on Query Pattern
impact: CRITICAL
impactDescription: Eliminates wasted disk/memory on unnecessary analysis, 2-10x faster exact-match queries
tags: mapping, text, keyword, field-type, analysis
---

## Choose text vs keyword Type Based on Query Pattern

Using `text` where `keyword` is needed (or vice versa) wastes resources and produces wrong results. `text` fields are analyzed (tokenized) for full-text search; `keyword` fields store exact values for filtering, sorting, and aggregations.

**Incorrect (text type for exact-match field):**

```json
PUT /products
{
  "mappings": {
    "properties": {
      "status": { "type": "text" },
      "sku": { "type": "text" },
      "category_code": { "type": "text" }
    }
  }
}

// term query on analyzed text field — may return zero results
GET /products/_search
{
  "query": {
    "term": { "status": "In Stock" }
  }
}
// "In Stock" is analyzed to ["in", "stock"], so exact term "In Stock" never matches
```

**Correct (keyword for exact-match, text for full-text search):**

```json
PUT /products
{
  "mappings": {
    "properties": {
      "status": { "type": "keyword" },
      "sku": { "type": "keyword" },
      "category_code": { "type": "keyword" },
      "description": { "type": "text" }
    }
  }
}

// term query on keyword field — exact match works correctly
GET /products/_search
{
  "query": {
    "term": { "status": "In Stock" }
  }
}
```

Decision guide:

| Use Case | Type | Query |
|----------|------|-------|
| Filter/exact match (status, enum, ID) | `keyword` | `term`, `terms` |
| Sorting, aggregation | `keyword` | `sort`, `terms agg` |
| Full-text search (title, description) | `text` | `match`, `multi_match` |
| Both search and filter | multi-field | See `mapping-multi-field.md` |

Common pitfall: Elasticsearch's default dynamic mapping maps strings as both `text` and `keyword` (multi-field), which doubles storage. Explicit mapping avoids this waste for fields that need only one type.

Reference: [Field data types](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-types.html)
