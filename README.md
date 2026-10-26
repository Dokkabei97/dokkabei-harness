> **English** · [한국어](README_KO.md)

# dokkabei-harness

Claude Code plugin marketplace. It started as a collection of sub agents, but now
it bundles agents, commands, skills, and hooks together into **12 plugins** under `plugins/`,
installed and distributed via `.claude-plugin/marketplace.json`.

## Installation

```
/plugin marketplace add <this repository path or git URL>
/plugin install <plugin name>@dokkabei-harness
```

Example: `/plugin install base@dokkabei-harness`, `/plugin install search@dokkabei-harness`.

## ★ Featured: `observe` — the self-measuring harness

Most plugins do work. **`observe` watches the harness itself** — which skills and agents actually
fire, *why*, and how their turns end (committed, cancelled, corrected) — and turns that into concrete improvements.

> Claude Code's native `/usage` shows **cost and tokens**. observe shows the layer above it — **which
> skills and agents fire, why, how their turns end, and which go stale or uncorrected** — the
> harness-health view that cost metrics can't give you.

Inspired by Nous Research's **Hermes Agent**: where Hermes grows by autonomously *creating* skills
from experience, observe takes the **evaluation-first** path — it *measures and proposes*. It ports the
**deterministic half** of Hermes's curator (usage lifecycle: stale / archive candidates; correction
signals) and surfaces dead/stale assets, missed activations, and uncorrected skill runs — then drafts
the fix. **You approve; it never edits a file silently.**

Use it in three steps:

```sh
# 1. Turn on tracing (opt-in — records prompt text locally, so it's off by default)
export OBSERVE_TRACE=1

# 2. Work normally — hooks log prompt → skill → agent → result → turn outcome → session
#    into <repo>/.tracer/ (self-gitignored). Codex runs the same hooks; Antigravity and
#    past Codex sessions come in via observe-backfill.js; git hooks are opt-in

# 3. Ask for the report: deterministic aggregation → LLM interpretation → proposals
/observe-report   # unused & stale/archive candidates · missed activations
                  # correction signals · description-tuning drafts
                  # then asks you to accept / reject / snooze each recommendation
```

### Local observability — no SaaS

There is no hosted service; everything runs on your machine. observe's traces live in the repo's
git-ignored `.tracer/` folder (prompt text only in `raw/`, after secret redaction), and nothing is uploaded or sold. OTel (Claude Code's built-in telemetry) is not supported — observe
neither reads nor exports it.

## Structure

```text
├── .claude-plugin/marketplace.json   # Marketplace registration surface (12 plugins)
├── plugins/<name>/                    # Each plugin
│   ├── .claude-plugin/plugin.json     #   Manifest (name/description/version)
│   ├── agents/                        #   Sub agents
│   ├── commands/                      #   Slash commands (legacy format)
│   ├── skills/<name>/SKILL.md         #   Skills (recommended format)
│   ├── hooks/hooks.json               #   Hook registration surface
│   └── bin/hooks/*.js                 #   Hook scripts (Node)
├── claude/                            # Distribution for Claude Code root settings (CLAUDE.md·settings.json·output-styles)
└── .github/                           # Issue / PR templates (no CI workflow)
```

## Plugin list

### Foundation·harness building
- **base** — 15 common guard hooks (security warning `warn-security`, format/compile checks, tmux enforcement, etc.) + LSP. The foundation layer of the loop harness.
- **harness** — Meta plugin for harness building: `team-harness` design (v2, three execution modes), `evolve` harness evolution, `/create-flow`·`/verify-flow`, lightweight generic loop (`/loop-run`·`/loop-stop`).
- **observe** — Harness usage observation·improvement. Claude Code and Codex hooks (Antigravity via backfill) correlation-log skill/agent calls·per-turn work digests (tool flow, commits, outcome: committed/cancelled/…)·session boundaries into the self-gitignored `<repo>/.tracer/` (raw text split into `raw/` with secret redaction; `OBSERVE_TRACE=1` opt-in), opt-in git hooks link commits to sessions (`/observe-git-hooks`), and `/observe-report` aggregates → judges missed activation → produces an improvement proposal (description tuning·dead assets) and records your accept/reject/snooze answers.

### Development workflow
- **test** — TDD workflow, E2E (Playwright/Chrome) test generation·execution.
- **workflow** — PE/MR review, session handoff, CLAUDE.md sync, documentation, issue tracking, post-merge processing, spec/planning/shipping/deprecation management, retro compounding.

### Backend stack
- **backend-shared** — Language-common: API design (REST/GraphQL), DB migration, hexagonal architecture, observability/caching/event/resilience/security/DTO patterns, backend testing.
- **kotlin-spring** / **python-fastapi** / **go-mux** — Stack-specific code generation·guide·scaffolding (combined with backend-shared).
- **nextjs** — Next.js App Router frontend specialization.
- **search** — Elasticsearch search engineering: query optimization, relevance tuning, vector/hybrid search (kNN/RRF), data pipeline integration (Kafka/Spark), index lifecycle.

### Knowledge ops
- **wiki-ops** — Operates a cited [llm-wiki](https://github.com/Dokkabei97/llm-wiki) knowledge vault: gated feed → deterministic audit → curation loop (on the harness generic loop) → cited Q&A.

## Development

```
jq . plugins/*/hooks/hooks.json   # Hook registration surface parse validation
```

- Hook scripts follow the `readEvent`/`passthrough` convention of `bin/hooks/_lib/hook-stdin`
  (event parsing → conditional warning stderr → original passthrough stdout; PreToolUse blocking is exit 2).
- There is no test suite or CI — verify a hook change by piping a real-data sample or fixture payload
  into the script and checking exit code, stdout bytes and the written record.
- For component conventions and validation rules see `plugins/harness/skills/flow-validation/`,
  for scaffolding templates see `plugins/harness/skills/flow-scaffolding/`.
