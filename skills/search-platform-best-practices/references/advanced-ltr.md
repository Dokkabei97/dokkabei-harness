---
title: Implement Learning to Rank for Business-Optimized Search Results
impact: LOW
impactDescription: ML-powered ranking incorporates click-through data, revenue, and relevance signals
tags: advanced, ltr, learning-to-rank, ranking, machine-learning
---

## Implement Learning to Rank for Business-Optimized Search Results

BM25 ranks by text relevance alone. Learning to Rank (LTR) uses an ML model trained on features like click-through rate, conversion, recency, and popularity to produce business-aligned rankings.

**LTR workflow:**

```json
// Step 1: Define features
PUT /_ltr/_featureset/product_features
{
  "featureset": {
    "features": [
      {
        "name": "title_match",
        "params": ["keywords"],
        "template_language": "mustache",
        "template": {
          "match": { "title": "{{keywords}}" }
        }
      },
      {
        "name": "description_match",
        "params": ["keywords"],
        "template_language": "mustache",
        "template": {
          "match": { "description": "{{keywords}}" }
        }
      },
      {
        "name": "popularity",
        "params": [],
        "template_language": "mustache",
        "template": {
          "function_score": {
            "field_value_factor": { "field": "click_count" }
          }
        }
      },
      {
        "name": "recency",
        "params": [],
        "template_language": "mustache",
        "template": {
          "function_score": {
            "linear": {
              "updated_at": { "origin": "now", "scale": "7d" }
            }
          }
        }
      }
    ]
  }
}

// Step 2: Train model offline with judgment lists (query + document + grade)
// Use tools like XGBoost/LightGBM/RankLib to train a ranking model

// Step 3: Upload trained model
POST /_ltr/_featureset/product_features/_createmodel
{
  "model": {
    "name": "product_ranker_v1",
    "model": {
      "type": "model/ranklib",
      "definition": "..."
    }
  }
}

// Step 4: Use LTR in search
GET /products/_search
{
  "query": {
    "sltr": {
      "_name": "logged_features",
      "featureset": "product_features",
      "params": { "keywords": "노트북" },
      "model": "product_ranker_v1"
    }
  }
}
```

Alternative: Use `function_score` for simpler business ranking without ML training:

```json
GET /products/_search
{
  "query": {
    "function_score": {
      "query": { "match": { "name": "노트북" } },
      "functions": [
        { "field_value_factor": { "field": "sales_count", "modifier": "log1p", "factor": 0.5 } },
        { "gauss": { "updated_at": { "origin": "now", "scale": "30d" } } }
      ],
      "score_mode": "sum",
      "boost_mode": "multiply"
    }
  }
}
```

Reference: [Learning to Rank plugin](https://elasticsearch-learning-to-rank.readthedocs.io/)
