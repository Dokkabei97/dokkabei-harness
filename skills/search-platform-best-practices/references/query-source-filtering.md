---
title: Use _source Filtering or stored_fields to Reduce Response Size
impact: MEDIUM-HIGH
impactDescription: 50-90% response size reduction, lower network latency and client memory usage
tags: query, _source, filtering, stored_fields, network, response-size
---

## Use _source Filtering or stored_fields to Reduce Response Size

By default, Elasticsearch returns the full `_source` of each hit. For documents with many fields, large text bodies, or embedding vectors, this wastes network bandwidth and client memory. Request only the fields you need.

**Incorrect (returning full _source when only a few fields are needed):**

```json
// Document has 50 fields, 5KB each — returning 20 hits = 1MB+ response
GET /products/_search
{
  "query": { "match": { "name": "노트북" } },
  "size": 20
}
// Client only displays name, price, and thumbnail_url
// But receives description, specs, reviews, metadata, embeddings...
```

**Correct (_source filtering — include only needed fields):**

```json
// Include specific fields
GET /products/_search
{
  "_source": ["name", "price", "thumbnail_url", "category"],
  "query": { "match": { "name": "노트북" } },
  "size": 20
}

// Or exclude heavy fields
GET /products/_search
{
  "_source": {
    "excludes": ["description", "embedding", "raw_specs"]
  },
  "query": { "match": { "name": "노트북" } },
  "size": 20
}

// Disable _source entirely when only aggregations are needed
GET /products/_search
{
  "_source": false,
  "size": 0,
  "aggs": {
    "categories": { "terms": { "field": "category", "size": 20 } }
  }
}
```

For fields that are frequently fetched in isolation, use `stored_fields`:

```json
// Map fields as stored for direct retrieval without _source parsing
PUT /products
{
  "mappings": {
    "properties": {
      "name": { "type": "text", "store": true },
      "price": { "type": "long", "store": true },
      "description": { "type": "text" }
    }
  }
}

// Retrieve only stored fields — avoids loading and parsing _source JSON
GET /products/_search
{
  "stored_fields": ["name", "price"],
  "_source": false,
  "query": { "match": { "name": "노트북" } }
}
```

Comparison:

| Method | Mechanism | Best For |
|--------|-----------|----------|
| `_source: [fields]` | Loads full _source, extracts fields | Ad-hoc field selection |
| `_source: false` | Skips _source entirely | Aggregation-only queries |
| `stored_fields` | Reads from stored field columns | Frequently accessed small fields |
| `fields` (runtime) | Computed from doc values/scripts | Formatted or computed fields |

For APIs serving search results, always filter `_source` to the fields displayed in the current view (list view vs detail view may need different field sets).

Reference: [Source filtering](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-fields.html#source-filtering)
