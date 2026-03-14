# MongoDB Best Practices - Contributor Guide

This skill contains MongoDB performance optimization references optimized for
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
   - `query-` Query Performance (CRITICAL)
   - `index-` Indexing Strategy (CRITICAL)
   - `schema-` Schema Design (CRITICAL)
   - `agg-` Aggregation Pipeline (HIGH)
   - `conn-` Connection Management (HIGH)
   - `model-` Data Modeling Patterns (MEDIUM-HIGH)
   - `security-` Security & Authentication (MEDIUM-HIGH)
   - `repl-` Replication & High Availability (MEDIUM)
   - `shard-` Sharding (MEDIUM)
   - `monitor-` Monitoring & Diagnostics (LOW-MEDIUM)
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
skills/mongodb-best-practices/
├── SKILL.md           # Agent-facing skill manifest (Agent Skills spec)
├── AGENTS.md          # [GENERATED] Compiled references document
├── README.md          # This file
└── references/
    ├── _template.md      # Reference template
    ├── _sections.md      # Section definitions
    ├── _contributing.md  # Writing guidelines
    └── *.md              # Individual references

packages/skills-build/
├── src/               # Generic build system source
└── package.json       # NPM scripts
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

```javascript
// Comment explaining what's wrong
[Bad mongosh/Node.js example]
```

**Correct (description):**

```javascript
// Comment explaining why this is better
[Good mongosh/Node.js example]
```
````

## Writing Guidelines

See `references/_contributing.md` for detailed guidelines. Key principles:

1. **Show concrete transformations** - "Change X to Y", not abstract advice
2. **Error-first structure** - Show the problem before the solution
3. **Quantify impact** - Include specific metrics (10x faster, 50% smaller)
4. **Self-contained examples** - Complete, runnable mongosh or Node.js code
5. **Semantic naming** - Use meaningful names (users, email), not (col1, field1)

## Impact Levels

| Level | Improvement | Examples |
|-------|-------------|----------|
| CRITICAL | 10-100x | Missing indexes, collection scans, unbounded queries |
| HIGH | 5-20x | Wrong index order, unoptimized aggregation pipelines |
| MEDIUM-HIGH | 2-5x | N+1 lookups, poor data modeling patterns |
| MEDIUM | 1.5-3x | Redundant indexes, suboptimal write concern |
| LOW-MEDIUM | 1.2-2x | Profiler tuning, read preference optimization |
| LOW | Incremental | Advanced patterns, edge cases |
