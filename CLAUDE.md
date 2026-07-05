> **English** · [한국어](CLAUDE_KO.md)

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Identity

A Claude Code plugin marketplace (`dokkabei-harness`). 19 plugins live in `plugins/<name>/` and
are registered in `.claude-plugin/marketplace.json`. Install: `/plugin install <name>@dokkabei-harness`.

## Commands

- Hook and loop-engine regression tests: `bats tests/hooks` (assumes bats-core is installed locally; CI uses an ubuntu+macOS matrix)
- Hook JSON validation: `jq . plugins/*/hooks/hooks.json`
- Shell hook lint (same as CI): `shellcheck --severity=error plugins/**/{hooks,bin}/**/*.sh`
- No package.json — do not look for npm scripts

## Absolute Rules (based on measured incident history)

- hooks.json `matcher` accepts **only a tool-name regex** (`Bash`, `Edit|Write`). Putting a `tool == "X"` expression or a command-content
  filter in the matcher causes it to **silently miss activation** (measured 2026-07) — command/argument filtering must
  be done inside the hook script.
- Plugins are **edited only in the repo source**. Directly modifying the `~/.claude/plugins/cache` / marketplaces clone is
  forbidden (cache-drift incident history — tasks/todo.md). The official propagation path is commit then `/plugin update`, and
  hook/config changes take effect from the next session onward.
- Plugin versions **must be manually synced in two places**: `plugins/<name>/.claude-plugin/plugin.json` ↔
  the corresponding plugin entry in `.claude-plugin/marketplace.json`.
- When you modify a hook, update the `tests/hooks/*.bats` regression tests along with it. PreToolUse blocking is exit 2
  (exit 1 passes through as a non-blocking warning).

## Conventions

- Commits: Conventional Commits + Korean body (`feat(scope): …`, `fix(base): …`)
- Component descriptions (skills/commands/agents frontmatter) are **bilingual**: Korean original first,
  then an English summary + `Use when: …` trigger clause appended (keeps activation working for both
  Korean and English prompts; total ≤ 1,400 chars — the skill listing truncates at 1,536)
- Component rules / validation ruleset: `plugins/harness/skills/flow-validation/` (used by `/verify-flow`;
  SKILL.md token budget optimized to <3.5k)
- Scaffolding templates: `plugins/harness/skills/flow-scaffolding/` (used by `/create-flow`)
- command/skill unification in Claude Code v2.1.3+ — new components should prefer the skill format

## Easily Confused Structure

- `claude/` = the global `~/.claude` distribution template — unrelated to this file (project memory).
- The `<!-- auto-snapshot -->` block at the top of `HANDOFF.md` is machine-written by the PreCompact/SessionEnd hooks —
  do not edit it by hand. Fill in the semantic summary via `/handoff`.
- Hook scripts come in 2 families: base is Node (`bin/hooks/*.js`, `_lib/hook-stdin.js` convention), and the loop
  plugins (harness/mvp/feature-loop) are bash Stop hooks (`hooks/*-stop-hook.sh`).
- `infra/otel/` = the local observability stack (Claude Code built-in OTel receiver, Grafana localhost:3000) —
  an orthogonal complement to the observe plugin's `.claude/skill-trace.jsonl`.
