---
title: Enforce Schema Validation with $jsonSchema
impact: HIGH
impactDescription: Prevents invalid data from entering the database
tags: schema-validation, jsonschema, data-integrity, validation
---

## Enforce Schema Validation with $jsonSchema

MongoDB's flexible schema is powerful but risky. Use `$jsonSchema` validation to enforce required fields, data types, and constraints while keeping schema flexibility where needed.

**Incorrect (no validation — any shape accepted):**

```javascript
// No validation — these all succeed
db.users.insertOne({ name: "Kim" });              // missing email
db.users.insertOne({ email: 123 });                // email is a number
db.users.insertOne({ email: "", name: "", age: -5 }); // invalid values
```

**Correct (schema validation enforces structure):**

```javascript
db.createCollection("users", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["email", "name", "createdAt"],
      properties: {
        email: {
          bsonType: "string",
          pattern: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$",
          description: "must be a valid email"
        },
        name: {
          bsonType: "string",
          minLength: 1,
          maxLength: 200
        },
        age: {
          bsonType: "int",
          minimum: 0,
          maximum: 200
        },
        createdAt: { bsonType: "date" },
        roles: {
          bsonType: "array",
          items: { enum: ["admin", "user", "moderator"] },
          maxItems: 5
        }
      },
      additionalProperties: true  // allow extra fields (schema evolution)
    }
  },
  validationLevel: "moderate",   // only validate inserts and updates to existing valid docs
  validationAction: "error"       // reject invalid documents (vs "warn" for logging only)
});
```

Use `validationLevel: "moderate"` during migration to avoid rejecting existing invalid documents.

Reference: [Schema Validation](https://www.mongodb.com/docs/manual/core/schema-validation/)
