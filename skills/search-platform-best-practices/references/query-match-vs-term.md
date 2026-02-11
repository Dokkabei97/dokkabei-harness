---
title: Never Use term Query on text Fields or match Query on keyword Fields
impact: CRITICAL
impactDescription: Eliminates zero-result bugs caused by query/field type mismatch
tags: query, term, match, text, keyword, analysis, correctness
---

## Never Use term Query on text Fields or match Query on keyword Fields

`term` queries find exact values in the inverted index without analysis. `match` queries analyze the input text first. Using them on the wrong field type produces unexpected results or zero matches — this is the single most common Elasticsearch bug.

**Incorrect (term query on text field — almost never matches):**

```json
PUT /users
{
  "mappings": {
    "properties": {
      "name": { "type": "text" }
    }
  }
}

POST /users/_doc/1
{ "name": "Kim Min-Jun" }

// term query searches for exact token "Kim Min-Jun" in the inverted index
GET /users/_search
{
  "query": {
    "term": { "name": "Kim Min-Jun" }
  }
}
// Returns ZERO results!
// text field analyzed "Kim Min-Jun" → tokens ["kim", "min", "jun"]
// term query looks for exact token "Kim Min-Jun" — no such token exists
```

**Correct (match query on text field):**

```json
// match query analyzes input the same way the field was indexed
GET /users/_search
{
  "query": {
    "match": { "name": "Kim Min-Jun" }
  }
}
// Analyzes input → ["kim", "min", "jun"] → matches indexed tokens

// For exact match on keyword field, use term query
PUT /users
{
  "mappings": {
    "properties": {
      "name": { "type": "text" },
      "email": { "type": "keyword" }
    }
  }
}

GET /users/_search
{
  "query": {
    "term": { "email": "kim@example.com" }
  }
}
// keyword field stores exact value — term query matches exactly
```

Use the `_analyze` API to debug tokenization:

```json
// See how a text field tokenizes your value
POST /users/_analyze
{
  "field": "name",
  "text": "Kim Min-Jun"
}
// Returns: ["kim", "min", "jun"]

// Compare with what term query is searching for:
// "Kim Min-Jun" (exact, unanalyzed) — no match
```

Quick reference:

| Field Type | Use This Query | Never Use |
|------------|---------------|-----------|
| `text` | `match`, `multi_match`, `match_phrase` | `term`, `terms` |
| `keyword` | `term`, `terms`, `wildcard` | `match` (works but wasteful) |
| Multi-field `.keyword` | `term` for exact match | |
| Multi-field (root) | `match` for full-text search | |

Edge case: `match` on `keyword` fields technically works (the keyword analyzer returns the whole string as one token), but it adds unnecessary analysis overhead. Always use `term` for `keyword` fields.

Reference: [Term query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-term-query.html), [Match query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-match-query.html)
