---
title: Build Custom Analyzer Chains with Tokenizer + Token Filter Pipeline
impact: HIGH
impactDescription: Precise control over text analysis, eliminates search relevance issues from default analyzer limitations
tags: analyzer, custom, tokenizer, token-filter, char-filter, analysis-chain
---

## Build Custom Analyzer Chains with Tokenizer + Token Filter Pipeline

The default `standard` analyzer tokenizes by Unicode word boundaries and lowercases — insufficient for Korean, CJK, or domain-specific search. Custom analyzers compose a char_filter → tokenizer → token_filter pipeline tailored to your language and domain.

**Incorrect (standard analyzer for Korean text):**

```json
PUT /articles
{
  "mappings": {
    "properties": {
      "title": { "type": "text" }
    }
  }
}

// Standard analyzer tokenizes Korean poorly
POST /articles/_analyze
{
  "analyzer": "standard",
  "text": "대한민국의 수도는 서울특별시입니다"
}
// Tokens: ["대한민국의", "수도는", "서울특별시입니다"]
// No morphological analysis — particles attached, compounds not decomposed
// Searching "서울" won't match "서울특별시입니다"
```

**Correct (custom analyzer chain for Korean):**

```json
PUT /articles
{
  "settings": {
    "analysis": {
      "char_filter": {
        "normalize_special": {
          "type": "mapping",
          "mappings": [
            "ㆍ => ·",
            "～ => ~"
          ]
        }
      },
      "tokenizer": {
        "nori_mixed": {
          "type": "nori_tokenizer",
          "decompound_mode": "mixed",
          "discard_punctuation": true
        }
      },
      "filter": {
        "nori_posfilter": {
          "type": "nori_part_of_speech",
          "stoptags": [
            "E", "IC", "J", "MAG", "MAJ",
            "MM", "SP", "SSC", "SSO", "SC",
            "SE", "XPN", "XSA", "XSN", "XSV",
            "UNA", "NA", "VSV"
          ]
        }
      },
      "analyzer": {
        "korean_analyzer": {
          "type": "custom",
          "char_filter": ["normalize_special", "html_strip"],
          "tokenizer": "nori_mixed",
          "filter": [
            "nori_readingform",
            "nori_posfilter",
            "lowercase",
            "trim"
          ]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "analyzer": "korean_analyzer"
      }
    }
  }
}

// Now Korean morphological analysis works correctly
POST /articles/_analyze
{
  "analyzer": "korean_analyzer",
  "text": "대한민국의 수도는 서울특별시입니다"
}
// Tokens: ["대한", "민국", "대한민국", "수도", "서울", "특별", "시", "서울특별시"]
// Particles removed, compounds decomposed, sub-tokens available
```

Analyzer chain processing order:

```
Input Text: "  <b>서울특별시</b>의 맛집 ～추천  "
     │
     ▼
[char_filter: html_strip]     → "  서울특별시의 맛집 ～추천  "
[char_filter: normalize]       → "  서울특별시의 맛집 ~추천  "
     │
     ▼
[tokenizer: nori_tokenizer]   → ["서울", "특별", "시", "서울특별시", "맛", "집", "맛집", "추천"]
     │
     ▼
[filter: nori_part_of_speech] → ["서울", "특별", "시", "서울특별시", "맛", "집", "맛집", "추천"]
[filter: nori_readingform]    → (한자 → 한글 변환)
[filter: lowercase]           → (이미 소문자)
[filter: trim]                → (공백 제거)
     │
     ▼
Final Tokens: ["서울", "특별", "시", "서울특별시", "맛", "집", "맛집", "추천"]
```

Key principle: Use `search_analyzer` to decouple index-time and search-time analysis when needed (e.g., ngram at index time, standard at search time).

```json
"title": {
  "type": "text",
  "analyzer": "ngram_analyzer",
  "search_analyzer": "standard"
}
```

Reference: [Custom analyzers](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-custom-analyzer.html)
