> **English** · [한국어](CLAUDE_KO.md)

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Identity

A Claude Code plugin marketplace (`dokkabei-harness`). 23 plugins live in `plugins/<name>/` and
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
- A hooks.json **matcher group carries only `matcher` and `hooks`** (`$schema` is the sole tolerated top-level extra).
  `timeout`/`args`/`async`/`if` belong to the handler entry, and an off-schema key such as `description` is ignored
  with a `hooks.json: unknown key "..." ignored` warning at every session start (measured 2026-09, CC 2.1.278) —
  document a hook in its script header comment. Guarded by `tests/hooks/hooks-registration.bats` + HK-004.
- A **Stop hook is overridden after 8 consecutive blocks** — Claude Code ends the turn regardless (measured 2026-09-20,
  3/3 trials: the hook is invoked 9 times and the 9th `exit 2` is ignored). So the in-session ceiling for the loop engines is
  **8 iterations**, not the documented `LOOP_MAX_ITER` default of 24/12. The headless driver (`plugins/feature-loop/bin/floop-headless.sh`)
  is unaffected because each `claude -p` call is a fresh turn. The engines do **not** yet detect this cap — see
  `tasks/spikes/harness-bottleneck-research.md`.
- Plugins are **edited only in the repo source**. Directly modifying the `~/.claude/plugins/cache` / marketplaces clone is
  forbidden (measured cache-drift incident history). The official propagation path is commit then `/plugin update`, and
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
- `HANDOFF.md` is written only by the `/handoff` command (explicit invocation) — there is no hook that records it
  automatically (the PreCompact/SessionEnd snapshot hook was removed 2026-09).
- Hook scripts come in 2 families: base is Node (`bin/hooks/*.js`, `_lib/hook-stdin.js` convention), and the loop
  plugins (harness/mvp/feature-loop) are bash Stop hooks (`hooks/*-stop-hook.sh`).
- `infra/otel/` = the local observability stack (Claude Code built-in OTel receiver, Grafana localhost:3000) —
  an orthogonal complement to the observe plugin's `.claude/skill-trace.jsonl`.
- `docs/` = the GitHub Pages landing site (`index.html`, self-contained, EN/KO toggle) — unrelated to any plugin;
  it is the public homepage (`dokkabei97.github.io/dokkabei-harness`). Not to be confused with a plugin's `references/` docs.
