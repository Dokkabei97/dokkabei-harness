---
title: Implement kNN/ANN Vector Search with dense_vector and HNSW
impact: LOW
impactDescription: Enables semantic similarity search for recommendation, image search, and RAG pipelines
tags: advanced, vector, knn, ann, dense-vector, hnsw, similarity
---

## Implement kNN/ANN Vector Search with dense_vector and HNSW

Vector search (kNN) finds documents whose embedding vectors are closest to a query vector, enabling semantic search, recommendation engines, and RAG retrieval. Elasticsearch supports approximate nearest neighbor (ANN) search via HNSW algorithm.

**Correct (dense_vector field with kNN search):**

```json
PUT /products
{
  "mappings": {
    "properties": {
      "name": { "type": "text" },
      "description": { "type": "text" },
      "embedding": {
        "type": "dense_vector",
        "dims": 768,
        "index": true,
        "similarity": "cosine",
        "index_options": {
          "type": "hnsw",
          "m": 16,
          "ef_construction": 100
        }
      }
    }
  }
}

// kNN search — find 10 nearest vectors
GET /products/_search
{
  "knn": {
    "field": "embedding",
    "query_vector": [0.12, -0.34, 0.56, ...],
    "k": 10,
    "num_candidates": 100
  },
  "_source": ["name", "description"]
}

// Hybrid search — combine kNN with keyword filters
GET /products/_search
{
  "knn": {
    "field": "embedding",
    "query_vector": [0.12, -0.34, 0.56, ...],
    "k": 10,
    "num_candidates": 100,
    "filter": {
      "term": { "category": "electronics" }
    }
  },
  "query": {
    "match": { "name": "노트북" }
  }
}
// Combines BM25 text score with vector similarity score
```

HNSW tuning parameters:

| Parameter | Default | Description | Trade-off |
|-----------|---------|-------------|-----------|
| `m` | 16 | Connections per layer | Higher = better recall, more memory |
| `ef_construction` | 100 | Build-time beam width | Higher = better graph, slower indexing |
| `num_candidates` | - | Query-time beam width | Higher = better recall, slower search |

Reference: [kNN search](https://www.elastic.co/guide/en/elasticsearch/reference/current/knn-search.html)
