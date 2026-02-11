---
title: Use ELSER or Text Embedding Models for Semantic Search
impact: LOW
impactDescription: Understands query intent beyond keywords — "affordable laptop" finds "budget notebook"
tags: advanced, semantic, elser, embedding, nlp, inference
---

## Use ELSER or Text Embedding Models for Semantic Search

Traditional keyword search fails when users express intent differently from document text. Semantic search uses ML models to understand meaning, so "affordable laptop" matches "budget-friendly notebook" even without shared keywords.

**Using ELSER (Elastic Learned Sparse EncodeR):**

```json
// Step 1: Deploy ELSER model
PUT /_ml/trained_models/.elser_model_2
{
  "input": { "field_names": ["text_field"] }
}

POST /_ml/trained_models/.elser_model_2/deployment/_start
{
  "number_of_allocations": 1,
  "threads_per_allocation": 1
}

// Step 2: Create ingest pipeline for ELSER
PUT /_ingest/pipeline/elser-pipeline
{
  "processors": [
    {
      "inference": {
        "model_id": ".elser_model_2",
        "input_output": [
          { "input_field": "description", "output_field": "description_embedding" }
        ]
      }
    }
  ]
}

// Step 3: Map the sparse vector field
PUT /products
{
  "mappings": {
    "properties": {
      "description": { "type": "text" },
      "description_embedding": { "type": "sparse_vector" }
    }
  }
}

// Step 4: Semantic search with text_expansion
GET /products/_search
{
  "query": {
    "text_expansion": {
      "description_embedding": {
        "model_id": ".elser_model_2",
        "model_text": "가벼운 노트북 추천"
      }
    }
  }
}
```

**Hybrid search (BM25 + semantic) with RRF:**

```json
GET /products/_search
{
  "retriever": {
    "rrf": {
      "retrievers": [
        {
          "standard": {
            "query": { "match": { "description": "가벼운 노트북" } }
          }
        },
        {
          "standard": {
            "query": {
              "text_expansion": {
                "description_embedding": {
                  "model_id": ".elser_model_2",
                  "model_text": "가벼운 노트북"
                }
              }
            }
          }
        }
      ],
      "rank_window_size": 100,
      "rank_constant": 60
    }
  }
}
// RRF combines rankings from BM25 and semantic search without score normalization
```

Reference: [Semantic search](https://www.elastic.co/guide/en/elasticsearch/reference/current/semantic-search.html)
