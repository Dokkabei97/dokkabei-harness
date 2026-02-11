---
title: Apply Least Privilege Principle with Role-Based Access Control
impact: HIGH
impactDescription: Limits blast radius of compromised credentials
tags: rbac, roles, least-privilege, access-control, security
---

## Apply Least Privilege Principle with Role-Based Access Control

Grant users the minimum permissions needed. A compromised read-only credential is far less damaging than a compromised admin credential.

**Incorrect (overly broad permissions):**

```javascript
// Application user with root access — one injection away from disaster
db.getSiblingDB("admin").createUser({
  user: "appUser",
  pwd: "password",
  roles: [{ role: "root", db: "admin" }]
});
```

**Correct (scoped custom roles):**

```javascript
// Create custom role with specific collection permissions
db.getSiblingDB("myApp").createRole({
  role: "orderServiceRole",
  privileges: [
    {
      resource: { db: "myApp", collection: "orders" },
      actions: ["find", "insert", "update"]  // no delete, no drop
    },
    {
      resource: { db: "myApp", collection: "products" },
      actions: ["find"]  // read-only access to products
    }
  ],
  roles: []
});

// Create user with custom role
db.getSiblingDB("myApp").createUser({
  user: "orderService",
  pwd: passwordPrompt(),
  roles: [{ role: "orderServiceRole", db: "myApp" }]
});
```

**Role hierarchy for typical applications:**
- `read` — read-only access (reporting, analytics)
- `readWrite` — read + write (application services)
- Custom roles — fine-grained per-collection access
- `dbAdmin` — index/stats management (DBA tools)
- `userAdmin` — user management only (identity team)

Reference: [Role-Based Access Control](https://www.mongodb.com/docs/manual/core/authorization/)
