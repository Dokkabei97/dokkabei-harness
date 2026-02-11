---
title: Use Runtime Fields for Schema-on-Read Without Reindexing
impact: LOW
impactDescription: Add computed fields at query time without reindexing or changing mappings
tags: advanced, runtime-fields, schema-on-read, computed, painless
---

## Use Runtime Fields for Schema-on-Read Without Reindexing

Runtime fields are computed at query time from `_source` or other fields. They enable schema-on-read — add, modify, or experiment with fields without reindexing.

**Correct (runtime field for computed value):**

```json
// Define runtime field in mapping
PUT /orders
{
  "mappings": {
    "runtime": {
      "price_with_tax": {
        "type": "double",
        "script": {
          "source": "emit(doc['price'].value * 1.1)"
        }
      },
      "day_of_week": {
        "type": "keyword",
        "script": {
          "source": "emit(doc['created_at'].value.dayOfWeekEnum.getDisplayName(TextStyle.FULL, Locale.ROOT))"
        }
      }
    },
    "properties": {
      "price": { "type": "double" },
      "created_at": { "type": "date" }
    }
  }
}

// Use runtime fields in queries, aggregations, and sorts
GET /orders/_search
{
  "query": {
    "range": { "price_with_tax": { "gte": 10000 } }
  },
  "aggs": {
    "by_day": { "terms": { "field": "day_of_week" } }
  }
}

// Or define runtime fields per-query (no mapping change needed)
GET /orders/_search
{
  "runtime_mappings": {
    "discount_amount": {
      "type": "double",
      "script": "emit(doc['original_price'].value - doc['price'].value)"
    }
  },
  "fields": ["discount_amount"],
  "query": { "range": { "discount_amount": { "gte": 5000 } } }
}
```

Use cases:
- Prototyping new fields before committing to mapping changes
- Computing derived values without reindexing
- Fixing data quality issues at query time
- A/B testing different field computations

Trade-off: Runtime fields are slower than indexed fields (computed on every query). For frequently used fields, index them properly after validation.

Reference: [Runtime fields](https://www.elastic.co/guide/en/elasticsearch/reference/current/runtime.html)
