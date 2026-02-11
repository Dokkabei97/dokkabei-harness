---
title: Use search_after + PIT for Deep Pagination Instead of from+size
impact: CRITICAL
impactDescription: Eliminates OOM risk and 10,000-hit limit for deep pagination
tags: query, pagination, search_after, point-in-time, from-size, deep-paging
---

## Use search_after + PIT for Deep Pagination Instead of from+size

`from + size` pagination requires the coordinating node to fetch `from + size` results from every shard, sort them, and discard the first `from` results. At `from=9990, size=10` with 5 shards, this means fetching 50,000 documents just to return 10. Elasticsearch hard-limits this at 10,000 hits by default.

**Incorrect (from+size deep pagination — fails or OOMs on large offsets):**

```json
// Page 1 — works fine
GET /logs/_search
{
  "from": 0, "size": 20,
  "query": { "match_all": {} },
  "sort": [{ "timestamp": "desc" }]
}

// Page 500 — fails with index.max_result_window exceeded
GET /logs/_search
{
  "from": 9980, "size": 20,
  "query": { "match_all": {} },
  "sort": [{ "timestamp": "desc" }]
}
// Error: "Result window is too large, from + size must be less than or equal to [10000]"

// DO NOT increase max_result_window — it causes heap pressure on large offsets
PUT /logs/_settings
{ "index.max_result_window": 100000 }
// This "fix" causes OOM under load — each shard must hold 100K docs in memory
```

**Correct (search_after + Point in Time for consistent deep pagination):**

```json
// Step 1: Open a Point in Time (consistent snapshot for pagination)
POST /logs/_pit?keep_alive=5m
// Returns: { "id": "46ToAwMDaWR..." }

// Step 2: First page — include PIT and sort
GET /_search
{
  "size": 20,
  "query": { "match_all": {} },
  "pit": {
    "id": "46ToAwMDaWR...",
    "keep_alive": "5m"
  },
  "sort": [
    { "timestamp": "desc" },
    { "_shard_doc": "asc" }
  ]
}
// Returns hits with "sort" values on each hit, e.g. [1704067200000, 42]

// Step 3: Next page — use the last hit's sort values as search_after
GET /_search
{
  "size": 20,
  "query": { "match_all": {} },
  "pit": {
    "id": "46ToAwMDaWR...",
    "keep_alive": "5m"
  },
  "search_after": [1704067200000, 42],
  "sort": [
    { "timestamp": "desc" },
    { "_shard_doc": "asc" }
  ]
}
// Efficiently fetches the next 20 documents after the last seen sort values
// No shard needs to collect more than `size` documents

// Step 4: Close PIT when done
DELETE /_pit
{ "id": "46ToAwMDaWR..." }
```

Pagination comparison:

| Method | Deep Paging | Consistency | Use Case |
|--------|-------------|-------------|----------|
| `from + size` | Max 10K hits | No (index changes between pages) | Small result sets, UI paging |
| `search_after` + PIT | Unlimited | Yes (PIT snapshot) | Production pagination, infinite scroll |
| `scroll` | Unlimited | Yes (snapshot) | Batch processing (deprecated for search) |

Important notes:
- Always include a tiebreaker sort field (`_shard_doc` or a unique field) to ensure deterministic ordering
- PIT keeps resources open on the cluster — always close when done and set reasonable `keep_alive`
- `search_after` requires results to be sorted; it cannot be used with random/custom scoring without a sort
- Do not use `from` parameter with `search_after` — they are mutually exclusive

Reference: [search_after](https://www.elastic.co/guide/en/elasticsearch/reference/current/paginate-search-results.html#search-after), [Point in time API](https://www.elastic.co/guide/en/elasticsearch/reference/current/point-in-time-api.html)
