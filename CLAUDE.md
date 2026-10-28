> **English** · [한국어](CLAUDE_KO.md)

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Identity

A Claude Code plugin marketplace (`dokkabei-harness`). 12 plugins live in `plugins/<name>/` and
are registered in `.claude-plugin/marketplace.json`. Install: `/plugin install <name>@dokkabei-harness`.

## Commands

- No in-repo test suite and no CI (`tests/` and the GitHub Actions workflow were removed 2026-10) — verify a hook
  change by hand: pipe a real-data sample or fixture payload into the script and check exit code, stdout bytes and
  the written record
- Hook JSON validation: `jq . plugins/*/hooks/hooks.json`
- Shell hook lint (local): `shellcheck --severity=error plugins/**/{hooks,bin}/**/*.sh`
- No package.json — do not look for npm scripts

## Absolute Rules (based on measured incident history)

- hooks.json `matcher` accepts **only a tool-name regex** (`Bash`, `Edit|Write`). Putting a `tool == "X"` expression or a command-content
  filter in the matcher causes it to **silently miss activation** (measured 2026-07) — command/argument filtering must
  be done inside the hook script.
- A hooks.json **matcher group carries only `matcher` and `hooks`** and the file has no top-level `$schema` — Codex 0.165 rejects the whole file on it (measured 2026-10). Handlers use one
  `command` string (`node "${CLAUDE_PLUGIN_ROOT}/…"`), never `command` + `args` (Codex drops `args`).
  `timeout`/`args`/`async`/`if` belong to the handler entry, and an off-schema key such as `description` is ignored
  with a `hooks.json: unknown key "..." ignored` warning at every session start (measured 2026-09, CC 2.1.278) —
  document a hook in its script header comment. Guarded by `/verify-flow` rule HK-004.
- A **Stop hook is overridden after 8 consecutive blocks** — Claude Code ends the turn regardless (measured 2026-09-20,
  3/3 trials: the hook is invoked 9 times and the 9th `exit 2` is ignored). So the in-session ceiling per turn is
  **8 iterations**, not `LOOP_MAX_ITER` (default 12). The generic engine counts consecutive blocks per turn via
  `stop_hook_active` (`turn_blocks` in loop-state.json) and, at the cap, writes a progress.md handoff and exits 0 with
  loop-active kept (LOOP-011). Never gate on the cumulative `iteration` counter for this.
- Plugins are **edited only in the repo source**. Directly modifying the `~/.claude/plugins/cache` / marketplaces clone is
  forbidden (measured cache-drift incident history). The official propagation path is commit then `/plugin update`, and
  hook/config changes take effect from the next session onward.
- Plugin versions **must be manually synced in two places**: `plugins/<name>/.claude-plugin/plugin.json` ↔
  the corresponding plugin entry in `.claude-plugin/marketplace.json`.
- When you modify a hook, verify it in the same change against a real-data sample or fixture payload (manual pipe —
  see Commands); there is no regression suite to update. PreToolUse blocking is exit 2
  (exit 1 passes through as a non-blocking warning).

## Conventions

- Commits: Conventional Commits + Korean body (`feat(scope): …`, `fix(base): …`)
- Component descriptions (skills/commands/agents frontmatter) are **bilingual**: Korean original first,
  then an English summary + `Use when: …` trigger clause appended (keeps activation working for both
  Korean and English prompts; total ≤ 1,400 chars — the skill listing truncates at 1,536)
- Component rules / validation ruleset: `plugins/harness/skills/flow-validation/` (used by `/verify-flow`;
  SKILL.md token budget optimized to <3.5k)
- Scaffolding templates: `plugins/harness/skills/flow-scaffolding/` (used by `/create-flow`)
- Harness v2 (synced to upstream revfactory/harness v2.1.0): no `TeamCreate`/team objects — a team is the orchestrator's
  `## Team Members` table; harness change history lives in git commit bodies (`harness:evolve`), not a CLAUDE.md table
- command/skill unification in Claude Code v2.1.3+ — new components should prefer the skill format

## Easily Confused Structure

- `claude/` = the global `~/.claude` distribution template — unrelated to this file (project memory).
- `HANDOFF.md` is written only by the `/handoff` command (explicit invocation) — there is no hook that records it
  automatically (the PreCompact/SessionEnd snapshot hook was removed 2026-09).
- Hook scripts come in 2 families: base is Node (`bin/hooks/*.js`, `_lib/hook-stdin.js` convention), and the harness
  generic loop is bash (`hooks/generic-loop-stop-hook.sh` + `hooks/test-guard.sh`).
- `archive/` = retired plugins (mvp, feature-loop, startup, scaleup, enterprise, eng-gov, legal, finance, hr, analyze, etc —
  archived 2026-10 after zero use) with their bats tests in `archive/tests/hooks/`. Not installable (no `.claude-plugin/`),
  not in marketplace.json, not run by CI. Restore = move back + re-add the manifest and marketplace entry.
- `archive/components/<plugin>/` = partial archive: individual components (skills/commands/agents/references) retired from a
  still-active plugin, mirroring the plugin-relative path (2026-10). Restore = `git mv` back to `plugins/<plugin>/`.
- `archive/infra/otel/` = the retired local OTel/Grafana stack (archived 2026-10). observe does not integrate with OTel.
- `.tracer/` = the observe plugin's runtime trace store (self-gitignored via its own `.gitignore` `*`; `~/.tracer/` is the
  global layer for `--all`) — unrelated to project memory or this file. The legacy `.claude/skill-trace.jsonl` is its v0 path.
- `docs/` = the GitHub Pages landing site (`index.html`, self-contained, EN/KO toggle) — unrelated to any plugin;
  it is the public homepage (`dokkabei97.github.io/dokkabei-harness`). Not to be confused with a plugin's `references/` docs.
