---
title: Implement Role-Based Access Control at Index, Field, and Document Level
impact: MEDIUM-HIGH
impactDescription: Principle of least privilege — prevents accidental or malicious data access across teams
tags: security, rbac, role, access-control, privilege, index-level
---

## Implement Role-Based Access Control at Index, Field, and Document Level

Without RBAC, every authenticated user has the same access. In multi-tenant or multi-team environments, RBAC ensures users only access their authorized indices, fields, and documents.

**Incorrect (all users use the elastic superuser):**

```json
// Every application uses the elastic superuser
// Any service can read/write/delete any index
// A bug in one service can corrupt another team's data
```

**Correct (least-privilege roles per use case):**

```json
// Read-only role for search API
PUT /_security/role/search_api
{
  "indices": [
    {
      "names": ["products", "products-*"],
      "privileges": ["read", "view_index_metadata"]
    }
  ]
}

// Write role for indexing service
PUT /_security/role/indexing_service
{
  "indices": [
    {
      "names": ["products-write"],
      "privileges": ["write", "create_index", "view_index_metadata"]
    }
  ]
}

// Admin role for specific indices
PUT /_security/role/products_admin
{
  "cluster": ["monitor"],
  "indices": [
    {
      "names": ["products*"],
      "privileges": ["all"]
    }
  ]
}

// Create user with specific role
PUT /_security/user/search_api_user
{
  "password": "secure_password_here",
  "roles": ["search_api"]
}
```

See `security-field-document-level.md` for field-level and document-level security.

Reference: [Role-based access control](https://www.elastic.co/guide/en/elasticsearch/reference/current/authorization.html)
