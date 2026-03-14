---
title: Build Custom Analyzer Chains for Domain-Specific Search
impact: HIGH
impactDescription: 3-10x improvement in search relevance for domain-specific terms and patterns
tags: analyzer, custom-analyzer, char-filter, tokenizer, token-filter
---

## Build Custom Analyzer Chains for Domain-Specific Search

The default `standard` analyzer is designed for generic English text. It fails on domain-specific patterns: product codes (SKU-12345), hyphenated terms (noise-cancelling), camelCase identifiers, and special characters that carry meaning. Custom analyzer chains let you control exactly how text is indexed and searched.

**Incorrect (standard analyzer on product catalog):**

```json
// standard analyzer tokenizes "SKU-12345" → ["sku", "12345"]
// Searching for "SKU-12345" or "sku12345" fails or returns wrong results
// "noise-cancelling" → ["noise", "cancelling"] — loses hyphenated meaning
PUT /products
{
  "mappings": {
    "properties": {
      "name": { "type": "text" },
      "sku": { "type": "text" },
      "description": { "type": "text" }
    }
  }
}
```

**Correct (custom analyzer chain: char_filter → tokenizer → token_filter):**

```json
PUT /products
{
  "settings": {
    "analysis": {
      "char_filter": {
        "sku_normalizer": {
          "type": "pattern_replace",
          "pattern": "[\\-_]",
          "replacement": ""
        }
      },
      "tokenizer": {
        "product_tokenizer": {
          "type": "pattern",
          "pattern": "[\\s,;]+",
          "lowercase": false
        }
      },
      "filter": {
        "product_synonym": {
          "type": "synonym",
          "synonyms": [
            "headphones, earphones, earbuds",
            "laptop, notebook"
          ]
        },
        "product_stopwords": {
          "type": "stop",
          "stopwords": ["the", "a", "an", "for", "with"]
        }
      },
      "analyzer": {
        "product_analyzer": {
          "type": "custom",
          "char_filter": ["sku_normalizer"],
          "tokenizer": "product_tokenizer",
          "filter": ["lowercase", "product_stopwords", "product_synonym"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": { "type": "text", "analyzer": "product_analyzer" },
      "sku": { "type": "text", "analyzer": "product_analyzer" },
      "description": { "type": "text", "analyzer": "product_analyzer" }
    }
  }
}
```

**Analyzer chain execution order:**

```
Input text: "SKU-12345 Noise-Cancelling Headphones"
          ↓
  char_filter (sku_normalizer): "SKU12345 NoiseCancelling Headphones"
          ↓
  tokenizer (product_tokenizer): ["SKU12345", "NoiseCancelling", "Headphones"]
          ↓
  token_filter (lowercase): ["sku12345", "noisecancelling", "headphones"]
          ↓
  token_filter (product_stopwords): ["sku12345", "noisecancelling", "headphones"]
          ↓
  token_filter (product_synonym): ["sku12345", "noisecancelling", "headphones", "earphones", "earbuds"]
```

**Always test with the _analyze API before indexing data:**

```json
// Verify token output matches your expectations
POST /products/_analyze
{
  "analyzer": "product_analyzer",
  "text": "SKU-12345 Noise-Cancelling Headphones"
}
// Response: tokens ["sku12345", "noisecancelling", "headphones", "earphones", "earbuds"]
```

```json
// Test individual components in isolation
POST /_analyze
{
  "char_filter": [{ "type": "pattern_replace", "pattern": "[\\-_]", "replacement": "" }],
  "tokenizer": "standard",
  "filter": ["lowercase"],
  "text": "SKU-12345"
}
// Response: tokens ["sku12345"]
```

Custom analyzers are defined per-index at creation time and cannot be changed on existing indices without reindexing. Always validate with `_analyze` in a test index first.

Reference: [Custom analyzer](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-custom-analyzer.html)
