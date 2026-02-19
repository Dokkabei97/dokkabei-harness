---
title: Use search_after for Deep Pagination
impact: HIGH
impactDescription: Eliminates heap explosion from deep from+size and enables unbounded pagination
tags: query, pagination, search-after, from-size
---

## Use search_after for Deep Pagination

`from + size` pagination requires each shard to load `from + size` results into heap memory, making deep pagination progressively more expensive. At `from=9990, size=10`, each of 5 shards loads 10,000 results (50,000 total) to return just 10. Elasticsearch hard-blocks requests beyond `max_result_window` (default 10,000) for this reason.

**Incorrect (deep from+size pagination):**

```json
// Page 1000: each shard loads 10,000 docs into heap
// 5 shards x 10,000 = 50,000 docs in coordinating node memory
// Increasing max_result_window just moves the OOM further out
GET /orders/_search
{
  "from": 9990,
  "size": 10,
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "completed" } }
      ]
    }
  },
  "sort": [{ "created_at": "desc" }]
}

// Even worse: raising the limit to paper over the problem
PUT /orders/_settings
{
  "index.max_result_window": 100000
}
```

**Correct (search_after with sort tiebreaker):**

```json
// Request 1: First page — no search_after needed
GET /orders/_search
{
  "size": 10,
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "completed" } }
      ]
    }
  },
  "sort": [
    { "created_at": "desc" },
    { "_id": "asc" }
  ]
}
// Response includes sort values for last hit:
// "sort": [1706745600000, "order_abc123"]
```

```json
// Request 2: Next page — pass sort values of last hit
// Each shard only scans forward from the given sort values
// Constant memory regardless of page depth
GET /orders/_search
{
  "size": 10,
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "completed" } }
      ]
    }
  },
  "sort": [
    { "created_at": "desc" },
    { "_id": "asc" }
  ],
  "search_after": [1706745600000, "order_abc123"]
}
```

**Comparison:**

| Aspect | from + size | search_after |
|--------|-----------|--------------|
| Memory per request | O(from + size) per shard | O(size) per shard |
| Max depth | 10,000 (default limit) | Unbounded |
| Random page access | Yes (page 50 directly) | No (sequential only) |
| Use case | Shallow UI pagination | Infinite scroll, data export, batch processing |

**Tiebreaker requirement:** Always include a unique tiebreaker field (like `_id` or `_shard_doc`) as the last sort criterion. Without it, documents with identical sort values may be skipped or duplicated across pages.

For bulk export of all matching documents, use the Point-in-Time (PIT) API with `search_after` to ensure a consistent snapshot across multiple pagination requests.

Reference: [search_after](https://www.elastic.co/guide/en/elasticsearch/reference/current/paginate-search-results.html#search-after)
