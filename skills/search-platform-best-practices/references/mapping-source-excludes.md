---
title: Exclude Unnecessary Fields from _source to Reduce Storage and Network Cost
impact: HIGH
impactDescription: 20-50% storage reduction and faster fetch for documents with large unused fields
tags: mapping, _source, storage, network, synthetic-source
---

## Exclude Unnecessary Fields from _source to Reduce Storage and Network Cost

`_source` stores the full original JSON document. Large fields that are only needed for indexing (not retrieval) waste storage and network bandwidth. Use `_source.excludes` or Synthetic Source to optimize.

**Incorrect (storing large embedding vectors and raw content in _source):**

```json
PUT /articles
{
  "mappings": {
    "properties": {
      "title": { "type": "text" },
      "body": { "type": "text" },
      "raw_html": { "type": "text" },
      "embedding": {
        "type": "dense_vector",
        "dims": 768
      }
    }
  }
}

// Every _search returns full _source including 768-dim vector and raw HTML
GET /articles/_search
{
  "query": { "match": { "title": "검색 엔진" } }
}
// Response includes embedding array (6KB+) and raw_html per hit — huge network cost
```

**Correct (_source excludes for large, retrieval-unnecessary fields):**

```json
PUT /articles
{
  "mappings": {
    "_source": {
      "excludes": ["embedding", "raw_html"]
    },
    "properties": {
      "title": { "type": "text" },
      "body": { "type": "text" },
      "raw_html": { "type": "text" },
      "embedding": {
        "type": "dense_vector",
        "dims": 768
      }
    }
  }
}

// Searches return _source without embedding and raw_html
GET /articles/_search
{
  "query": { "match": { "title": "검색 엔진" } }
}
// Response is much smaller — embedding and raw_html excluded from _source
```

For Elasticsearch 8.4+, consider **Synthetic Source** which reconstructs `_source` from doc values and stored fields instead of storing the raw JSON:

```json
PUT /logs
{
  "mappings": {
    "_source": {
      "mode": "synthetic"
    },
    "properties": {
      "timestamp": { "type": "date" },
      "level": { "type": "keyword" },
      "message": { "type": "text", "store": true }
    }
  }
}
// Up to 50% storage savings — _source is reconstructed on-the-fly
```

Important caveats:
- Excluded fields cannot be retrieved via `_source` (use `stored_fields` if needed)
- `_reindex` and `_update` cannot access excluded fields
- Synthetic Source may alter field ordering and formatting of the returned document
- Always verify that excluded fields are truly not needed for retrieval before applying

Reference: [Source filtering](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-source-field.html)
