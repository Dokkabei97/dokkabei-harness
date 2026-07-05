> **English** · [한국어](README_KO.md)

# analyze

> A comprehensive code analysis plugin that statically analyzes code quality, security, performance, architecture, and SQL, and presents severity-rated improvement proposals.

## Overview

`analyze` is a collection of static analysis tools that scan code read-only, without modifying the source, to find structural problems. It is divided into a comprehensive command (`/analyze`) that looks at multiple domains at once, and specialized commands (`/arch-review`, `/perf-review`, `/sql-analyze`) that dig deep into architecture, performance, and SQL respectively. Each specialized command delegates the actual analysis methodology to a dedicated agent responsible for the same domain (`arch-reviewer`, `perf-reviewer`, `sql-analyzer`), and skills (`*-guide`) automatically attach anti-pattern and rule quick references at the moment they are needed.

All analysis results are classified by Critical / High / Medium / Low severity, and each finding is accompanied by Bad/Good code examples and concrete improvement proposals. It is used for code review gates (before PR merge), root-cause identification of slow queries, architecture health checks, identifying cleanup targets before starting a refactor, and more. It supports Kotlin (Spring Boot), Python (FastAPI/Django), and TypeScript/JavaScript (Next.js/NestJS), and for SQL it handles the PostgreSQL, MySQL, and Oracle dialects.

## Components

### Commands

- `/analyze` — Multi-domain static analysis spanning quality, security, performance, and architecture. It adjusts scope and output with `--focus`, `--depth`, and `--format`, and produces a report with severity-ranked findings and an improvement roadmap.
- `/arch-review` — Performs dependency direction analysis, layer violation detection, naming/package consistency checks, and MSA maturity assessment to produce a 0–100 architecture health score. Based on 6-phase analysis and a violation checklist (V-C1~V-L3).
- `/perf-review` — Grep-based scanning for performance anti-patterns across 9 categories such as memory, I/O, concurrency, and serialization, presenting an expected improvement impact and Bad/Good examples for each finding.
- `/sql-analyze` — Analyzes SQL queries for full scans, index invalidation, subquery inefficiency, and join/pagination problems in 2 phases (query alone → metadata-precise), and even generates CREATE statements for missing indexes.

### Agents

- `arch-reviewer` — Architecture review specialist. Analyzes codebase structure, dependency direction, and adherence to design patterns. The actual analysis engine of `/arch-review`.
- `perf-reviewer` — Performance review specialist. Detects memory leaks, I/O bottlenecks, concurrency issues, serialization overhead, and language-specific performance pitfalls. The actual analysis engine of `/perf-review`.
- `sql-analyzer` — SQL performance analyst. Diagnoses full table scans, slow query patterns, subquery inefficiency, missing indexes, and join optimization issues. The actual analysis engine of `/sql-analyze`.

### Skills

- `arch-review-guide` — Quick reference for architecture violation detection, dependency direction rules, and structural health assessment (includes the detailed reference `guide/arch-review-guide.md`).
- `perf-review-guide` — Quick reference of representative anti-patterns and optimization strategies to consult when writing and reviewing performance-sensitive code.
- `sql-analyze-guide` — Quick reference for performance anti-patterns, index strategy, and subquery/join tuning to consult when writing and reviewing SQL.
- `code-simplification-guide` — A guide of principles, cleanup-target classification, and a safe simplification procedure to consult when simplifying, refactoring, or cleaning up existing code. (Auto-activates in the context of simplification work without a dedicated command.)

## Usage

Invoke commands directly as `/analyze`, `/arch-review`, `/perf-review`, `/sql-analyze`. You can narrow the scope by appending a target path and options.

```
# Multi-domain analysis of the whole project
/analyze

# Deep security analysis of the auth module
/analyze src/auth --focus security --depth deep

# Architecture gate before PR merge (Critical/High only, fast)
/arch-review src --depth quick

# I/O·DB performance review of the repository layer (N+1, missing batching, etc.)
/perf-review src/repository --focus io

# Paste SQL and analyze indexes/subqueries
/sql-analyze
SELECT ... FROM orders o JOIN customers c ON ...
```

Specialized commands delegate the analysis to their corresponding agents, and skills load automatically — without a separate call — in the context of related work (architecture review, performance tuning, SQL authoring, code simplification) to reinforce the judgment criteria. `/sql-analyze` produces a first-pass analysis (Phase 1) from the query alone, and when the user adds table row counts, index information, or EXPLAIN results, it automatically moves on to precise analysis (Phase 2).

## Notes

- All commands **only propose** and do not directly modify source code. They provide findings and Bad/Good examples as a report.
- Build/compile, running actual profilers/benchmarks, EXPLAIN against a real DB connection, and the like are not performed without user approval (only to the level of guiding you on the command to run).
- Performance improvement impacts and architecture health scores are **estimates** based on static analysis and do not guarantee specific figures.
- It detects and verifies rather than forcing a particular architecture style, and it addresses only the quality/performance/structure perspective, not the correctness of business logic.
- If you need language-neutral, framework-specific reviews, use it together with the backend-family (`backend-*`) plugins, and if you need ES/search-domain reviews, use it together with the `search` plugin.
