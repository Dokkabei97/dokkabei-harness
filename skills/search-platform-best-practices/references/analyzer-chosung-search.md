---
title: Implement Korean Chosung (Initial Consonant) Search with char_filter
impact: MEDIUM-HIGH
impactDescription: Enables ㅅㅇ → 서울, ㄱㄴ → 강남 style rapid Korean input matching
tags: analyzer, chosung, jamo, char-filter, korean, autocomplete
---

## Implement Korean Chosung (Initial Consonant) Search with char_filter

Korean users frequently search by initial consonants (초성): typing "ㅅㅇ" to find "서울", "ㄱㄴ" for "강남". This requires decomposing Korean syllables into their jamo components and indexing the initial consonant sequence as a searchable field.

**Incorrect (no chosung support — initial consonant search returns nothing):**

```json
PUT /places
{
  "mappings": {
    "properties": {
      "name": { "type": "text", "analyzer": "standard" }
    }
  }
}

POST /places/_doc/1
{ "name": "서울특별시" }

// Searching with chosung returns no results
GET /places/_search
{ "query": { "match": { "name": "ㅅㅇ" } } }
// Zero results — standard analyzer doesn't understand jamo decomposition
```

**Correct (custom chosung analyzer with jamo decomposition):**

```json
PUT /places
{
  "settings": {
    "analysis": {
      "char_filter": {
        "jamo_decompose": {
          "type": "pattern_replace",
          "pattern": "([가-힣])",
          "replacement": ""
        }
      },
      "tokenizer": {
        "chosung_tokenizer": {
          "type": "pattern",
          "pattern": "\\s+"
        }
      },
      "filter": {
        "chosung_extract": {
          "type": "pattern_capture",
          "preserve_original": false,
          "patterns": ["(.+)"]
        }
      },
      "analyzer": {
        "chosung_index_analyzer": {
          "type": "custom",
          "tokenizer": "keyword",
          "filter": ["lowercase"]
        },
        "korean_standard": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": ["nori_readingform", "lowercase"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "korean_standard",
        "fields": {
          "chosung": {
            "type": "text",
            "analyzer": "chosung_index_analyzer"
          }
        }
      }
    }
  }
}
```

A more practical approach uses an ingest pipeline or application-side chosung extraction:

```json
// Application extracts chosung before indexing
// "서울특별시" → chosung: "ㅅㅇㅌㅂㅅ"
// "강남구" → chosung: "ㄱㄴㄱ"

PUT /places
{
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "korean_standard"
      },
      "name_chosung": {
        "type": "text",
        "analyzer": "standard"
      }
    }
  }
}

POST /places/_doc/1
{
  "name": "서울특별시",
  "name_chosung": "ㅅㅇㅌㅂㅅ"
}

POST /places/_doc/2
{
  "name": "강남구",
  "name_chosung": "ㄱㄴㄱ"
}

// Chosung search with prefix query
GET /places/_search
{
  "query": {
    "prefix": { "name_chosung": "ㅅㅇ" }
  }
}
// Matches "서울특별시" ✓
```

For real-time autocomplete, combine chosung with edge_ngram:

```json
PUT /places
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "chosung_ngram": {
          "type": "edge_ngram",
          "min_gram": 1,
          "max_gram": 10
        }
      },
      "analyzer": {
        "chosung_autocomplete": {
          "type": "custom",
          "tokenizer": "chosung_ngram",
          "filter": ["lowercase"]
        },
        "chosung_search": {
          "type": "custom",
          "tokenizer": "keyword",
          "filter": ["lowercase"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name_chosung": {
        "type": "text",
        "analyzer": "chosung_autocomplete",
        "search_analyzer": "chosung_search"
      }
    }
  }
}

// "ㅅ" matches, "ㅅㅇ" matches, "ㅅㅇㅌ" matches progressively
```

Korean jamo decomposition algorithm (for application-side implementation):

```python
# Python example for chosung extraction
CHOSUNG = [
    'ㄱ','ㄲ','ㄴ','ㄷ','ㄸ','ㄹ','ㅁ','ㅂ','ㅃ','ㅅ',
    'ㅆ','ㅇ','ㅈ','ㅉ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'
]

def extract_chosung(text):
    result = []
    for char in text:
        code = ord(char) - 0xAC00
        if 0 <= code < 11172:
            result.append(CHOSUNG[code // 588])
        else:
            result.append(char)
    return ''.join(result)

# extract_chosung("서울특별시") → "ㅅㅇㅌㅂㅅ"
```

Reference: [Pattern replace char_filter](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-pattern-replace-charfilter.html)
