> **English** · [한국어](README_KO.md)

# dokkabei-harness

Claude Code plugin marketplace. It started as a collection of sub agents, but now
it bundles agents, commands, skills, and hooks together into **20 plugins** under `plugins/`,
installed and distributed via `.claude-plugin/marketplace.json`.

## Installation

```
/plugin marketplace add <this repository path or git URL>
/plugin install <plugin name>@dokkabei-harness
```

Example: `/plugin install base@dokkabei-harness`, `/plugin install search@dokkabei-harness`.

## ★ Featured: `observe` — the self-measuring harness

Most plugins do work. **`observe` watches the harness itself** — which skills and agents actually
fire, *why*, and whether they complete — and turns that into concrete improvements.

Inspired by Nous Research's **Hermes Agent**: where Hermes grows by autonomously *creating* skills
from experience, observe takes the **evaluation-first** path — it *measures and proposes*. It ports the
**deterministic half** of Hermes's curator (usage lifecycle: stale / archive candidates; correction
signals) and surfaces dead/stale assets, missed activations, and uncorrected skill runs — then drafts
the fix. **You approve; it never edits a file silently.**

Use it in three steps:

```sh
# 1. Turn on tracing (opt-in — records prompt text locally, so it's off by default)
export OBSERVE_TRACE=1

# 2. Work normally — 6 hooks correlation-log prompt → skill → agent → result → session
#    into .claude/skill-trace.jsonl (joined by session_id / prompt_id)

# 3. Ask for the report: deterministic aggregation → LLM interpretation → proposals
/observe-report   # unused & stale/archive candidates · missed activations
                  # correction signals · description-tuning drafts
```

### Local observability — no SaaS

There is no hosted service; everything runs on your machine. observe's traces are a local `.jsonl`.
For the cost/token side, the optional Grafana stack under `infra/otel` is a **docker-compose you bring
up yourself** — it receives Claude Code's built-in OpenTelemetry (cost·tokens·events) and renders it
next to your skill traces. Everything binds to **loopback only**; your prompts and metrics never leave
your laptop.

```sh
cd infra/otel && docker compose up -d
# Grafana → http://localhost:3000  (Claude Code cost/token dashboards, EN/KO)
```

**Why docker-compose and not a SaaS?** Trust in a harness comes from running it yourself, not from a
dashboard you rent. The stack is here so you can **verify locally** — spin it up, watch the numbers,
tear it down. Nothing is uploaded, nothing is sold. (Details: [`infra/otel/README.md`](infra/otel/README.md).)

## Structure

```text
├── .claude-plugin/marketplace.json   # Marketplace registration surface (20 plugins)
├── plugins/<name>/                    # Each plugin
│   ├── .claude-plugin/plugin.json     #   Manifest (name/description/version)
│   ├── agents/                        #   Sub agents
│   ├── commands/                      #   Slash commands (legacy format)
│   ├── skills/<name>/SKILL.md         #   Skills (recommended format)
│   ├── hooks/hooks.json               #   Hook registration surface
│   └── bin/hooks/*.js                 #   Hook scripts (Node)
├── claude/                            # Distribution for Claude Code root settings (CLAUDE.md·settings.json·output-styles)
├── tests/hooks/*.bats                 # Hook·loop engine regression tests (bats)
└── .github/workflows/                 # CI (ubuntu+macos matrix)
```

## Plugin list

### Foundation·harness building
- **base** — 16 common guard hooks (security warning `warn-security`, format/compile checks, tmux enforcement, etc.) + LSP. The foundation layer of the loop harness.
- **harness** — Meta plugin for harness building: `team-harness` design, `/create-flow`·`/verify-flow`, lightweight generic loop (`/loop-run`·`/loop-stop`).
- **observe** — Harness usage observation·improvement. 6 hooks correlation-log skill/agent calls·completion·session boundaries into `.claude/skill-trace.jsonl` (`OBSERVE_TRACE=1` opt-in), and `/observe-report` aggregates → judges missed activation → produces an improvement proposal (description tuning·dead assets).

### Development workflow
- **analyze** — Comprehensive code quality/security/performance/architecture/SQL analysis.
- **test** — TDD workflow, E2E (Playwright/Chrome) test generation·execution.
- **workflow** — PE/MR review, session handoff, CLAUDE.md sync, documentation, issue tracking, post-merge processing, spec/planning/shipping/deprecation management, retro compounding.

### Loop engineering
- **mvp** — New service MVP loop. Completes idea→PRD→design→stack selection·scaffolding→PRD-driven development via a Stop-hook loop engine + gate state machine.
- **feature-loop** — Loop for brownfield codebases. Completes natural language requests via task decomposition (tasks.json)→baseline capture→regression-safe development loop.

### Backend stack
- **backend-shared** — Language-common: API design (REST/GraphQL), DB migration, hexagonal architecture, observability/caching/event/resilience/security/DTO patterns, backend testing.
- **kotlin-spring** / **python-fastapi** / **go-mux** — Stack-specific code generation·guide·scaffolding (combined with backend-shared).
- **nextjs** — Next.js App Router frontend specialization.
- **search** — Elasticsearch search engineering: query optimization, relevance tuning, vector/hybrid search (kNN/RRF), data pipeline integration (Kafka/Spark), index lifecycle.

### Domain
- **legal** — Korean law legal affairs (contracts·corporate/investment·labor·IP·regulation·criminal risk). Expert Pool + Fan-out.
- **finance** — Operational finance·tax (expense eligibility, financial statement interpretation, tax risk screening).
- **hr** — Recruiting·people ops (JD drafting, interview kits, onboarding). Labor law judgments are delegated to legal.
- **startup** — Lean canvas, idea validation, market research, unit economics, growth plan, pitch deck.
- **etc** — Utilities (web fetch, cross-model CLI routing).

## Development

```
bats tests/hooks           # Hook·loop engine regression tests
jq . plugins/*/hooks/hooks.json   # Hook registration surface parse validation
```

- Hook scripts follow the `readEvent`/`passthrough` convention of `bin/hooks/_lib/hook-stdin`
  (event parsing → conditional warning stderr → original passthrough stdout; PreToolUse blocking is exit 2).
- For component conventions and validation rules see `plugins/harness/skills/flow-validation/`,
  for scaffolding templates see `plugins/harness/skills/flow-scaffolding/`.
