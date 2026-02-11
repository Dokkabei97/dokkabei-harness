---
title: Always Enable Authentication in Production
impact: CRITICAL
impactDescription: Prevents unauthorized access to entire database
tags: authentication, auth, scram, x509, security
---

## Always Enable Authentication in Production

Running MongoDB without authentication allows anyone with network access to read, modify, or delete all data. Always enable authentication, even in development.

**Incorrect (no authentication):**

```javascript
// mongod started without --auth
// Anyone can connect and do anything:
// mongosh "mongodb://server:27017"
db.getSiblingDB("admin").getUsers();  // no authentication required
db.dropDatabase();                     // disaster — no auth check
```

**Correct (authentication enabled with SCRAM):**

```javascript
// 1. Start mongod with authentication
// mongod --auth --keyFile /path/to/keyfile

// 2. Create admin user first
db.getSiblingDB("admin").createUser({
  user: "admin",
  pwd: passwordPrompt(),
  roles: [{ role: "userAdminAnyDatabase", db: "admin" }]
});

// 3. Create application-specific user with minimal privileges
db.getSiblingDB("myApp").createUser({
  user: "appUser",
  pwd: passwordPrompt(),
  roles: [{ role: "readWrite", db: "myApp" }]
});

// 4. Connect with credentials
// mongosh "mongodb://appUser:password@server:27017/myApp?authSource=myApp"
```

For Atlas, authentication is always enabled. Use database users with scoped roles.

Reference: [Enable Authentication](https://www.mongodb.com/docs/manual/tutorial/enable-authentication/)
