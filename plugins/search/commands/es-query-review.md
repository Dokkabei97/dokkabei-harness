---
name: es-query-review
description: "Elasticsearch query DSL review with anti-pattern detection, complexity rating, and optimization suggestions"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /es-query-review - Elasticsearch Query DSL Review

## Triggers
- Elasticsearch query performance tuning or optimization requests
- Code review involving ES query construction in Kotlin services
- Standalone ES query JSON file validation
- Pre-deploy query safety checks for production indices

## Usage
```
/es-query-review [target] [options]

Options:
  --explain           Show conceptual execution plan for each query
  --suggest-rewrite   Generate optimized query alternative
```

## Behavioral Flow

### Standard Flow
1. **Discover**: Scan target path for ES queries — Kotlin source files (QueryBuilders, SearchRequest, JSON string literals) and standalone JSON query files
2. **Parse**: Extract and normalize query DSL structures into analyzable form, resolving Kotlin builder chains to equivalent JSON DSL
3. **Analyze**: Apply anti-pattern checklist against each query and rate complexity
4. **Report**: Present findings with severity, location, and actionable guidance

### Anti-Pattern Checklist
| Anti-Pattern | Severity | Description |
|---|---|---|
| Scoring in filter context | High | `must` used where `filter` suffices, wasting CPU on score calculation |
| Missing `_source` filtering | Medium | Full `_source` returned when only specific fields are needed |
| Unbounded aggregations | Critical | `terms` agg without explicit `size`, defaults may return excessive buckets |
| Deep pagination | Critical | `from` + `size` exceeds 10,000 — use `search_after` or scroll instead |
| Nested query depth > 3 | High | Deeply nested `bool` queries degrade readability and performance |
| Script where native works | Medium | `script_score` or `script` fields used where native query/agg features suffice |
| Leading wildcard | High | `wildcard` or `query_string` with leading `*` bypasses inverted index |
| Missing filter context | Medium | `must` clause used for exact-match or boolean conditions that don't need scoring |

### Complexity Rating
- **Simple**: Single clause queries, basic filters, standard aggregations
- **Moderate**: Multi-clause bool queries, nested aggregations, function_score with simple functions
- **Complex**: Multi-level nested queries, pipeline aggregations, custom script scoring
- **Dangerous**: Unbounded aggs + deep pagination, leading wildcards on high-cardinality fields, regex on analyzed fields

## Tool Coordination
- **Glob**: Discover Kotlin source files and JSON query files in target path
- **Grep**: Locate QueryBuilders, SearchRequest, RestHighLevelClient, and JSON DSL patterns
- **Read**: Extract full query construction context from source files
- **Bash**: Validate JSON syntax of extracted query bodies

## Key Patterns
- **Builder Chain Resolution**: Trace Kotlin QueryBuilders / SearchSourceBuilder chains to reconstruct the equivalent JSON DSL
- **Context Awareness**: Distinguish `query` vs `filter` vs `post_filter` vs `aggs` contexts
- **Cascade Detection**: Identify queries where multiple anti-patterns compound (e.g., unbounded agg inside a script-scored query)

## Examples

### Review Kotlin ES queries in a service
```
/es-query-review src/main/kotlin/com/example/search/
# Scans all Kotlin files for ES query patterns
# Reports anti-patterns with file:line references
```

### Review with execution plan
```
/es-query-review src/main/kotlin/com/example/search/ProductSearchService.kt --explain
# Analyzes queries and shows conceptual execution plan
# Explains how ES will process each query internally
```

### Review and suggest rewrites
```
/es-query-review queries/ --suggest-rewrite
# Reviews standalone JSON query files
# Generates optimized alternatives for problematic queries
```

## Output Format

### Standard Output
```
## ES Query Review
- Target: [path]
- Queries Found: [count]
- Files Scanned: [count]

## Query Analysis

### Query 1 — [File:Line or filename]
- Complexity: [Simple|Moderate|Complex|Dangerous]
- Anti-Patterns:
  - [CRITICAL] Unbounded aggregation: `terms` agg on `category` without explicit size
  - [HIGH] Scoring in filter context: `must` clause for exact `status` match → use `filter`
- Recommendation: Move exact-match clauses to `filter`, add `size: 100` to terms agg

### Query 2 — [File:Line or filename]
...

## Summary
- Critical: [count] | High: [count] | Medium: [count]
- Overall Risk: [Low|Medium|High|Critical]
```

### With --explain
```
### Execution Plan (Query 1)
1. Filter phase: [filters applied, cache eligibility]
2. Query phase: [scoring clauses, cost estimate]
3. Aggregation phase: [agg tree traversal, memory estimate]
4. Fetch phase: [_source fields, doc count]
```

### With --suggest-rewrite
```
### Suggested Rewrite (Query 1)
#### Before
{ "query": { "bool": { "must": [{ "term": { "status": "active" }}] }}}

#### After
{ "query": { "bool": { "filter": [{ "term": { "status": "active" }}] }}}

#### Rationale
- Moved exact-match `term` from `must` to `filter` to skip scoring and enable filter cache
```

## Boundaries

**Will:**
- Extract and analyze ES queries from Kotlin source code and JSON files
- Detect common anti-patterns and rate query complexity
- Generate conceptual execution plans and optimized rewrites
- Provide severity-rated findings with precise file locations

**Will Not:**
- Execute queries against a live Elasticsearch cluster
- Analyze index mappings or cluster settings (use `/es-mapping-review` instead)
- Modify source code without explicit user consent
- Profile actual query execution time or resource consumption
