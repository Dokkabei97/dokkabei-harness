---
title: Use API Keys with Expiration Instead of Shared Credentials
impact: MEDIUM
impactDescription: Scoped, rotatable, auditable access tokens with fine-grained permissions
tags: security, api-key, authentication, rotation, expiration
---

## Use API Keys with Expiration Instead of Shared Credentials

Sharing username/password credentials across services makes rotation difficult and audit trails unclear. API keys provide scoped, expirable, and independently revocable access tokens.

**Incorrect (shared credentials across services):**

```bash
# Every microservice uses the same credentials
curl -u "elastic:shared_password" https://es.example.com:9200/products/_search
# If one service is compromised, all services are compromised
# Cannot identify which service made which request
# Password rotation requires updating every service simultaneously
```

**Correct (per-service API keys with least privilege):**

```json
// Create API key for search service (read-only, 90-day expiry)
POST /_security/api_key
{
  "name": "search-service-prod",
  "expiration": "90d",
  "role_descriptors": {
    "search_only": {
      "indices": [
        {
          "names": ["products", "products-*"],
          "privileges": ["read"]
        }
      ]
    }
  },
  "metadata": {
    "application": "search-service",
    "environment": "production",
    "team": "search-platform"
  }
}
// Returns: { "id": "VuaCfGcBCdbkQm-e5aOx", "api_key": "ui2lp2axTNmsyakw9tvNnw", "encoded": "..." }

// Use the encoded key in requests
// Authorization: ApiKey <encoded-value>
```

```json
// Create API key for indexing pipeline
POST /_security/api_key
{
  "name": "indexing-pipeline-prod",
  "expiration": "30d",
  "role_descriptors": {
    "indexing": {
      "indices": [
        {
          "names": ["products-write"],
          "privileges": ["write", "create_index"]
        }
      ]
    }
  }
}

// List and audit active API keys
GET /_security/api_key?owner=false

// Invalidate compromised key
DELETE /_security/api_key
{
  "ids": ["VuaCfGcBCdbkQm-e5aOx"]
}
```

API key best practices:
- Set expiration on all keys (30-90 days)
- Use metadata to track team, service, and environment
- Automate rotation before expiry
- Monitor `_security/api_key` for stale keys
- Use the most restrictive role descriptors possible

Reference: [API key service](https://www.elastic.co/guide/en/elasticsearch/reference/current/security-api-create-api-key.html)
