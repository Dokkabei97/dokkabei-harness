---
title: Prevent NoSQL Injection by Validating Input Types
impact: HIGH
impactDescription: Blocks unauthorized data access and manipulation
tags: nosql-injection, input-validation, security, operator-injection
---

## Prevent NoSQL Injection by Validating Input Types

MongoDB is vulnerable to operator injection when user input is passed directly into queries without type checking. An attacker can inject query operators like `$gt`, `$ne`, or `$regex`.

**Incorrect (direct user input in query — injectable):**

```javascript
// Express.js route — req.body can contain operators!
app.post("/login", async (req, res) => {
  const user = await db.users.findOne({
    email: req.body.email,
    password: req.body.password
  });
  // Attacker sends: { "email": "admin@test.com", "password": { "$ne": "" } }
  // Query becomes: { email: "admin@test.com", password: { $ne: "" } }
  // Matches any non-empty password — authentication bypass!
});
```

**Correct (validate input types before querying):**

```javascript
app.post("/login", async (req, res) => {
  // Validate that inputs are strings, not objects
  if (typeof req.body.email !== "string" || typeof req.body.password !== "string") {
    return res.status(400).json({ error: "Invalid input" });
  }

  const user = await db.users.findOne({
    email: req.body.email,
    password: req.body.password  // now guaranteed to be a string
  });
});

// Or use a sanitization library
const mongoSanitize = require("express-mongo-sanitize");
app.use(mongoSanitize());  // strips $ and . from user input
```

Key defenses:
1. Always validate input types (string, number, etc.)
2. Use `express-mongo-sanitize` middleware
3. Never pass raw user input to `$where` or `$expr`
4. Use parameterized aggregation with `$let` variables

Reference: [NoSQL Injection Prevention](https://www.mongodb.com/docs/manual/faq/fundamentals/#how-does-mongodb-address-sql-or-query-injection)
