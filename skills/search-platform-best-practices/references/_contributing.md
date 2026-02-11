# Writing Guidelines for Search Platform References

This document provides guidelines for creating effective Elasticsearch/OpenSearch best
practice references that work well with AI agents and LLMs.

## Key Principles

### 1. Concrete Transformation Patterns

Show exact DSL rewrites. Avoid philosophical advice.

**Good:** "Use `filter` context instead of `must` for non-scoring clauses"
**Bad:** "Write good queries"

### 2. Error-First Structure

Always show the problematic pattern first, then the solution. This trains agents
to recognize anti-patterns.

```markdown
**Incorrect (full-text query on keyword field):** [bad example]

**Correct (term-level query on keyword field):** [good example]
```

### 3. Quantified Impact

Include specific metrics. Helps agents prioritize fixes.

**Good:** "10x faster queries", "50% less heap usage", "Eliminates full cluster scan"
**Bad:** "Faster", "Better", "More efficient"

### 4. Self-Contained Examples

Examples should be complete and runnable via REST API. Include index creation
with mappings if context is needed.

```json
// Include mapping definition when needed for clarity
PUT /users
{
  "mappings": {
    "properties": {
      "email": { "type": "keyword" },
      "name": { "type": "text" },
      "created_at": { "type": "date" },
      "is_active": { "type": "boolean" }
    }
  }
}

// Now show the query
GET /users/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "is_active": true } },
        { "term": { "email": "user@example.com" } }
      ]
    }
  }
}
```

### 5. Semantic Naming

Use meaningful index/field names. Names carry intent for LLMs.

**Good:** `users`, `email`, `created_at`, `is_active`
**Bad:** `index1`, `field1`, `data`, `flag`

---

## Code Example Standards

### REST API Formatting

```json
// Use the HTTP method + path format for clarity
PUT /my-index
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1
  }
}

// Not cramped or inconsistent
PUT /my-index {"settings":{"number_of_shards":3,"number_of_replicas":1}}
```

### JSON DSL Formatting

- Use 2-space indentation for JSON bodies
- Place the HTTP method and path on the first line
- Use `//` comments (Dev Tools style) to explain intent
- Keep JSON keys in double quotes

### Comments

- Explain _why_, not _what_
- Highlight performance implications
- Point out common pitfalls

### Language Tags

- `json` - Elasticsearch/OpenSearch DSL (mappings, queries, settings, aggregations)
- `yaml` - ECK manifests, configuration files
- `bash` - curl commands, CLI operations
- `typescript` - Application code (when showing client library usage)
- `python` - Application code (when showing client library usage)

---

## When to Include Application Code

**Default: JSON DSL Only**

Most references should focus on pure Elasticsearch/OpenSearch REST API patterns. This keeps examples portable across clients.

**Include Application Code When:**

- Client library configuration (connection pooling, retry strategies)
- Bulk indexing patterns in application context
- Search result processing patterns
- Client-side query building anti-patterns

**Format for Mixed Examples:**

````markdown
**Incorrect (single-document indexing in loop):**

```python
for doc in documents:
    es.index(index="my-index", body=doc)
```

**Correct (bulk API):**

```python
from elasticsearch.helpers import bulk

actions = [
    {"_index": "my-index", "_source": doc}
    for doc in documents
]
bulk(es, actions, chunk_size=1000)
```
````

---

## Impact Level Guidelines

| Level | Improvement | Use When |
|-------|-------------|----------|
| **CRITICAL** | 10-100x | Wrong field types, missing filter context, cluster misconfiguration, oversharding |
| **HIGH** | 5-20x | Suboptimal analyzers, missing bulk API, poor shard sizing, refresh interval issues |
| **MEDIUM-HIGH** | 2-5x | Inefficient aggregations, missing field data, suboptimal bool queries |
| **MEDIUM** | 1.5-3x | ILM policy tuning, replica adjustments, query template optimization |
| **LOW-MEDIUM** | 1.2-2x | Slow log tuning, monitoring setup, diagnostic patterns |
| **LOW** | Incremental | Advanced patterns, vector search optimization, edge cases |

---

## Reference Standards

**Primary Sources:**

- Official Elasticsearch documentation
- Official OpenSearch documentation
- Elastic blog (engineering deep-dives)
- OpenSearch project blog
- Elasticsearch: The Definitive Guide (concepts still relevant)

**Format:**

```markdown
Reference:
[Elasticsearch Mapping](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html)
```

---

## Review Checklist

Before submitting a reference:

- [ ] Title is clear and action-oriented
- [ ] Impact level matches the performance gain
- [ ] impactDescription includes quantification
- [ ] Explanation is concise (1-2 sentences)
- [ ] Has at least 1 **Incorrect** JSON DSL example
- [ ] Has at least 1 **Correct** JSON DSL example
- [ ] JSON uses semantic naming for indexes and fields
- [ ] Comments explain _why_, not _what_
- [ ] REST API format uses `METHOD /path` convention
- [ ] Trade-offs mentioned if applicable
- [ ] Reference links included
