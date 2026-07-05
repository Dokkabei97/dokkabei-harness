> **English** · [한국어](README_KO.md)

# base

> The foundational plugin of the loop harness, providing a common guard-hook layer that automatically triggers on code edits and shell commands, plus multi-language LSP.

## Overview

`base` is the lowest-level foundational layer that other plugins commonly lay down first. Attached to Claude Code's `PreToolUse`/`PostToolUse` hooks, it activates automatically at every shell command and file edit without any separate invocation. It blocks dangerous behaviors (e.g., dev servers outside tmux, indiscriminate creation of document files) and gives non-blocking feedback for the rest — format cleanup, compile checks, security vulnerability warnings, and so on.

There are two core design intents. First, real-time security warnings (`warn-security`) catch high-signal patterns such as secrets, injection, and deserialization the moment they are edited, but operate strictly as warning-only that never block the flow. Second, it serves as the safety net that loop-type harnesses like `mvp` and `feature-loop` presume via `requires` — this hook layer becomes the guardrail while an autonomous iteration loop runs. The plugin itself exposes no commands, agents, or skills; it is composed purely of hooks and LSP configuration.

## Components

### Hooks (hooks/hooks.json → bin/hooks/*.js, 16 total)

All hooks are Node.js scripts. The matcher in `hooks.json` specifies only the tool name (`Bash`/`Edit`/`Write`), while the detailed command/extension filtering is performed inside each script (a measured workaround for expression matchers not activating).

**PreToolUse — blocking/reminder**

- `block-dev-server.js` (Bash) → blocks with `exit 2` when a dev server (`npm/pnpm/yarn/bun dev`, `uvicorn`, `flask run`, `manage.py runserver`, `uv run …`) is run outside tmux, to guarantee log access
- `warn-tmux.js` (Bash) → recommends keeping the session alive (non-blocking) when a long-running command (`npm/pnpm/yarn install·test`, `gradlew`, `pip install`, `uv sync`, `pytest`, `docker`, `make`, etc.) is run outside tmux
- `warn-git-push.js` (Bash) → change-review reminder right before `git push` (non-blocking, passes through)
- `block-md-creation.js` (Write) → blocks with `exit 2` the creation of `.md`/`.txt` files outside the allowlist (`README`/`CLAUDE`/`AGENTS`/`CONTRIBUTING`/`HANDOFF`/`CHANGELOG`) and the `.planning/`·`tasks/` paths (to prevent document sprawl)

**PostToolUse — format/compile/lint**

- `format-prettier.js` (Edit) → auto-formats with Prettier after editing `.ts/.tsx/.js/.jsx`
- `format-ktlint.js` (Edit) → auto-formats with ktlintFormat after editing `.kt/.kts`
- `check-tsc.js` (Edit) → type-checks with `tsc --noEmit` after editing `.ts/.tsx`, reporting only errors related to the edited file
- `check-kotlin-compile.js` (Edit) → compile check after editing `.kt/.kts`
- `check-py-compile.js` (Edit) → `py_compile` syntax check after editing `.py`
- `warn-console-log.js` (Edit) → warns about leftover `console.log` in JS/TS
- `warn-println.js` (Edit) → warns about leftover `println()` in Kotlin
- `warn-print.js` (Edit) → warns about leftover `print()` in Python

**PostToolUse — security warning**

- `warn-security.js` (Edit·Write) → detects and warns about 15 classes of high-signal security patterns in edited code files (AWS/GitHub/Slack tokens·Private Key·credential URLs·hardcoded secrets, SQL injection·command concatenation·dynamic eval/exec, pickle/`yaml.load`/ObjectInputStream deserialization, TLS verification disabling, innerHTML/dangerouslySetInnerHTML XSS). **Always warning-only that passes through**, and secret values are masked, leaving only the first 4 characters in the output

**PostToolUse — build/collaboration**

- `log-pr-mr.js` (Bash) → on successful `gh pr create`/`glab mr create`, logs the PR/MR URL and review·approval command hints
- `notify-build-async.js` (Bash, async, timeout 30s) → `npm/pnpm/yarn build` completion notification (background, non-blocking)
- `notify-gradle-build-async.js` (Bash, async, timeout 60s) → Gradle build analysis notification (background, non-blocking)

### LSP (.lsp.json)

Registers a Language Server per edited-target language to provide diagnostics, go-to-definition, and so on.

- `typescript-language-server` → `.ts/.tsx/.js/.jsx`
- `kotlin-language-server` → `.kt/.kts`
- `jdtls` → `.java`
- `pyright-langserver` → `.py`
- `gopls` → `.go`

## Usage

No separate invocation is needed after installation. As long as the plugin is enabled, the relevant hooks activate automatically at every shell command execution (`Bash`) and file edit (`Edit`/`Write`).

- **Blocking hooks** (`block-dev-server`, `block-md-creation`) stop the corresponding tool call with `exit 2`. Run the dev server inside tmux (`tmux new-session -d -s dev "npm run dev"`), and consolidate documents into `README.md` or an allowed path to pass through.
- **Warning hooks** only leave a message on standard error and proceed as-is.
- If a `warn-security` warning is on intended code, suppress it by attaching a `security-ok` comment to that line.

## Dependencies

- This plugin itself has no `requires`/`dependencies` (can be installed standalone).
- Loop-type harnesses such as `mvp` and `feature-loop` presume `base` via `requires` — since it becomes a safety net during loop execution, using them together is the default combination.

## Notes

- **Runtime**: All hooks run with `node`. Check/format hooks such as Prettier/ktlint/tsc only operate when the project has the corresponding tool (and configuration such as `tsconfig.json`), and pass silently when absent.
- **tmux premise**: Dev server blocking and long-running warnings determine the tmux session by the presence of the `TMUX` environment variable.
- **Warning vs blocking convention**: `PreToolUse` blocking must be `exit 2` (=`exit 1` passes through as a non-blocking warning). All warning hooks, including `warn-security`, guarantee passthrough.
- **ReDoS defense**: `warn-security` excludes files over 1MB·lines over 2000 characters·binaries (NUL bytes)·`.md`/`.lock` from inspection to prevent runaway regex backtracking.
