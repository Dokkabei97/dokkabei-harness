# Elasticsearch Best Practices - Contributor Guide

This skill contains Elasticsearch performance optimization references optimized for
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
   - `cluster-` Cluster Architecture (CRITICAL)
   - `shard-` Shard Strategy (HIGH)
   - `indexing-` Indexing & Bulk (HIGH)
   - `analyzer-` Analyzer (HIGH)
   - `client-` Client & Framework (HIGH)
   - `streaming-` Streaming & Integration (MEDIUM-HIGH)
   - `agg-` Aggregation (MEDIUM)
   - `monitor-` Monitoring (LOW-MEDIUM)

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
skills/elasticsearch-best-practices/
├── SKILL.md           # Agent-facing skill manifest (Agent Skills spec)
├── AGENTS.md          # Navigation guide with file listings
├── CLAUDE.md          # Symlink to AGENTS.md
├── README.md          # This file
└── references/
    ├── _template.md      # Reference template
    ├── _sections.md      # Section definitions
    ├── _contributing.md  # Writing guidelines
    └── *.md              # Individual references (30 files)
```

## Reference File Structure

See `references/_template.md` for the complete template. Key elements:

````markdown
---
title: Clear, Action-Oriented Title
impact: CRITICAL|HIGH|MEDIUM-HIGH|MEDIUM|LOW-MEDIUM|LOW
impactDescription: Quantified benefit (e.g., "2-10x faster")
tags: relevant, keywords
---

## [Title]

[1-2 sentence explanation]

**Incorrect (description):**

```json
// Comment explaining what's wrong
{ "bad": "example" }
```

**Correct (description):**

```json
// Comment explaining why this is better
{ "good": "example" }
```
````

## Writing Guidelines

See `references/_contributing.md` for detailed guidelines. Key principles:

1. **Show concrete transformations** - "Change X to Y", not abstract advice
2. **Error-first structure** - Show the problem before the solution
3. **Quantify impact** - Include specific metrics (2-10x faster, 50% smaller)
4. **Self-contained examples** - Complete, runnable JSON/Java
5. **Semantic naming** - Use meaningful names (products, orders), not (index1, col1)

## Impact Levels

| Level | Improvement | Examples |
|-------|-------------|----------|
| CRITICAL | 10-100x | Missing filter context, dynamic mapping explosion |
| HIGH | 5-20x | Wrong shard sizing, no bulk API |
| MEDIUM-HIGH | 2-5x | Deep pagination, connection pool issues |
| MEDIUM | 1.5-3x | Aggregation cardinality, refresh tuning |
| LOW-MEDIUM | 1.2-2x | Slow log tuning, monitoring config |
| LOW | Incremental | Advanced patterns, edge cases |

## Enterprise Focus

All references target enterprise-scale deployments:
- 10+ node clusters
- 100M+ documents
- 1000+ QPS
- ES 8.x baseline, ES 9.x migration notes where applicable
