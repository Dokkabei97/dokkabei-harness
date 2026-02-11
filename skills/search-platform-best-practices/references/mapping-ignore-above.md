---
title: Set ignore_above on Keyword Fields to Skip Excessively Long Values
impact: MEDIUM
impactDescription: Prevents disk waste and slow aggregations from abnormally long keyword values
tags: mapping, keyword, ignore_above, storage, aggregation
---

## Set ignore_above on Keyword Fields to Skip Excessively Long Values

Keyword fields index the exact value for filtering, sorting, and aggregations. Without `ignore_above`, abnormally long strings (stack traces, URLs, base64 blobs accidentally sent to a keyword field) are fully indexed, wasting disk space and degrading aggregation performance.

**Incorrect (no ignore_above — all values indexed regardless of length):**

```json
PUT /events
{
  "mappings": {
    "properties": {
      "user_agent": { "type": "keyword" },
      "referrer_url": { "type": "keyword" },
      "error_message": { "type": "keyword" }
    }
  }
}

// A 10KB error stack trace is fully indexed as a single keyword term
POST /events/_doc
{
  "user_agent": "Mozilla/5.0 ...",
  "referrer_url": "https://example.com/very/long/path...(2000 chars)...",
  "error_message": "java.lang.NullPointerException\n\tat com.example...(10000 chars)..."
}
// Keyword inverted index and doc values store the full 10KB string
```

**Correct (ignore_above limits indexing of excessively long values):**

```json
PUT /events
{
  "mappings": {
    "properties": {
      "user_agent": {
        "type": "keyword",
        "ignore_above": 512
      },
      "referrer_url": {
        "type": "keyword",
        "ignore_above": 1024
      },
      "error_message": {
        "type": "keyword",
        "ignore_above": 256
      }
    }
  }
}

// Values longer than the limit are stored in _source but NOT indexed
// They won't appear in term queries, aggregations, or sorting
// The document itself is still indexed — only the oversized field value is skipped
```

Recommended `ignore_above` values by use case:

| Field Type | Suggested Limit | Rationale |
|------------|----------------|-----------|
| Status codes, enums | 64 | Fixed vocabulary |
| Email, username | 256 | Practical max length |
| URL, user agent | 512-1024 | Long but bounded |
| Free-form tags, labels | 256 | Prevent abuse |
| Multi-field `.keyword` sub-field | 256 | Default in dynamic mapping |

Important: `ignore_above` is measured in characters, not bytes. For multi-byte characters (Korean, CJK), a 256-character limit still allows 256 Korean characters. Values exceeding the limit are still stored in `_source` and can be retrieved, but they are invisible to queries, aggregations, and sorting.

Reference: [ignore_above parameter](https://www.elastic.co/guide/en/elasticsearch/reference/current/ignore-above.html)
