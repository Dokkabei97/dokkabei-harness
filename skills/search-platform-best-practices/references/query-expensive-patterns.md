---
title: Avoid Leading Wildcards, Regex Queries, and Script Queries in Production
impact: CRITICAL
impactDescription: Leading wildcards and regex can be 100-1000x slower than term queries, causing cluster-wide slowdowns
tags: query, wildcard, regex, script, performance, anti-pattern, expensive
---

## Avoid Leading Wildcards, Regex Queries, and Script Queries in Production

Certain query patterns bypass the inverted index and scan every term or document, turning O(1) lookups into O(n) scans. In production with millions of documents, these patterns cause timeouts and affect all queries on the same node.

**Incorrect (leading wildcard — scans every term in the inverted index):**

```json
// Leading wildcard "*검색" must check EVERY term in the field's inverted index
GET /products/_search
{
  "query": {
    "wildcard": { "name": "*검색엔진" }
  }
}
// With 1M unique terms, this iterates through all of them
// Cannot use the index structure — equivalent to a full scan
```

**Incorrect (complex regex — also scans all terms):**

```json
GET /logs/_search
{
  "query": {
    "regexp": {
      "message": ".*error.*timeout.*connection.*"
    }
  }
}
// Regex with .* prefix has the same problem as leading wildcards
```

**Incorrect (script query — evaluates on every document):**

```json
GET /products/_search
{
  "query": {
    "script": {
      "script": {
        "source": "doc['price'].value * doc['discount_rate'].value < params.max",
        "params": { "max": 50000 }
      }
    }
  }
}
// Runs the script on EVERY document in the index — no index optimization possible
```

**Correct alternatives:**

```json
// 1. Replace leading wildcard with ngram or edge_ngram tokenizer
PUT /products
{
  "settings": {
    "analysis": {
      "analyzer": {
        "ngram_analyzer": {
          "type": "custom",
          "tokenizer": "ngram_tokenizer",
          "filter": ["lowercase"]
        }
      },
      "tokenizer": {
        "ngram_tokenizer": {
          "type": "ngram",
          "min_gram": 2,
          "max_gram": 4
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "ngram_analyzer",
        "search_analyzer": "standard"
      }
    }
  }
}

// Now "검색엔진" substring search uses the inverted index — fast!
GET /products/_search
{
  "query": { "match": { "name": "검색엔진" } }
}

// 2. Replace script query with pre-computed field (index-time calculation)
// At index time, compute and store the discounted price
POST /products/_doc/1
{
  "name": "노트북",
  "price": 100000,
  "discount_rate": 0.3,
  "discounted_price": 70000
}

// Now use a simple range query — fully indexed
GET /products/_search
{
  "query": {
    "range": { "discounted_price": { "lt": 50000 } }
  }
}

// 3. For ES 7.11+, use "wildcard" field type for efficient wildcard queries
PUT /logs
{
  "mappings": {
    "properties": {
      "url_path": {
        "type": "wildcard"
      }
    }
  }
}

GET /logs/_search
{
  "query": {
    "wildcard": { "url_path": "*api/v2*" }
  }
}
// wildcard field type uses ngram-based internal indexing — much faster than text+wildcard query
```

If expensive queries are unavoidable, protect the cluster:

```json
// Set search timeout to prevent runaway queries
GET /products/_search?timeout=5s
{
  "query": { "wildcard": { "name": "*검색*" } }
}

// Enable the search.allow_expensive_queries cluster setting guard
PUT /_cluster/settings
{
  "persistent": {
    "search.allow_expensive_queries": false
  }
}
// Blocks leading wildcards, regex, and script queries cluster-wide
```

Reference: [Wildcard query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-wildcard-query.html), [Expensive queries](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-wildcard-query.html#wildcard-query-allow-expensive-queries)
