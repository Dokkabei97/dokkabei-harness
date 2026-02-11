# Search Platform Best Practices - Contributor Guide

This skill contains Elasticsearch/OpenSearch performance optimization references optimized for
AI agents and LLMs. It follows the [Agent Skills Open Standard](https://agentskills.io/).

## Quick Start

```bash
# From repository root
npm install

# Validate existing references
npm run validate

# Build AGENTS.md
npm run build
```

## Creating a New Reference

1. **Choose a section prefix** based on the category:
   - `mapping-` Mapping & Schema Design (CRITICAL)
   - `query-` Query Performance (CRITICAL)
   - `cluster-` Cluster & Node Architecture (CRITICAL)
   - `shard-` Index & Shard Strategy (HIGH)
   - `indexing-` Indexing Performance (HIGH)
   - `analyzer-` Korean/CJK Search & Analyzers (HIGH)
   - `security-` Security (MEDIUM-HIGH)
   - `agg-` Aggregation Optimization (MEDIUM-HIGH)
   - `resilience-` Resilience & Recovery (MEDIUM)
   - `lifecycle-` Data Lifecycle (MEDIUM)
   - `crosscluster-` Cross-Cluster (MEDIUM)
   - `monitor-` Monitoring & Diagnostics (LOW-MEDIUM)
   - `k8s-` Kubernetes / ECK Operations (LOW-MEDIUM)
   - `advanced-` Advanced Features (LOW)

2. **Copy the template**:
   ```bash
   cp references/_template.md references/query-your-reference-name.md
   ```

3. **Fill in the content** following the template structure

4. **Validate and build**:
   ```bash
   npm run validate
   npm run build
   ```

5. **Review** the generated `AGENTS.md`

## Skill Structure

```
skills/search-platform-best-practices/
├── SKILL.md           # Agent-facing skill manifest (Agent Skills spec)
├── AGENTS.md          # [GENERATED] Compiled references document
├── README.md          # This file
└── references/
    ├── _template.md      # Reference template
    ├── _sections.md      # Section definitions
    ├── _contributing.md  # Writing guidelines
    └── *.md              # Individual references
```

## Reference File Structure

See `references/_template.md` for the complete template. Key elements:

````markdown
---
title: Clear, Action-Oriented Title
impact: CRITICAL|HIGH|MEDIUM-HIGH|MEDIUM|LOW-MEDIUM|LOW
impactDescription: Quantified benefit (e.g., "10-100x faster")
tags: relevant, keywords
---

## [Title]

[1-2 sentence explanation]

**Incorrect (description):**

```json
// Comment explaining what's wrong
[Bad JSON DSL example]
```
````

**Correct (description):**

```json
// Comment explaining why this is better
[Good JSON DSL example]
```

## Writing Guidelines

See `references/_contributing.md` for detailed guidelines. Key principles:

1. **Show concrete transformations** - "Change X to Y", not abstract advice
2. **Error-first structure** - Show the problem before the solution
3. **Quantify impact** - Include specific metrics (10x faster, 50% less heap)
4. **Self-contained examples** - Complete, runnable REST API calls
5. **Semantic naming** - Use meaningful names (users, email), not (index1, field1)

## Impact Levels

| Level | Improvement | Examples |
|-------|-------------|----------|
| CRITICAL | 10-100x | Wrong field types, missing filter context, cluster misconfiguration |
| HIGH | 5-20x | Suboptimal analyzers, missing bulk API, poor shard sizing |
| MEDIUM-HIGH | 2-5x | Inefficient aggregations, suboptimal bool queries |
| MEDIUM | 1.5-3x | ILM tuning, replica adjustments, query templates |
| LOW-MEDIUM | 1.2-2x | Slow log tuning, monitoring setup |
| LOW | Incremental | Advanced patterns, vector search, edge cases |
