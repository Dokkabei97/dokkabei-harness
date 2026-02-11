---
title: Use Index Templates and Component Templates for Consistent Index Configuration
impact: HIGH
impactDescription: Prevents configuration drift, ensures all indices have correct mappings, settings, and aliases
tags: shard, template, component-template, index-template, configuration, consistency
---

## Use Index Templates and Component Templates for Consistent Index Configuration

Without templates, every index must be manually configured with correct mappings, settings, and aliases. This leads to inconsistent configurations, forgotten settings, and mapping conflicts across indices.

**Incorrect (manual index creation with copy-paste settings):**

```json
// Each index created manually — settings drift over time
PUT /logs-2024-01
{
  "settings": { "number_of_shards": 3, "number_of_replicas": 1 },
  "mappings": { "properties": { "timestamp": { "type": "date" }, "message": { "type": "text" } } }
}

PUT /logs-2024-02
{
  "settings": { "number_of_shards": 5, "number_of_replicas": 1 },
  "mappings": { "properties": { "timestamp": { "type": "date" }, "message": { "type": "text" }, "level": { "type": "keyword" } } }
}
// Shard count changed, mapping added a new field — inconsistency
```

**Correct (composable index templates with component templates):**

```json
// Step 1: Create reusable component templates
PUT /_component_template/base-settings
{
  "template": {
    "settings": {
      "number_of_replicas": 1,
      "refresh_interval": "5s",
      "index.mapping.total_fields.limit": 2000
    }
  }
}

PUT /_component_template/korean-analyzer
{
  "template": {
    "settings": {
      "analysis": {
        "analyzer": {
          "korean": {
            "type": "custom",
            "tokenizer": "nori_tokenizer",
            "filter": ["nori_readingform", "lowercase"]
          }
        }
      }
    }
  }
}

PUT /_component_template/logs-mappings
{
  "template": {
    "mappings": {
      "dynamic": "strict",
      "properties": {
        "@timestamp": { "type": "date" },
        "level": { "type": "keyword" },
        "service": { "type": "keyword" },
        "message": { "type": "text" },
        "trace_id": { "type": "keyword" }
      }
    }
  }
}

// Step 2: Compose into an index template
PUT /_index_template/logs-template
{
  "index_patterns": ["logs-*"],
  "priority": 200,
  "composed_of": ["base-settings", "logs-mappings"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "index.lifecycle.name": "logs-policy"
    }
  }
}

// Step 3: Any index matching "logs-*" automatically gets correct configuration
PUT /logs-2024-03
{}
// Automatically has: 1 shard, 1 replica, strict mapping, all fields defined
```

Template priority and composition:

```json
// Higher priority templates override lower ones
PUT /_index_template/logs-high-volume
{
  "index_patterns": ["logs-api-*"],
  "priority": 300,
  "composed_of": ["base-settings", "logs-mappings"],
  "template": {
    "settings": {
      "number_of_shards": 3
    }
  }
}
// logs-api-* gets 3 shards (priority 300)
// logs-other-* gets 1 shard (falls through to priority 200 template)
```

Verify template application:

```json
// Simulate which template applies to an index name
POST /_index_template/_simulate_index/logs-api-2024-03

// List all templates
GET /_index_template?filter_path=index_templates.name
```

Reference: [Index templates](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-templates.html), [Component templates](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-component-template.html)
