---
title: Use Field-Level and Document-Level Security for Fine-Grained Access Control
impact: MEDIUM-HIGH
impactDescription: Restricts access to specific fields and documents within shared indices
tags: security, field-level, document-level, fls, dls, multi-tenant
---

## Use Field-Level and Document-Level Security for Fine-Grained Access Control

When multiple teams or tenants share the same index, field-level security (FLS) hides sensitive fields and document-level security (DLS) restricts which documents a user can see.

**Incorrect (separate indices per tenant — operational overhead):**

```json
// Creating per-tenant indices increases shard count and management complexity
PUT /orders-tenant-a
PUT /orders-tenant-b
PUT /orders-tenant-c
// With 100 tenants = 100 indices with their own shards, templates, ILM policies
```

**Correct (shared index with document-level security):**

```json
// All tenants in one index
PUT /orders
{
  "mappings": {
    "properties": {
      "tenant_id": { "type": "keyword" },
      "customer_name": { "type": "text" },
      "customer_email": { "type": "keyword" },
      "amount": { "type": "double" },
      "internal_notes": { "type": "text" }
    }
  }
}

// Role with document-level security: only see own tenant's documents
PUT /_security/role/tenant_a_user
{
  "indices": [
    {
      "names": ["orders"],
      "privileges": ["read"],
      "query": {
        "term": { "tenant_id": "tenant-a" }
      }
    }
  ]
}

// Role with field-level security: hide sensitive fields
PUT /_security/role/support_agent
{
  "indices": [
    {
      "names": ["orders"],
      "privileges": ["read"],
      "field_security": {
        "grant": ["customer_name", "amount", "tenant_id"],
        "except": ["customer_email", "internal_notes"]
      }
    }
  ]
}

// Combined DLS + FLS: tenant-specific, field-restricted
PUT /_security/role/tenant_a_support
{
  "indices": [
    {
      "names": ["orders"],
      "privileges": ["read"],
      "query": {
        "term": { "tenant_id": "tenant-a" }
      },
      "field_security": {
        "grant": ["customer_name", "amount", "tenant_id"]
      }
    }
  ]
}
```

Performance note: DLS adds a filter to every query, similar to a bool filter. For high-throughput scenarios, ensure the DLS field (`tenant_id`) is a keyword type for efficient filtering.

Reference: [Field and document level security](https://www.elastic.co/guide/en/elasticsearch/reference/current/field-and-document-access-control.html)
