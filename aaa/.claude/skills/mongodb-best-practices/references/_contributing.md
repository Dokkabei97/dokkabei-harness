# Writing Guidelines for MongoDB References

This document provides guidelines for creating effective MongoDB best
practice references that work well with AI agents and LLMs.

## Key Principles

### 1. Concrete Transformation Patterns

Show exact query/schema rewrites. Avoid philosophical advice.

**Good:** "Use `{ status: 1, createdAt: 1 }` compound index instead of
separate `{ status: 1 }` and `{ createdAt: 1 }` indexes"
**Bad:** "Design good schemas"

### 2. Error-First Structure

Always show the problematic pattern first, then the solution. This trains agents
to recognize anti-patterns.

```markdown
**Incorrect (full collection scan):** [bad example]

**Correct (index-backed query):** [good example]
```

### 3. Quantified Impact

Include specific metrics. Helps agents prioritize fixes.

**Good:** "10x faster queries", "50% less memory usage", "Eliminates COLLSCAN"
**Bad:** "Faster", "Better", "More efficient"

### 4. Self-Contained Examples

Examples should be complete and runnable in mongosh (or close to it). Include
collection setup if context is needed.

```javascript
// Include collection setup when needed for clarity
db.createCollection("users", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["email", "name"],
      properties: {
        email: { bsonType: "string" },
        name: { bsonType: "string" },
        deletedAt: { bsonType: ["date", "null"] }
      }
    }
  }
});

// Now show the index
db.users.createIndex(
  { email: 1 },
  { partialFilterExpression: { deletedAt: null } }
);
```

### 5. Semantic Naming

Use meaningful collection/field names. Names carry intent for LLMs.

**Good:** `users`, `email`, `createdAt`, `isActive`
**Bad:** `collection1`, `field1`, `val`, `flag`

---

## Code Example Standards

### mongosh Formatting

```javascript
// Use clear formatting with consistent style
db.orders.createIndex(
  { status: 1, createdAt: -1 },
  { partialFilterExpression: { status: { $ne: "archived" } } }
);

// Not cramped or unclear
db.orders.createIndex({status:1,createdAt:-1},{partialFilterExpression:{status:{$ne:"archived"}}});
```

### Comments

- Explain _why_, not _what_
- Highlight performance implications
- Point out common pitfalls

### Language Tags

- `javascript` - mongosh queries and Node.js driver code
- `json` - MongoDB documents, configuration, aggregation pipeline output
- `typescript` - Application code with MongoDB driver (when needed)

---

## When to Include Node.js Driver Code

**Default: mongosh Only**

Most references should focus on mongosh patterns. This keeps examples portable
and concise.

**Include Node.js Driver Code When:**

- Connection pooling configuration
- Retry logic and error handling
- Transaction management in application context
- ODM anti-patterns (N+1 in Mongoose)
- Driver-specific options (readPreference, writeConcern)

**Format for Mixed Examples:**

````markdown
**Incorrect (N+1 queries in application):**

```javascript
// Mongoose anti-pattern: loading relations in a loop
const users = await User.find({ active: true });
for (const user of users) {
  const orders = await Order.find({ userId: user._id });
}
```

**Correct (batch query with $in):**

```javascript
const users = await User.find({ active: true });
const userIds = users.map(u => u._id);
const orders = await Order.find({ userId: { $in: userIds } });
```
````

---

## Impact Level Guidelines

| Level | Improvement | Use When |
|-------|-------------|----------|
| **CRITICAL** | 10-100x | Missing indexes, collection scans, unbounded arrays, oversized documents |
| **HIGH** | 5-20x | Wrong index field order, unoptimized $lookup, missing projections |
| **MEDIUM-HIGH** | 2-5x | N+1 queries, poor embedding decisions, suboptimal aggregation |
| **MEDIUM** | 1.5-3x | Redundant indexes, suboptimal write/read concern |
| **LOW-MEDIUM** | 1.2-2x | Profiler tuning, read preference optimization |
| **LOW** | Incremental | Advanced patterns, edge cases |

---

## Reference Standards

**Primary Sources:**

- Official MongoDB documentation
- MongoDB University courses
- MongoDB blog and engineering articles
- Established community resources (Percona, Studio 3T)

**Format:**

```markdown
Reference:
[MongoDB Indexes](https://www.mongodb.com/docs/manual/indexes/)
```

---

## Review Checklist

Before submitting a reference:

- [ ] Title is clear and action-oriented
- [ ] Impact level matches the performance gain
- [ ] impactDescription includes quantification
- [ ] Explanation is concise (1-2 sentences)
- [ ] Has at least 1 **Incorrect** code example
- [ ] Has at least 1 **Correct** code example
- [ ] Code uses semantic naming
- [ ] Comments explain _why_, not _what_
- [ ] Trade-offs mentioned if applicable
- [ ] Reference links included
- [ ] `npm run validate` passes
- [ ] `npm run build` generates correct output
