---
name: es-mapping-review
description: "Elasticsearch index mapping review with field type validation, analyzer checks, and compatibility analysis"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /es-mapping-review - Elasticsearch Index Mapping Review

## Triggers
- New index mapping design review before deployment
- Mapping change validation to detect breaking changes
- Korean search analyzer (nori) configuration audit
- Storage optimization and field type correctness checks

## Usage
```
/es-mapping-review [target] [options]

Options:
  --check-compatibility [old-mapping]   Compare mapping versions, detect breaking changes
  --suggest-optimizations               Recommend copy_to, flattened type, runtime fields
```

## Behavioral Flow

### Standard Flow
1. **Load**: Read mapping JSON files from target path, supporting both standalone mapping files and index template definitions
2. **Validate**: Apply field-level and structure-level validation rules against each mapping
3. **Compare** (optional): When `--check-compatibility` is provided, diff old vs new mapping for breaking changes
4. **Report**: Present findings with severity, field paths, and corrective guidance

### Validation Rules
| Issue | Severity | Description |
|---|---|---|
| `text` without `keyword` sub-field | High | Full-text field lacks exact-match capability for aggregations and sorting |
| Date stored as `text` | Critical | Date fields lose range query and date math capability |
| Numeric stored as `keyword` | High | Numeric fields lose range query efficiency and numeric aggregations |
| Missing `ignore_above` on keyword | Medium | Unbounded keyword values waste storage and can cause indexing failures |
| Incorrect `nori` decompound_mode | High | Wrong mode (`none`/`discard`/`mixed`) degrades Korean search quality |
| `text` without analyzer specification | Medium | Relies on default analyzer, may not match search requirements |
| `nested` where `object` suffices | Medium | Nested type adds overhead — only needed when array element independence matters |
| `dynamic: true` on production index | High | Uncontrolled field creation risks mapping explosion and cluster instability |
| Missing `doc_values: false` on text-only fields | Low | Text fields with doc_values enabled waste disk (default disabled, but check explicit settings) |
| Excessive field count (> 1000) | High | Large mappings increase cluster state size and slow down queries |

### Korean Analyzer Checks
- `nori_tokenizer` presence and `decompound_mode` setting (`mixed` recommended for general search)
- Custom `nori_part_of_speech` stop tag configuration
- `nori_readingform` filter for Hanja-to-Hangul conversion
- Synonym filter ordering relative to nori tokenizer in analysis chain
- `user_dictionary` path validity for custom compound noun splitting

### Compatibility Check Rules (--check-compatibility)
| Change Type | Breaking? | Description |
|---|---|---|
| Field type change | Yes | Changing `keyword` to `text` or vice versa requires reindex |
| Analyzer change on existing field | Yes | Existing documents retain old analysis — new docs differ |
| Field removal | No | Removed fields remain in existing documents |
| New field addition | No | Safe — existing documents lack the field but queries work |
| `nested` to `object` | Yes | Query semantics change, existing nested docs incompatible |
| Parameter change (e.g., `ignore_above`) | Conditional | Some params apply only to new docs |

## Tool Coordination
- **Glob**: Discover mapping JSON files, index templates, and component templates
- **Read**: Load mapping definitions and analyzer configurations
- **Grep**: Locate mapping references in Kotlin code and configuration files
- **Bash**: Validate JSON syntax of mapping files

## Key Patterns
- **Field Path Tracking**: Report issues with full dotted field path (e.g., `properties.address.properties.city`)
- **Analyzer Chain Validation**: Verify tokenizer → filter ordering and compatibility
- **Template Resolution**: Resolve component templates into final merged mapping for analysis

## Examples

### Review a mapping file
```
/es-mapping-review mappings/product-index.json
# Validates field types, analyzers, and structural issues
# Reports findings with field paths and severity
```

### Check compatibility between versions
```
/es-mapping-review mappings/product-v2.json --check-compatibility mappings/product-v1.json
# Compares old vs new mapping
# Identifies breaking changes requiring reindex
```

### Review with optimization suggestions
```
/es-mapping-review mappings/ --suggest-optimizations
# Reviews all mapping files in directory
# Suggests copy_to, flattened type, and runtime field opportunities
```

## Output Format

### Standard Output
```
## Mapping Review
- Target: [path]
- Index: [index name]
- Fields: [total count]
- Analyzers: [custom analyzer count]

## Field Validation

### Critical Issues
- `order_date` (text) → Should be `date` with format `yyyy-MM-dd'T'HH:mm:ss`
- `dynamic: true` on root mapping → Set explicit `dynamic: strict` for production

### High Issues
- `product_name` (text) → Missing `keyword` sub-field for aggregation/sorting
- `price` (keyword) → Should be `scaled_float` or `long` for range queries
- `nori_tokenizer.decompound_mode: none` → Use `mixed` for better Korean recall

### Medium Issues
- `description.keyword` → Missing `ignore_above`, recommend `ignore_above: 256`

## Korean Analyzer Review
- Tokenizer: nori_tokenizer (decompound_mode: [value])
- Filters: [filter chain]
- Issues: [findings]

## Summary
- Critical: [count] | High: [count] | Medium: [count] | Low: [count]
```

### With --check-compatibility
```
## Compatibility Report
- Old: [old mapping path]
- New: [new mapping path]

### Breaking Changes (Require Reindex)
- `category`: type changed `keyword` → `text`
- `tags`: changed from `nested` to `object`

### Safe Changes
- `new_field`: added as `keyword`
- `old_field`: removed (no impact on existing docs)

### Verdict: [Compatible|Reindex Required]
```

### With --suggest-optimizations
```
## Optimization Suggestions

### copy_to Opportunities
- `first_name` + `last_name` → `copy_to: full_name` for combined search

### Flattened Type Candidates
- `metadata` (object with 50+ dynamic sub-fields) → Consider `flattened` type

### Runtime Field Candidates
- `full_address` (concatenation of address parts) → Runtime field saves storage
```

## Boundaries

**Will:**
- Validate field types, analyzers, and mapping structure against best practices
- Detect breaking changes between mapping versions
- Audit Korean analyzer (nori) configuration for correctness
- Suggest optimizations for storage and query performance

**Will Not:**
- Apply mapping changes to a live Elasticsearch cluster
- Analyze query performance against the mapping (use `/es-query-review` instead)
- Generate complete mappings from scratch without input
- Validate cluster-level settings (shard count, replicas) — use `/index-lifecycle` instead
