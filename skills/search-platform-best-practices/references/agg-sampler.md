---
title: Use Sampler Aggregation to Speed Up Expensive Sub-Aggregations
impact: MEDIUM
impactDescription: 5-10x faster aggregations by computing on a representative sample instead of all documents
tags: aggregation, sampler, performance, approximate, optimization
---

## Use Sampler Aggregation to Speed Up Expensive Sub-Aggregations

When sub-aggregations are expensive (significant_terms, cardinality on high-cardinality fields), running them on all matching documents is wasteful. The `sampler` aggregation limits sub-aggregations to the top N most relevant documents.

**Incorrect (expensive aggregation on full result set):**

```json
GET /articles/_search
{
  "size": 0,
  "query": { "match": { "content": "인공지능" } },
  "aggs": {
    "trending_topics": {
      "significant_terms": {
        "field": "tags",
        "size": 20
      }
    }
  }
}
// significant_terms runs on ALL 500,000 matching documents
// Extremely memory-intensive and slow
```

**Correct (sampler limits sub-aggregation scope):**

```json
GET /articles/_search
{
  "size": 0,
  "query": { "match": { "content": "인공지능" } },
  "aggs": {
    "sample": {
      "sampler": {
        "shard_size": 200
      },
      "aggs": {
        "trending_topics": {
          "significant_terms": {
            "field": "tags",
            "size": 20
          }
        }
      }
    }
  }
}
// Only processes top 200 most relevant docs per shard
// Results are statistically representative, 10x faster

// diversified_sampler for better coverage across categories
GET /articles/_search
{
  "size": 0,
  "aggs": {
    "diverse_sample": {
      "diversified_sampler": {
        "shard_size": 200,
        "field": "category"
      },
      "aggs": {
        "trending_topics": {
          "significant_terms": { "field": "tags", "size": 20 }
        }
      }
    }
  }
}
// Samples are diversified across categories — prevents one category from dominating
```

Reference: [Sampler aggregation](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-sampler-aggregation.html)
