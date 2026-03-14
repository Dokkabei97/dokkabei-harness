---
name: claude-md-inverted-index
description: |
  Inverted index strategy for CLAUDE.md that maps technology keywords to module/package locations.
  Reduces AI agent tool calls by 42-68% across all major languages and architectures.
  Use when setting up CLAUDE.md for any project with 50+ files, multi-module structure,
  or 3+ external technologies. Covers Spring Hexagonal, Python uv, Node.js/TypeScript,
  Go, Rust, and polyglot monorepos.
license: MIT
metadata:
  version: 2.0.0
  author: jmk
  category: developer-productivity
  domain: ai-agent-optimization
  updated: 2026-02-24
  research-basis: 3-phase team research (12 agents, 6 languages, 10+ architectures)
  languages: kotlin, java, python, typescript, javascript, go, rust
  frameworks: spring-hexagonal, fastapi, django, nextjs, nestjs, turborepo, axum, gin
---

# CLAUDE.md Inverted Index Strategy

Map technology keywords to file locations so AI agents find code instantly instead of searching.

## When to Apply

Use this skill when:
- Setting up or optimizing CLAUDE.md for a code project
- Project has 50+ files with multi-module or multi-package structure
- 3+ external technologies integrated (DB, cache, queue, search, etc.)
- AI agent repeatedly asks "where is X?" or makes many Glob/Grep calls
- Hexagonal/Clean Architecture with ports and adapters spread across modules
- Monorepo with multiple apps/packages sharing code

**Do NOT apply when:**
- Convention-over-Configuration framework (Rails, Laravel, small Django)
- Single module project with <50 files
- File-based routing project with no complex lib/ (basic Next.js pages)
- Greenfield project still establishing structure

## 3-Axis Necessity Score

Calculate before applying:

| Axis | 1 point | 2 points | 3 points | 4 points |
|------|---------|----------|----------|----------|
| **Scale** (files) | <50 | 50-200 | 200-500 | 500+ |
| **Architecture** | single, flat | multi-module or layered | hexagonal/clean + multi-module | polyglot monorepo |
| **Tech Diversity** | 1-2 techs | 3-5 techs | 6-8 techs | 9+ techs |

**Sum 3-5**: Not needed | **6-8**: Recommended | **9-12**: Strongly recommended

## Core Concept

```
BEFORE (narrative):
  "The evolution directory contains Python scripts for each pipeline phase..."

AFTER (inverted index):
  ### Kafka
  - consumer: inbound-consumer/.../listener/
  - producer: outbound-event/.../producer/
  - config: inbound-consumer/.../config/, outbound-event/.../config/
```

## Output Architecture: 3-Tier External Reference

All files are **project-level** (not global `~/.claude/`). Each project has its own inverted index.

```
PROJECT_ROOT/
├── CLAUDE.md                          # Tier 1: always loaded (30-50 lines)
├── .claude/
│   └── rules/                         # Tier 2: auto-loaded on path match
│       ├── kafka.md
│       ├── jpa.md
│       └── redis.md
├── module-a/
│   └── CLAUDE.md                      # Tier 3: loaded in this module only
└── module-b/
    └── CLAUDE.md
```

**Tier 1: `PROJECT_ROOT/CLAUDE.md`** (always loaded, 30-50 lines)
- Module/package list (names only)
- Entry points, Generated files (DO NOT MODIFY)
- "See .claude/rules/ for tech-specific guides"

**Tier 2: `PROJECT_ROOT/.claude/rules/*.md`** (auto-loaded on path match)
- Each file has frontmatter with `paths:` for auto-loading:
  ```yaml
  ---
  description: "Kafka consumer/producer conventions"
  paths: ["**/inbound-consumer/**", "**/outbound-event/**"]
  ---
  ```
- Contains: tech-specific inverted index + conventions + pitfalls

**Tier 3: `PROJECT_ROOT/{module}/CLAUDE.md`** (loaded when working in that module)
- Optional, for complex modules only

**Why 3-Tier?**
- Root CLAUDE.md stays under 50 lines (always in context, never wasted)
- Tech-specific rules load ONLY when the agent works in matching paths
- Total indexed knowledge can be 10x larger without context overhead

## Optimal Granularity

```
Safe to index          |  Do NOT index
-----------------------|-----------------
Module structure       |  Business class filenames
Package paths          |  Test filenames
Config filenames (few) |  DTO/VO class names
Port/Interface names   |  Implementation file names (many)
```

**Module + Package level** is optimal. Agent can `ls` the package to find specific files.

## Effectiveness by Language

| Ecosystem | Tool Call Reduction | ROI | Killer Feature |
|-----------|-------------------|-----|----------------|
| Rust (Cargo workspace) | ~68% | 5-12x | Trait->Impl mapping, feature flags |
| Polyglot monorepo | ~67% | 8-14x | Cross-service domain mapping |
| Turborepo/Nx | ~63% | 8-14x | Cross-app impact analysis |
| Python uv monorepo | ~62% | 5-12x | Name disambiguation (models/schemas) |
| Go (standard layout) | ~60% | 5-10x | Interface->Impl mapping |
| Next.js App Router | ~58% | 6-12x | 3-way split (app/lib/components) |
| Spring Hexagonal | ~42% | 3-8x | Layer mapping (port/adapter) |

## How to Use Templates

Templates in `templates/` provide ready-to-use 3-Tier output for each stack.

Each template contains two parts:
- **Part 1: Root CLAUDE.md** -- Copy to your project's root CLAUDE.md
- **Part 2: .claude/rules/ Files** -- Create each file in your `.claude/rules/` directory

```
templates/spring-hexagonal.md     -- Kotlin/Java multi-module
templates/python-uv-monorepo.md   -- Python uv workspace
templates/turborepo.md            -- TypeScript Turborepo/Nx/pnpm
templates/go-standard.md          -- Go standard layout
templates/rust-workspace.md       -- Rust Cargo workspace
```

See `references/` for detailed per-language guides:

```
references/lang-kotlin-java.md       -- Spring Hexagonal deep guide
references/lang-python.md            -- FastAPI/Django/Celery patterns
references/lang-typescript.md        -- Next.js/NestJS/Turborepo patterns
references/lang-go.md                -- Go standard layout + DDD
references/lang-rust.md              -- Cargo workspace + trait system
references/lang-polyglot.md          -- Multi-language monorepo
references/maintenance-automation.md -- Auto-generation scripts, CI checks
```

## Key Principles

1. **Root CLAUDE.md**: 30-50 lines max (module names + entry points + generated files)
2. **.claude/rules/**: One file per technology, with `paths:` frontmatter for auto-loading
3. **Module + Package** granularity (not individual files)
4. **Technology-grouped** format (not layer-grouped)
5. **Auto-generate paths, manually curate descriptions**
6. **Validate in CI** (check paths still exist)

## References

- Liu et al., "Lost in the Middle" (TACL 2024) - context middle information ignored
- "Context Length Alone Hurts" (EMNLP 2025) - length itself degrades performance
- Anthropic, "Effective context engineering for AI agents"
- arXiv 2602.11988 - context files can hurt agent performance when overdone
- arXiv 2601.20404 - AGENTS.md reduces runtime by 28.64%
