---
title: Use edge_ngram for Autocomplete Instead of Wildcard Queries
impact: HIGH
impactDescription: 100x faster autocomplete by using the inverted index instead of scanning all terms
tags: analyzer, ngram, edge-ngram, autocomplete, search-as-you-type, performance
---

## Use edge_ngram for Autocomplete Instead of Wildcard Queries

Autocomplete (search-as-you-type) requires matching partial input against indexed values. Using wildcard queries for this is extremely slow because it scans the entire term dictionary. `edge_ngram` pre-indexes prefixes at index time, turning autocomplete into a fast inverted index lookup.

**Incorrect (wildcard query for autocomplete — scans all terms):**

```json
// User types "삼성" → application sends wildcard query
GET /products/_search
{
  "query": {
    "wildcard": { "name": "삼성*" }
  }
}
// Scans every term in the inverted index starting with "삼성"
// With millions of products, this takes 100ms+ and gets worse with more data
// Leading wildcards (*삼성) are even worse — see query-expensive-patterns.md
```

**Correct (edge_ngram for prefix-based autocomplete):**

```json
PUT /products
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "edge_ngram_tokenizer": {
          "type": "edge_ngram",
          "min_gram": 1,
          "max_gram": 20,
          "token_chars": ["letter", "digit"]
        }
      },
      "analyzer": {
        "autocomplete_index": {
          "type": "custom",
          "tokenizer": "edge_ngram_tokenizer",
          "filter": ["lowercase"]
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
      }
    }
  }
}

// "삼성전자" is indexed as: ["삼", "삼성", "삼성전", "삼성전자"]
// Searching "삼성" is a simple term lookup — instant results

POST /products/_doc/1
{ "name": "삼성전자 갤럭시 S24" }

GET /products/_search
{
  "query": {
    "match": { "name": "삼성" }
  }
}
// Matches via edge_ngram tokens — fast inverted index lookup
```

For Korean autocomplete with morphological analysis, combine Nori with edge_ngram:

```json
PUT /products
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "nori_mixed": {
          "type": "nori_tokenizer",
          "decompound_mode": "mixed"
        }
      },
      "filter": {
        "edge_ngram_filter": {
          "type": "edge_ngram",
          "min_gram": 1,
          "max_gram": 20
        }
      },
      "analyzer": {
        "korean_autocomplete_index": {
          "type": "custom",
          "tokenizer": "nori_mixed",
          "filter": ["nori_readingform", "lowercase", "edge_ngram_filter"]
        },
        "korean_autocomplete_search": {
          "type": "custom",
          "tokenizer": "nori_mixed",
          "filter": ["nori_readingform", "lowercase"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "korean_autocomplete_index",
        "search_analyzer": "korean_autocomplete_search"
      }
    }
  }
}
```

Alternatively, use the built-in `search_as_you_type` field type (ES 7.2+):

```json
PUT /products
{
  "mappings": {
    "properties": {
      "name": {
        "type": "search_as_you_type",
        "max_shingle_size": 3
      }
    }
  }
}

// Automatically creates sub-fields:
// name          → standard analysis
// name._2gram   → shingle(2) for 2-word prefix matching
// name._3gram   → shingle(3) for 3-word prefix matching
// name._index_prefix → edge_ngram for single-word prefix

GET /products/_search
{
  "query": {
    "multi_match": {
      "query": "삼성 갤럭",
      "type": "bool_prefix",
      "fields": ["name", "name._2gram", "name._3gram"]
    }
  }
}
```

ngram vs edge_ngram:

| Type | Tokens from "삼성전자" | Use Case |
|------|---------------------|----------|
| `edge_ngram` | ["삼", "삼성", "삼성전", "삼성전자"] | Prefix autocomplete (start-of-word) |
| `ngram` | ["삼", "삼성", "성전", "전자", "삼성전", "성전자", "삼성전자"] | Substring search (anywhere in word) |

**Always use `edge_ngram` for autocomplete** — `ngram` creates far more tokens and larger index size. Use `ngram` only when substring matching is needed (see `query-expensive-patterns.md` for leading wildcard replacement).

Reference: [search_as_you_type](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-as-you-type.html), [Edge n-gram tokenizer](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-edgengram-tokenizer.html)
