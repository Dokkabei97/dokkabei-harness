---
title: Use copy_to for Multi-Field Search Instead of multi_match on Many Fields
impact: HIGH
impactDescription: 3-10x faster multi-field search by querying a single combined field
tags: query, copy_to, multi-field, search, performance
---

## Use copy_to for Multi-Field Search Instead of multi_match on Many Fields

`multi_match` generates a query per field and combines scores, which becomes expensive as the number of fields grows. `copy_to` copies values from multiple fields into a single combined field at index time, enabling a simple `match` query on one field.

**Incorrect (multi_match across many fields):**

```json
PUT /restaurants
{
  "mappings": {
    "properties": {
      "name": { "type": "text" },
      "description": { "type": "text" },
      "menu_items": { "type": "text" },
      "address": { "type": "text" },
      "tags": { "type": "text" },
      "cuisine_type": { "type": "text" }
    }
  }
}

// Searching across 6 fields — generates 6 sub-queries
GET /restaurants/_search
{
  "query": {
    "multi_match": {
      "query": "강남 이탈리안 파스타",
      "fields": ["name^3", "description", "menu_items^2", "address", "tags", "cuisine_type"],
      "type": "best_fields"
    }
  }
}
// Each field generates its own BM25 score calculation
// With 5 shards × 6 fields = 30 sub-queries across the cluster
```

**Correct (copy_to combined field):**

```json
PUT /restaurants
{
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "copy_to": "search_all"
      },
      "description": {
        "type": "text",
        "copy_to": "search_all"
      },
      "menu_items": {
        "type": "text",
        "copy_to": "search_all"
      },
      "address": {
        "type": "text",
        "copy_to": "search_all"
      },
      "tags": {
        "type": "text",
        "copy_to": "search_all"
      },
      "cuisine_type": {
        "type": "text",
        "copy_to": "search_all"
      },
      "search_all": {
        "type": "text",
        "analyzer": "standard"
      }
    }
  }
}

// Single-field query — one BM25 calculation per shard
GET /restaurants/_search
{
  "query": {
    "match": {
      "search_all": "강남 이탈리안 파스타"
    }
  }
}
// 5 shards × 1 field = 5 sub-queries — much faster
```

For cases where field-level boosting is important, combine `copy_to` for recall with a targeted `should` for boosting:

```json
GET /restaurants/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "search_all": "강남 이탈리안 파스타" } }
      ],
      "should": [
        { "match": { "name": { "query": "강남 이탈리안 파스타", "boost": 3.0 } } }
      ]
    }
  }
}
// search_all provides broad recall, name boost rewards title matches
```

Key considerations:
- `copy_to` field is not stored in `_source` — it's an index-time only field
- Changes to `copy_to` mapping require reindexing
- The combined field uses its own analyzer (not the source fields' analyzers)
- For Korean search, create a separate `search_all_korean` field with nori analyzer

Reference: [copy_to parameter](https://www.elastic.co/guide/en/elasticsearch/reference/current/copy-to.html)
