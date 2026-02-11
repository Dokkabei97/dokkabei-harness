---
title: Choose Between Index-Time and Search-Time Synonym Filters
impact: HIGH
impactDescription: Wrong synonym timing causes stale results or reindex requirements on every synonym update
tags: analyzer, synonym, filter, index-time, search-time, trade-off, korean
---

## Choose Between Index-Time and Search-Time Synonym Filters

Synonyms expand queries so "노트북" also finds "랩탑" and "laptop". The critical choice is *when* to apply synonyms: at index time (baked into the inverted index) or at search time (expanded at query time). Each has significant trade-offs.

**Index-time synonyms (baked in — requires reindex to update):**

```json
PUT /products
{
  "settings": {
    "analysis": {
      "filter": {
        "synonym_index": {
          "type": "synonym",
          "synonyms": [
            "노트북, 랩탑, laptop",
            "핸드폰, 스마트폰, 휴대폰, mobile phone"
          ]
        }
      },
      "analyzer": {
        "korean_with_synonyms": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": ["nori_readingform", "lowercase", "synonym_index"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "korean_with_synonyms"
      }
    }
  }
}

// "노트북" is indexed as tokens: ["노트북", "랩탑", "laptop"]
// Searching "랩탑" matches documents containing "노트북" ✓
// BUT: Adding a new synonym requires full reindex ✗
```

**Search-time synonyms (applied at query time — updatable without reindex):**

```json
PUT /products
{
  "settings": {
    "analysis": {
      "filter": {
        "synonym_search": {
          "type": "synonym",
          "synonyms": [
            "노트북, 랩탑, laptop",
            "핸드폰, 스마트폰, 휴대폰, mobile phone"
          ],
          "updateable": true
        }
      },
      "analyzer": {
        "korean_index": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": ["nori_readingform", "lowercase"]
        },
        "korean_search": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": ["nori_readingform", "lowercase", "synonym_search"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "korean_index",
        "search_analyzer": "korean_search"
      }
    }
  }
}

// Document indexed with original tokens only: ["노트북"]
// At search time, "랩탑" expands to: ["노트북", "랩탑", "laptop"]
// Matches because "노트북" is in the index ✓
```

Reload search-time synonyms without reindex (ES 7.3+):

```json
// Update synonym file on disk, then reload
POST /products/_reload_search_analyzers
// Search analyzer reloads — new synonyms active immediately
// No reindex needed!
```

Using synonym files instead of inline:

```json
PUT /products
{
  "settings": {
    "analysis": {
      "filter": {
        "synonym_search": {
          "type": "synonym",
          "synonyms_path": "synonyms_ko.txt",
          "updateable": true
        }
      }
    }
  }
}
```

```
# synonyms_ko.txt (in ES config directory)
# Equivalent synonyms (bidirectional)
노트북, 랩탑, laptop
핸드폰, 스마트폰, 휴대폰

# Explicit mapping (unidirectional)
TV => 텔레비전, 티비
AS => 애프터서비스
```

Comparison:

| Aspect | Index-Time | Search-Time |
|--------|-----------|-------------|
| Update synonyms | Requires reindex | Reload API, no reindex |
| Index size | Larger (more tokens) | Normal |
| Query performance | Faster (pre-expanded) | Slightly slower (expands at query time) |
| IDF accuracy | Each synonym has own IDF | Shared IDF (may affect ranking) |
| Recommendation | Stable, rarely-changed synonyms | Frequently updated synonyms |

**Recommendation**: Use search-time synonyms for most cases. The ability to update without reindex far outweighs the minor query-time overhead.

Reference: [Synonym token filter](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-synonym-tokenfilter.html)
