---
title: Use Edge N-gram for Autocomplete, Not Wildcard
impact: MEDIUM-HIGH
impactDescription: 100x faster autocomplete — O(1) index lookup vs O(n) full index scan with wildcard
tags: analyzer, edge-ngram, autocomplete, wildcard, search-as-you-type
---

## Use Edge N-gram for Autocomplete, Not Wildcard

Wildcard queries (`wire*`) scan the entire term dictionary — O(n) on the number of unique terms. Edge n-gram pre-computes prefix tokens at index time (`w`, `wi`, `wir`, `wire`), making autocomplete an O(1) inverted index lookup. For indices with 100M+ documents, this difference is 100x or more.

**Incorrect (wildcard query for autocomplete):**

```json
// Wildcard scans all terms starting with "wire" across the entire index
// On 100M docs: 200-500ms per keystroke — unusable for real-time autocomplete
// Leading wildcard (*phone) is even worse: scans ALL terms
GET /products/_search
{
  "query": {
    "wildcard": {
      "name": {
        "value": "wire*"
      }
    }
  }
}
```

**Correct (edge n-gram analyzer for index-time prefix expansion):**

```json
// Edge n-gram creates prefix tokens at index time
// "wireless" → ["wi", "wir", "wire", "wirel", "wirele", "wireles", "wireless"]
// Autocomplete query is a simple term lookup → <5ms
PUT /products
{
  "settings": {
    "analysis": {
      "filter": {
        "autocomplete_filter": {
          "type": "edge_ngram",
          "min_gram": 2,
          "max_gram": 15
        }
      },
      "analyzer": {
        "autocomplete_index": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "autocomplete_filter"]
        },
        "autocomplete_search": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "autocomplete_index",
        "search_analyzer": "autocomplete_search"
      },
      "category": { "type": "keyword" }
    }
  }
}
```

**Why separate index and search analyzers:**

```
Index time ("wireless headphones"):
  autocomplete_index → ["wi", "wir", "wire", ..., "wireless", "he", "hea", ..., "headphones"]

Search time ("wire"):
  autocomplete_search → ["wire"]  (NOT edge-ngram expanded)
  → Matches against pre-built prefix tokens in the index
```

If you used the same edge n-gram analyzer for search, typing "wire" would expand to `["wi", "wir", "wire"]` and match documents containing "winter" (via "wi") — wrong results.

**Query with autocomplete:**

```json
// Fast prefix match — inverted index lookup, not a scan
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "name": "wire" } }
      ],
      "filter": [
        { "term": { "category": "electronics" } }
      ]
    }
  }
}
```

**Verify tokenization with _analyze:**

```json
// Check index-time tokens
POST /products/_analyze
{
  "analyzer": "autocomplete_index",
  "text": "wireless"
}
// tokens: ["wi", "wir", "wire", "wirel", "wirele", "wireles", "wireless"]

// Check search-time tokens
POST /products/_analyze
{
  "analyzer": "autocomplete_search",
  "text": "wire"
}
// tokens: ["wire"]
```

**Performance comparison:**

| Approach | Latency (100M docs) | Index Size Overhead | Correctness |
|----------|---------------------|---------------------|-------------|
| `wildcard: "wire*"` | 200-500ms | None | Exact prefix |
| `wildcard: "*phone"` | 500ms-2s | None | Leading wildcard (avoid) |
| Edge n-gram | 2-5ms | 20-40% larger index | Prefix from each token |

Set `min_gram: 2` to avoid single-character tokens that match too broadly. Set `max_gram` to the longest reasonable prefix (15 is sufficient for most use cases). The index size increase from edge n-gram tokens is a worthwhile trade-off for sub-5ms autocomplete response times.

Reference: [Edge n-gram tokenizer](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-edgengram-tokenizer.html)
