---
title: Choose Nori decompound_mode Based on Search Recall vs Precision Needs
impact: HIGH
impactDescription: Directly controls whether compound nouns match partial or full terms
tags: analyzer, nori, decompound, compound-noun, recall, precision, korean
---

## Choose Nori decompound_mode Based on Search Recall vs Precision Needs

Korean compound nouns (e.g., "서울특별시", "삼성전자") can be decomposed into sub-words. The `decompound_mode` setting controls how these compounds are tokenized, directly affecting whether partial searches match compound nouns.

**Three modes compared:**

```json
// Test text: "삼성전자"

// Mode: none — no decomposition
POST /_analyze
{
  "tokenizer": {
    "type": "nori_tokenizer",
    "decompound_mode": "none"
  },
  "text": "삼성전자"
}
// Tokens: ["삼성전자"]
// Searching "삼성" does NOT match — compound kept as-is

// Mode: discard — only sub-words, original discarded
POST /_analyze
{
  "tokenizer": {
    "type": "nori_tokenizer",
    "decompound_mode": "discard"
  },
  "text": "삼성전자"
}
// Tokens: ["삼성", "전자"]
// Searching "삼성" matches ✓
// Searching "삼성전자" as phrase may not match (tokens are separate) ✗

// Mode: mixed — both original and sub-words (RECOMMENDED)
POST /_analyze
{
  "tokenizer": {
    "type": "nori_tokenizer",
    "decompound_mode": "mixed"
  },
  "text": "삼성전자"
}
// Tokens: ["삼성", "전자", "삼성전자"]
// Searching "삼성" matches ✓
// Searching "삼성전자" exact match ✓
// Best recall — slightly larger index size
```

**Recommended: `mixed` mode for most use cases:**

```json
PUT /products
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "nori_mixed": {
          "type": "nori_tokenizer",
          "decompound_mode": "mixed",
          "discard_punctuation": true
        }
      },
      "analyzer": {
        "korean_search": {
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
        "analyzer": "korean_search"
      }
    }
  }
}
```

Real-world compound noun examples:

```json
POST /products/_analyze
{
  "analyzer": "korean_search",
  "text": "서울특별시 강남구 삼성동 포스코사거리"
}
// mixed mode tokens:
// ["서울", "특별", "시", "서울특별시",
//  "강남", "구", "강남구",
//  "삼성", "동", "삼성동",
//  "포스코", "사거리", "포스코사거리"]
```

Mode selection guide:

| Mode | Index Size | Recall | Precision | Recommended For |
|------|-----------|--------|-----------|-----------------|
| `none` | Smallest | Low | High | Exact compound matching only |
| `discard` | Medium | Medium | Medium | When index size is a concern |
| **`mixed`** | **Largest** | **High** | **High** | **General-purpose Korean search** |

Trade-off: `mixed` mode increases index size by ~15-25% due to additional tokens, but the search quality improvement is almost always worth it.

Reference: [Nori tokenizer decompound_mode](https://www.elastic.co/guide/en/elasticsearch/plugins/current/analysis-nori-tokenizer.html)
