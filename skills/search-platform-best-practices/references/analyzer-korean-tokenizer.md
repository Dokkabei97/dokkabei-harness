---
title: Choose the Right Korean Tokenizer - Nori vs Mecab vs Custom Dictionary
impact: CRITICAL
impactDescription: Tokenizer choice determines search recall and precision for all Korean queries
tags: analyzer, korean, nori, mecab, tokenizer, morphological-analysis
---

## Choose the Right Korean Tokenizer - Nori vs Mecab vs Custom Dictionary

Korean is an agglutinative language where particles, conjugations, and compound nouns make keyword matching fail without morphological analysis. The tokenizer choice fundamentally determines search quality.

**Incorrect (standard tokenizer for Korean — no morphological analysis):**

```json
POST /_analyze
{
  "tokenizer": "standard",
  "text": "삼성전자 갤럭시 스마트폰을 구매했습니다"
}
// Tokens: ["삼성전자", "갤럭시", "스마트폰을", "구매했습니다"]
// "스마트폰을" includes particle "을" → search for "스마트폰" won't match
// "구매했습니다" includes conjugation → search for "구매" won't match
```

**Correct (Nori tokenizer — built-in Korean morphological analysis):**

```json
// Nori is the official Elasticsearch Korean analyzer plugin
POST /_analyze
{
  "tokenizer": {
    "type": "nori_tokenizer",
    "decompound_mode": "mixed"
  },
  "text": "삼성전자 갤럭시 스마트폰을 구매했습니다"
}
// Tokens: ["삼성", "전자", "삼성전자", "갤럭시", "스마트", "폰", "스마트폰", "구매", "하", "습니다"]
// Particles stripped, compounds decomposed, verb stems extracted
```

Tokenizer comparison:

| Tokenizer | Pros | Cons | Best For |
|-----------|------|------|----------|
| **Nori** (nori_tokenizer) | Official ES plugin, easy installation, good quality, maintained by Elastic | Limited customization, dictionary updates require plugin rebuild | Most Korean search use cases |
| **Mecab** (seunjeon/arirang) | Very accurate, mature dictionary, fast | Community plugin, may lag ES versions, requires separate installation | High-precision NLP tasks |
| **Standard** | No installation needed | No Korean morphology | Non-Korean text only |

Nori setup:

```json
// Install the plugin (on every node, requires restart)
// bin/elasticsearch-plugin install analysis-nori

PUT /korean-search
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "nori_user_dict": {
          "type": "nori_tokenizer",
          "decompound_mode": "mixed",
          "user_dictionary": "userdict_ko.txt"
        }
      },
      "analyzer": {
        "korean": {
          "type": "custom",
          "tokenizer": "nori_user_dict",
          "filter": [
            "nori_readingform",
            "nori_part_of_speech",
            "lowercase"
          ]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "analyzer": "korean"
      }
    }
  }
}
```

Use `_analyze` API to debug tokenization issues:

```json
// Compare tokenization between analyzers
POST /korean-search/_analyze
{
  "analyzer": "korean",
  "text": "서울특별시 강남구 역삼동"
}
// Expected: ["서울", "특별", "시", "서울특별시", "강남", "구", "강남구", "역삼", "동", "역삼동"]

// Verify your custom dictionary is working
POST /korean-search/_analyze
{
  "analyzer": "korean",
  "text": "카카오뱅크 모바일뱅킹"
}
// Without user_dict: ["카카오", "뱅크"] or ["카카오뱅크"] depending on built-in dictionary
// With user_dict entry "카카오뱅크": ensures "카카오뱅크" is a single token
```

Reference: [Nori tokenizer](https://www.elastic.co/guide/en/elasticsearch/plugins/current/analysis-nori-tokenizer.html)
