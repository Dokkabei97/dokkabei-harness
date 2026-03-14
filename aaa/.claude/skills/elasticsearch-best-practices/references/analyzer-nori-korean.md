---
title: Configure Nori Analyzer for Korean Morphological Search
impact: HIGH
impactDescription: 5-20x improvement in Korean search recall and precision over standard analyzer
tags: analyzer, nori, korean, morphological-analysis, decompound
---

## Configure Nori Analyzer for Korean Morphological Search

The `standard` analyzer treats Korean text as sequences of individual characters or whitespace-delimited chunks, producing meaningless tokens. The Nori plugin provides morphological analysis that decompounds compound words, handles conjugation, and extracts meaningful Korean tokens.

**Incorrect (standard analyzer on Korean text):**

```json
// standard analyzer on "삼성전자" → ["삼성전자"] as single token
// No decompounding: "서울대학교" stays as one token → "서울" search fails
// No conjugation handling: "먹었다" ≠ "먹다"
POST /_analyze
{
  "analyzer": "standard",
  "text": "삼성전자 무선 이어폰을 구매했습니다"
}
// tokens: ["삼성전자", "무선", "이어폰을", "구매했습니다"]
// "이어폰" search fails because token is "이어폰을" (with particle)
// "구매" search fails because token is "구매했습니다" (conjugated form)
```

**Correct (Nori analyzer with decompound and reading form):**

```json
// Install plugin first: bin/elasticsearch-plugin install analysis-nori
PUT /products
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "nori_mixed": {
          "type": "nori_tokenizer",
          "decompound_mode": "mixed",
          "user_dictionary_rules": [
            "삼성전자",
            "애플워치",
            "에어팟프로"
          ]
        }
      },
      "analyzer": {
        "korean_analyzer": {
          "type": "custom",
          "tokenizer": "nori_mixed",
          "filter": [
            "nori_readingform",
            "lowercase",
            "nori_part_of_speech"
          ]
        }
      },
      "filter": {
        "nori_part_of_speech": {
          "type": "nori_part_of_speech",
          "stoptags": [
            "E", "IC", "J", "MAG", "MAJ",
            "MM", "SP", "SSC", "SSO", "SC",
            "SE", "XPN", "XSA", "XSN", "XSV",
            "UNA", "NA", "VSV"
          ]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "korean_analyzer"
      },
      "description": {
        "type": "text",
        "analyzer": "korean_analyzer"
      },
      "category": { "type": "keyword" }
    }
  }
}
```

**_analyze API comparison — standard vs Nori:**

```json
POST /products/_analyze
{
  "analyzer": "korean_analyzer",
  "text": "삼성전자 무선 이어폰을 구매했습니다"
}
// tokens: ["삼성전자", "삼성", "전자", "무선", "이어폰", "구매"]
// ✓ "삼성전자" preserved as compound AND decompounded into "삼성" + "전자"
// ✓ particle "을" stripped from "이어폰을"
// ✓ conjugation "했습니다" reduced to stem "구매"
```

**Decompound mode options:**

| Mode | Output for "삼성전자" | Use Case |
|------|----------------------|----------|
| `none` | `["삼성전자"]` | Exact compound matching only |
| `discard` | `["삼성", "전자"]` | Component search, no compound |
| `mixed` | `["삼성전자", "삼성", "전자"]` | Both compound and component search (recommended) |

**User dictionary for domain terms:**

```json
// Without user dictionary: "에어팟프로" → ["에어", "팟", "프로"] (wrong segmentation)
// With user dictionary: "에어팟프로" treated as single known compound
"user_dictionary_rules": [
  "에어팟프로",
  "갤럭시버즈",
  "맥북프로",
  "카카오페이"
]
```

Use `decompound_mode: "mixed"` as the default for most Korean search applications — it ensures both exact compound matches and component-based searches work correctly. Add brand names and domain-specific compound words to `user_dictionary_rules` to prevent incorrect segmentation.

Reference: [Nori analysis plugin](https://www.elastic.co/guide/en/elasticsearch/plugins/current/analysis-nori.html)
