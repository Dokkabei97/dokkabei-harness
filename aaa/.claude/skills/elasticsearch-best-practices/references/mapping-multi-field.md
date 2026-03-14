---
title: Use Multi-Fields for Search + Filtering on Same Field
impact: HIGH
impactDescription: Single field definition handles both full-text search and exact filtering/sorting
tags: mapping, multi-field, text, keyword
---

## Use Multi-Fields for Search + Filtering on Same Field

When the same field needs both full-text search (analyzed `text`) and exact match filtering, sorting, or aggregation (unanalyzed `keyword`), use multi-fields instead of creating separate fields. Multi-fields index the same source data in multiple ways under a single field definition.

**Incorrect (separate fields for different query types):**

```json
// Two separate fields from the same source data
// Application must populate both → sync issues, doubled mapping complexity
PUT /products
{
  "mappings": {
    "properties": {
      "product_name": { "type": "text" },
      "product_name_keyword": { "type": "keyword" },
      "brand": { "type": "text" },
      "brand_exact": { "type": "keyword" }
    }
  }
}
```

**Correct (multi-field mapping with .keyword sub-field):**

```json
// Single source field with multiple indexing strategies
// name → analyzed text for full-text search
// name.keyword → exact value for filtering, sorting, aggregation
PUT /products
{
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "fields": {
          "keyword": {
            "type": "keyword",
            "ignore_above": 256
          }
        }
      },
      "brand": {
        "type": "text",
        "fields": {
          "keyword": {
            "type": "keyword"
          }
        }
      },
      "category": { "type": "keyword" },
      "price": { "type": "double" }
    }
  }
}
```

**Query using both sub-fields:**

```json
// match on "name" (full-text) + terms agg on "name.keyword" (exact)
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "name": "wireless headphones" } }
      ],
      "filter": [
        { "term": { "brand.keyword": "Sony" } }
      ]
    }
  },
  "aggs": {
    "top_brands": {
      "terms": { "field": "brand.keyword", "size": 10 }
    }
  },
  "sort": [
    { "_score": "desc" },
    { "name.keyword": "asc" }
  ]
}
```

Set `ignore_above: 256` on keyword sub-fields to skip indexing excessively long values (descriptions, body text) that are unsuitable for exact matching. Fields purely for filtering that never need full-text search should be plain `keyword` type — multi-fields add index size overhead.

Reference: [Multi-fields](https://www.elastic.co/guide/en/elasticsearch/reference/current/multi-fields.html)
