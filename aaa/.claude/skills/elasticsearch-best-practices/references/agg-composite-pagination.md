---
title: "Use Composite Aggregation for Large Result Pagination"
impact: MEDIUM
impactDescription: "Enables streaming over millions of buckets without OOM or size cap"
tags: agg, composite, pagination, large-result, streaming
---

## Use Composite Aggregation for Large Result Pagination

The standard `terms` aggregation loads all buckets into memory and returns at most `size` results (default 10, max practical ~65536). For high-cardinality fields with millions of unique values, increasing `size` causes OOM or extreme latency. The `composite` aggregation paginates through buckets using an `after_key` cursor, processing one page at a time with constant memory regardless of total cardinality.

**Incorrect (terms aggregation with inflated size on high-cardinality field):**

```json
// BAD: seller_id has 500K unique values
// BAD: Each shard builds and returns 100K buckets
// BAD: Coordinating node merges 100K x 20 shards = 2M buckets in heap
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "revenue_by_seller": {
      "terms": {
        "field": "seller_id",
        "size": 100000
      },
      "aggs": {
        "total_revenue": {
          "sum": { "field": "order_total" }
        }
      }
    }
  }
}
// Result: ~3GB heap spike, 45-second response time
// Coordinating node merges 100K buckets x N shards in memory
// Still only returns top 100K of 500K sellers
```

**Correct (composite aggregation with after_key pagination):**

```json
// First page — no "after" parameter
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "revenue_by_seller": {
      "composite": {
        "size": 1000,
        "sources": [
          {
            "seller": {
              "terms": { "field": "seller_id" }
            }
          }
        ]
      },
      "aggs": {
        "total_revenue": {
          "sum": { "field": "order_total" }
        }
      }
    }
  }
}
```

```json
// Response includes after_key for pagination
{
  "aggregations": {
    "revenue_by_seller": {
      "after_key": { "seller": "seller-001000" },
      "buckets": [
        {
          "key": { "seller": "seller-000001" },
          "doc_count": 342,
          "total_revenue": { "value": 28450.00 }
        }
        // ... 999 more buckets
      ]
    }
  }
}
```

```json
// Next page — pass after_key from previous response
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "revenue_by_seller": {
      "composite": {
        "size": 1000,
        "sources": [
          {
            "seller": {
              "terms": { "field": "seller_id" }
            }
          }
        ],
        "after": { "seller": "seller-001000" }
      },
      "aggs": {
        "total_revenue": {
          "sum": { "field": "order_total" }
        }
      }
    }
  }
}
// Repeat until response returns fewer buckets than "size" (last page)
```

**Multi-source composite (group by multiple fields):**

```json
// Paginate through all (seller, month) combinations
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "seller_monthly_revenue": {
      "composite": {
        "size": 500,
        "sources": [
          {
            "seller": {
              "terms": { "field": "seller_id" }
            }
          },
          {
            "month": {
              "date_histogram": {
                "field": "order_date",
                "calendar_interval": "month"
              }
            }
          }
        ]
      },
      "aggs": {
        "total_revenue": { "sum": { "field": "order_total" } },
        "order_count": { "value_count": { "field": "order_id" } }
      }
    }
  }
}
```

**Comparison:**

| Aspect | terms (size=N) | composite (paginated) |
|--------|---------------|----------------------|
| Memory usage | O(N x shards) in coordinating node | O(page_size) constant |
| Max results | Practical limit ~65K | Unlimited (all buckets) |
| Accuracy | Approximate on multi-shard | Exact (no approximation) |
| Sorting | By doc_count or sub-agg | By composite key only |
| Use case | Top-N with ranking | Full enumeration, export |
| Nested sub-aggs | All types supported | All types supported |

**Key rules:**

- Use `terms` when you need top-N ranking (e.g., "top 10 sellers by revenue") — it supports `order` by sub-aggregation.
- Use `composite` when you need to enumerate all buckets or when cardinality exceeds ~10K unique values.
- Set composite `size` to 1000-5000 per page — larger pages reduce round-trips but increase per-request memory.
- Pagination terminates when the response returns fewer buckets than the requested `size`.
- Composite aggregation always returns results in key order, not ranked by doc_count or sub-aggregation values.
- For ES 7.15+, consider `multi_terms` aggregation for simple multi-field grouping when you only need top-N.

Reference:
[Composite Aggregation](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-composite-aggregation.html)
