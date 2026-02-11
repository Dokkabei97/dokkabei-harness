---
title: Manage User Dictionaries for Domain-Specific Korean Tokenization
impact: HIGH
impactDescription: Fixes mis-tokenization of brand names, product names, and domain terms that break search
tags: analyzer, user-dictionary, nori, korean, brand-names, domain-terms
---

## Manage User Dictionaries for Domain-Specific Korean Tokenization

Built-in dictionaries don't contain brand names, product names, slang, or domain-specific compound nouns. Without a user dictionary, "카카오뱅크" might tokenize as ["카카오", "뱅크"] or worse, and "챗GPT" may not tokenize correctly at all.

**Incorrect (relying solely on built-in dictionary):**

```json
POST /_analyze
{
  "tokenizer": {
    "type": "nori_tokenizer",
    "decompound_mode": "mixed"
  },
  "text": "카카오뱅크에서 토스증권으로 이체"
}
// Without user dict:
// "카카오뱅크" → ["카카오", "뱅크"] (brand split into meaningless parts)
// "토스증권" → ["토스", "증권"] (may lose brand identity)
// Searching "카카오뱅크" as phrase might not match
```

**Correct (user dictionary for domain terms):**

```
# userdict_ko.txt (placed in ES config directory)
# Format: word [cost]
# Lower cost = higher priority for this tokenization
카카오뱅크
토스증권
삼성전자
네이버웹툰
쿠팡로켓배송
챗지피티
```

```json
PUT /fintech
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "nori_custom": {
          "type": "nori_tokenizer",
          "decompound_mode": "mixed",
          "user_dictionary": "userdict_ko.txt"
        }
      },
      "analyzer": {
        "korean_fintech": {
          "type": "custom",
          "tokenizer": "nori_custom",
          "filter": ["nori_readingform", "lowercase"]
        }
      }
    }
  }
}

// Verify tokenization with user dictionary
POST /fintech/_analyze
{
  "analyzer": "korean_fintech",
  "text": "카카오뱅크에서 토스증권으로 이체"
}
// Tokens: ["카카오뱅크", "토스증권", "이체"]
// Brand names preserved as single tokens
```

User dictionary deployment strategies:

| Strategy | Pros | Cons | Best For |
|----------|------|------|----------|
| Config directory file | Simple, file-based | Requires node restart to update | Small, stable dictionaries |
| NFS shared mount | Shared across nodes | Network dependency, requires close_index/open_index to reload | Medium clusters |
| Plugin bundling | Part of deployment pipeline | Requires plugin rebuild and rolling restart | CI/CD managed clusters |
| ConfigMap (K8s) | Cloud-native, version controlled | Requires pod restart | ECK/Kubernetes deployments |

Updating user dictionary without full cluster restart (close/open pattern):

```json
// Step 1: Close the index (brief downtime for this index only)
POST /fintech/_close

// Step 2: Update userdict_ko.txt on all nodes (or update ConfigMap)

// Step 3: Reopen the index (reloads analyzers with new dictionary)
POST /fintech/_open

// Step 4: Verify new terms are recognized
POST /fintech/_analyze
{
  "analyzer": "korean_fintech",
  "text": "새로운브랜드명"
}
```

For zero-downtime dictionary updates, use the alias + reindex pattern:

```json
// 1. Create new index with updated dictionary
// 2. Reindex from old to new
// 3. Atomic alias switch (see mapping-reindex-strategy.md)
```

Reference: [Nori tokenizer user_dictionary](https://www.elastic.co/guide/en/elasticsearch/plugins/current/analysis-nori-tokenizer.html)
