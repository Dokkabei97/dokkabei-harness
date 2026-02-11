---
title: Optimize Painless Scripts to Avoid Performance Pitfalls
impact: LOW
impactDescription: Poorly written scripts can be 100x slower than equivalent native queries
tags: advanced, painless, script, performance, optimization
---

## Optimize Painless Scripts to Avoid Performance Pitfalls

Painless is Elasticsearch's scripting language for computed fields, custom scoring, and update operations. Poorly written scripts cause severe performance degradation.

**Incorrect (slow script patterns):**

```json
// Accessing _source in scripts (very slow — parses JSON per document)
GET /products/_search
{
  "query": {
    "script_score": {
      "query": { "match_all": {} },
      "script": {
        "source": "params._source.price * params._source.discount_rate"
      }
    }
  }
}
// _source requires JSON parsing for EVERY document

// String operations in scoring scripts
GET /products/_search
{
  "query": {
    "script_score": {
      "query": { "match_all": {} },
      "script": {
        "source": "doc['name.keyword'].value.toLowerCase().contains('노트북') ? 10 : 1"
      }
    }
  }
}
// String operations per document = extremely slow
```

**Correct (optimized script patterns):**

```json
// Use doc values instead of _source (direct columnar access)
GET /products/_search
{
  "query": {
    "script_score": {
      "query": { "match": { "name": "노트북" } },
      "script": {
        "source": "doc['popularity'].value * Math.log1p(doc['sales_count'].value)",
        "params": {}
      }
    }
  }
}
// doc values are columnar — much faster than _source parsing

// Use params for constants (compiled once, reused)
GET /products/_search
{
  "query": {
    "script_score": {
      "query": { "match_all": {} },
      "script": {
        "source": "doc['price'].value * params.tax_rate",
        "params": { "tax_rate": 1.1 }
      }
    }
  }
}
// Changing params doesn't require recompilation

// Prefer native queries over scripts when possible
// Instead of script: "doc['price'].value < 50000"
// Use: { "range": { "price": { "lt": 50000 } } }
```

Script performance rules:
1. Use `doc['field']` (doc values) instead of `params._source` or `ctx._source`
2. Use `params` for all constants (enables script caching)
3. Prefer native queries/aggregations over scripts
4. Avoid string operations in scoring scripts
5. Pre-compute values at index time when possible (see `indexing-ingest-pipeline.md`)

Reference: [Painless scripting](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-scripting-painless.html)
