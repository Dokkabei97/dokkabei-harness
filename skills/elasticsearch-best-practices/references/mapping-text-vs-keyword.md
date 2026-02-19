---
title: Choose text vs keyword Based on Query Pattern
impact: CRITICAL
impactDescription: Wrong field type causes failed queries and 5-10x unnecessary index size
tags: mapping, text, keyword, field-type
---

## Choose text vs keyword Based on Query Pattern

Choosing the wrong field type leads to either broken queries or wasted resources. `text` fields are analyzed into tokens for full-text search; `keyword` fields store the exact value for filtering, sorting, and aggregations.

**Incorrect (text for categorical fields, keyword for searchable content):**

```json
// text on status → analyzed into tokens, aggregation returns ["in", "stock"] instead of ["in_stock"]
// keyword on description → no tokenization, match query fails to find partial terms
PUT /products
{
  "mappings": {
    "properties": {
      "name": { "type": "keyword" },
      "description": { "type": "keyword" },
      "status": { "type": "text" },
      "category": { "type": "text" }
    }
  }
}
```

**Correct (text for searchable content, keyword for exact match/agg/sort):**

```json
// text: inverted index with analyzer → full-text search with relevance scoring
// keyword: single token, doc_values → exact match, terms agg, sorting
PUT /products
{
  "mappings": {
    "properties": {
      "name": { "type": "text" },
      "description": { "type": "text" },
      "status": { "type": "keyword" },
      "category": { "type": "keyword" },
      "price": { "type": "double" },
      "created_at": { "type": "date" }
    }
  }
}
```

**Decision criteria:**

| Question | text | keyword |
|----------|------|---------|
| Need full-text search? | Yes | No |
| Need exact match filter? | No (use .keyword) | Yes |
| Need sorting? | No | Yes |
| Need aggregation? | No (use .keyword) | Yes |
| Field values are enumerable? | No | Yes |
| Typical examples | product name, description, body | status, category, email, tags, country_code |

When you need both full-text search AND exact filtering on the same field, use multi-fields (see `mapping-multi-field.md`).

Reference: [Field data types](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-types.html)
