---
title: Use Multi-Field Mappings for Combined Search and Filter Needs
impact: HIGH
impactDescription: Single field supports full-text search, exact filtering, and Korean analysis simultaneously
tags: mapping, multi-field, text, keyword, analyzer, korean
---

## Use Multi-Field Mappings for Combined Search and Filter Needs

When a field needs both full-text search (text) and exact filtering/aggregation (keyword), use multi-field mapping to index the same data with different analyzers. This avoids duplicating data at the application level.

**Incorrect (separate fields for the same data):**

```json
PUT /restaurants
{
  "mappings": {
    "properties": {
      "name_text": { "type": "text" },
      "name_keyword": { "type": "keyword" },
      "name_korean": {
        "type": "text",
        "analyzer": "nori"
      }
    }
  }
}

// Application must index the same value into 3 fields
POST /restaurants/_doc
{
  "name_text": "서울 강남 맛집",
  "name_keyword": "서울 강남 맛집",
  "name_korean": "서울 강남 맛집"
}
```

**Correct (multi-field mapping):**

```json
PUT /restaurants
{
  "settings": {
    "analysis": {
      "analyzer": {
        "korean_analyzer": {
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
        "analyzer": "standard",
        "fields": {
          "keyword": {
            "type": "keyword",
            "ignore_above": 256
          },
          "korean": {
            "type": "text",
            "analyzer": "korean_analyzer"
          }
        }
      }
    }
  }
}

// Single field ingestion
POST /restaurants/_doc
{
  "name": "서울 강남 맛집"
}

// Full-text search (standard analyzer)
GET /restaurants/_search
{ "query": { "match": { "name": "강남 맛집" } } }

// Korean morphological search
GET /restaurants/_search
{ "query": { "match": { "name.korean": "맛집" } } }

// Exact filter or aggregation
GET /restaurants/_search
{
  "query": { "term": { "name.keyword": "서울 강남 맛집" } },
  "aggs": { "top_names": { "terms": { "field": "name.keyword", "size": 10 } } }
}
```

Multi-field best practices:
- `.keyword` sub-field for sorting, aggregation, and exact match
- `.korean` or `.nori` sub-field for Korean morphological analysis
- `.ngram` sub-field for autocomplete (see `analyzer-autocomplete-ngram.md`)
- Set `ignore_above: 256` on keyword sub-fields to skip excessively long values
- Use `copy_to` for cross-field search instead of querying every sub-field

Reference: [Multi-fields](https://www.elastic.co/guide/en/elasticsearch/reference/current/multi-fields.html)
