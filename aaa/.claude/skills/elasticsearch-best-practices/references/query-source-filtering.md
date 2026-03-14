---
title: Fetch Only Needed Fields with _source Filtering
impact: MEDIUM-HIGH
impactDescription: 30-70% reduction in network transfer and heap usage on large documents
tags: query, source-filtering, performance, network
---

## Fetch Only Needed Fields with _source Filtering

By default, Elasticsearch returns the entire `_source` document for every hit. For documents with 50+ fields or large text fields, this wastes network bandwidth, increases heap pressure on coordinating nodes, and slows serialization. Fetch only the fields your application needs.

**Incorrect (returning entire 50-field documents):**

```json
// Returns full _source for each of 100 hits
// 50-field product docs at ~5KB each = 500KB per request
// At 1000 QPS = 500MB/s of unnecessary network traffic
GET /products/_search
{
  "size": 100,
  "query": {
    "bool": {
      "filter": [
        { "term": { "category": "electronics" } }
      ]
    }
  }
}
```

**Correct (_source filtering to fetch only needed fields):**

```json
// Only returns 4 fields per hit → ~200 bytes vs ~5KB
// 95% reduction in response size
GET /products/_search
{
  "size": 100,
  "_source": ["name", "price", "status", "category"],
  "query": {
    "bool": {
      "filter": [
        { "term": { "category": "electronics" } }
      ]
    }
  }
}
```

**Alternative: includes/excludes pattern:**

```json
// Useful when you need most fields but want to exclude large ones
GET /products/_search
{
  "_source": {
    "includes": ["name", "price", "metadata.*"],
    "excludes": ["description", "raw_html", "embedding_vector"]
  },
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "active" } }
      ]
    }
  }
}
```

**Disable _source entirely for count/agg-only queries:**

```json
// Aggregation-only query — no need for document bodies
GET /orders/_search
{
  "size": 0,
  "_source": false,
  "aggs": {
    "daily_revenue": {
      "date_histogram": {
        "field": "created_at",
        "calendar_interval": "day"
      },
      "aggs": {
        "total": { "sum": { "field": "amount" } }
      }
    }
  }
}
```

For aggregation-only queries, always set `"size": 0` to skip fetching hits entirely — this is even more impactful than `_source` filtering.

Reference: [Source filtering](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-fields.html#source-filtering)
