---
title: Use Profile API to Identify Query Bottlenecks
impact: MEDIUM
impactDescription: Pinpoints exact slow clauses, enabling targeted optimization instead of guessing
tags: query, profile, debugging, performance, bottleneck, slow-query
---

## Use Profile API to Identify Query Bottlenecks

When a query is slow, guessing which part is the bottleneck wastes time. The Profile API reveals the exact time spent on each query clause, collector, and aggregation across every shard, enabling targeted optimization.

**Incorrect (guessing at query performance problems):**

```json
// This query is slow but you don't know why
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "name": "노트북" } },
        { "nested": {
            "path": "reviews",
            "query": { "range": { "reviews.rating": { "gte": 4 } } }
          }
        }
      ],
      "should": [
        { "wildcard": { "description": "*고성능*" } }
      ],
      "filter": [
        { "terms": { "category": ["laptop", "ultrabook", "notebook"] } }
      ]
    }
  }
}
// Is it the nested query? The wildcard? The multi-term filter? No way to tell without profiling
```

**Correct (add profile: true to identify the bottleneck):**

```json
GET /products/_search
{
  "profile": true,
  "query": {
    "bool": {
      "must": [
        { "match": { "name": "노트북" } },
        { "nested": {
            "path": "reviews",
            "query": { "range": { "reviews.rating": { "gte": 4 } } }
          }
        }
      ],
      "should": [
        { "wildcard": { "description": "*고성능*" } }
      ],
      "filter": [
        { "terms": { "category": ["laptop", "ultrabook", "notebook"] } }
      ]
    }
  }
}
```

Reading profile output:

```json
// Profile response structure (simplified)
{
  "profile": {
    "shards": [{
      "searches": [{
        "query": [{
          "type": "BooleanQuery",
          "description": "+name:노트북 +ToParentBlockJoinQuery ...",
          "time_in_nanos": 15234567,
          "children": [
            {
              "type": "TermQuery",
              "description": "name:노트북",
              "time_in_nanos": 123456
            },
            {
              "type": "ToParentBlockJoinQuery",
              "description": "reviews.rating:[4 TO *]",
              "time_in_nanos": 12000000
            },
            {
              "type": "WildcardQuery",
              "description": "description:*고성능*",
              "time_in_nanos": 2500000
            }
          ]
        }]
      }]
    }]
  }
}
// ToParentBlockJoinQuery (nested) takes 12ms — main bottleneck
// WildcardQuery takes 2.5ms — secondary issue (leading wildcard)
// TermQuery takes 0.1ms — fast
```

Use profiling results to prioritize optimization:
1. Replace `nested` with denormalized `object` if cross-matching is not needed
2. Replace leading wildcard with `ngram` tokenizer or `wildcard` field type
3. Move to filter context if scoring is not needed for that clause

Important notes:
- **Never use `profile: true` in production** — it adds significant overhead (2-10x slower)
- Use on a staging cluster with production-like data
- Profile output can be very large for complex queries — focus on `time_in_nanos` to find the worst offenders
- For aggregation profiling, check the `aggregations` section of the profile output

Reference: [Profile API](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-profile.html)
