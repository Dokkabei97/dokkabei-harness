---
title: Use Ingest Pipelines for Data Transformation Instead of Application-Side Processing
impact: MEDIUM-HIGH
impactDescription: Centralizes data transformation, reduces application complexity, enables reprocessing via reindex
tags: indexing, ingest, pipeline, processor, enrichment, transformation
---

## Use Ingest Pipelines for Data Transformation Instead of Application-Side Processing

Ingest pipelines process documents before indexing — adding fields, transforming data, parsing formats. This centralizes transformation logic in Elasticsearch rather than scattering it across multiple application codebases.

**Incorrect (application-side transformation — duplicated across services):**

```python
# Every indexing service must implement the same transformation
import hashlib
from datetime import datetime

def transform_and_index(doc):
    # Parse timestamp
    doc["@timestamp"] = datetime.fromisoformat(doc["timestamp"]).isoformat()
    # Add geo coordinates from IP
    doc["geo"] = geoip_lookup(doc["client_ip"])
    # Hash PII
    doc["email_hash"] = hashlib.sha256(doc["email"].encode()).hexdigest()
    del doc["email"]
    # Lowercase tags
    doc["tags"] = [t.lower() for t in doc.get("tags", [])]

    es.index(index="events", body=doc)

# Same logic duplicated in Java service, Go service, Python service...
# Each has slightly different implementations — data inconsistency
```

**Correct (ingest pipeline — single source of truth):**

```json
// Define the pipeline once
PUT /_ingest/pipeline/events-pipeline
{
  "description": "Process event documents before indexing",
  "processors": [
    {
      "date": {
        "field": "timestamp",
        "formats": ["ISO8601", "yyyy-MM-dd HH:mm:ss"],
        "target_field": "@timestamp"
      }
    },
    {
      "geoip": {
        "field": "client_ip",
        "target_field": "geo"
      }
    },
    {
      "script": {
        "source": "ctx.email_hash = ctx.email.sha256(); ctx.remove('email');"
      }
    },
    {
      "lowercase": {
        "field": "tags",
        "ignore_missing": true
      }
    },
    {
      "remove": {
        "field": ["timestamp", "client_ip"],
        "ignore_missing": true
      }
    },
    {
      "set": {
        "field": "processed_at",
        "value": "{{{_ingest.timestamp}}}"
      }
    }
  ],
  "on_failure": [
    {
      "set": {
        "field": "_index",
        "value": "events-failed"
      }
    },
    {
      "set": {
        "field": "error.message",
        "value": "{{_ingest.on_failure_message}}"
      }
    }
  ]
}

// All services just index raw documents — pipeline handles transformation
POST /events/_doc?pipeline=events-pipeline
{
  "timestamp": "2024-01-15 10:30:00",
  "client_ip": "203.0.113.50",
  "email": "user@example.com",
  "tags": ["ERROR", "TIMEOUT"],
  "message": "Connection timeout"
}

// Or set as default pipeline for the index
PUT /events/_settings
{
  "index.default_pipeline": "events-pipeline"
}
```

Common processors:

| Processor | Use Case |
|-----------|----------|
| `set` | Add or overwrite fields |
| `remove` | Delete sensitive fields before storage |
| `rename` | Normalize field names |
| `geoip` | Enrich IP addresses with geolocation |
| `user_agent` | Parse user agent strings |
| `date` | Parse date strings into date type |
| `script` | Custom Painless transformations |
| `enrich` | Lookup enrichment data from another index |

Reprocess existing data by reindexing with a pipeline:

```json
POST /_reindex
{
  "source": { "index": "events-old" },
  "dest": { "index": "events-new", "pipeline": "events-pipeline" }
}
```

Reference: [Ingest pipelines](https://www.elastic.co/guide/en/elasticsearch/reference/current/ingest.html)
