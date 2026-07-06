> **English** · [한국어](CONTRIBUTING_KO.md)

# Contributing to dokkabei-harness

Thanks for your interest. This repository is a **Claude Code plugin marketplace** — 20 plugins under
`plugins/<name>/`, registered in `.claude-plugin/marketplace.json`. Contributions that add a
distinct-domain plugin, sharpen an existing component, or harden the loop engine are all welcome.

## Ground truth first

Before changing anything, read [`CLAUDE.md`](CLAUDE.md) — it encodes the absolute rules distilled from
measured incident history. The most important ones bite silently if ignored:

- **`hooks.json` `matcher` accepts only a tool-name regex** (`Bash`, `Edit|Write`). Putting a
  `tool == "X"` expression or a command-content filter in the matcher makes the hook **silently miss
  activation**. Filter command/arguments inside the hook script instead.
- **Plugins are edited only in the repo source.** Never modify the `~/.claude/plugins/cache` clone
  directly (cache-drift incident history). The propagation path is: commit → `/plugin update`.
- **Plugin versions are synced in two places**: `plugins/<name>/.claude-plugin/plugin.json` ↔ the
  matching entry in `.claude-plugin/marketplace.json`. They must match to the string.
- **When you modify a hook, update its `tests/hooks/*.bats` regression tests in the same change.**
  PreToolUse blocking is exit 2 (exit 1 passes through as a non-blocking warning).

## Development setup

There is **no `package.json`** — this is not an npm project. The checks that CI runs (and that you
should run locally before opening a PR):

```sh
bats tests/hooks                                            # hook + loop-engine regression suite
jq . plugins/*/hooks/hooks.json                             # hooks.json validity
shellcheck --severity=error plugins/**/{hooks,bin}/**/*.sh  # shell hook/runner lint
```

`bats` runs on an ubuntu + macOS matrix in CI (`.github/workflows/loop-engine-ci.yml`) — macOS is
included to exercise the `md5sum`→`md5`/`shasum` fallback and bash 3.2 portability. If you touch a
hook or shell runner, add/adjust the corresponding `.bats` case so the matrix stays green.

## Building components

Don't hand-scaffold. This repo ships its own tooling:

- **`/create-flow`** (`harness` plugin) — interactive scaffolding for agents, commands, skills, and
  hooks that follows every convention below.
- **`/verify-flow`** (`harness` plugin) — validates a component against the ruleset
  (`plugins/harness/skills/flow-validation/`) and reports a severity-rated health score.

Prefer the **skill format** for new components (Claude Code v2.1.3+ unified command/skill). Reuse
before you create: if an existing plugin already covers the domain, extend it rather than adding a
near-duplicate — overlapping components create trigger conflicts and maintenance debt.

## Conventions

- **Commits**: Conventional Commits with a Korean body — `feat(scope): …`, `fix(base): …`.
- **Component descriptions** (skill/command/agent frontmatter) are **bilingual**: the Korean original
  first, then an English summary with a `Use when: …` trigger clause. This keeps activation working for
  both Korean and English prompts. Keep the total under ~1,400 characters (the skill listing truncates
  at 1,536).
- **READMEs are paired**: English `README.md` is the main file, Korean lives in `README_KO.md`.
- **Skill token budget**: SKILL.md under ~500 lines; orchestrator skills under 500 (optimal < 300).
  Move heavy templates/presets into `references/`.

## Pull request checklist

1. Branch from `main` (never commit directly to `main`).
2. `bats tests/hooks` is green locally, plus `jq` and `shellcheck` clean.
3. If you added/changed a component, `/verify-flow` reports no Critical/High findings.
4. If you added a plugin, both version locations are synced and the marketplace entry is complete.
5. Fill in the PR template — describe what changed, why, and how you verified it.

## Reporting bugs & requesting features

Use the [issue templates](.github/ISSUE_TEMPLATE/). For a bug, a failing `bats` case reproduces it
deterministically and is the fastest path to a fix. For a feature, name the **distinct domain** a new
plugin would own — the bar for a new plugin is "no existing plugin can absorb this."

## License

By contributing, you agree that your contributions are licensed under the repository's
[Apache-2.0](LICENSE) license.
