> **English** · [한국어](README_KO.md)

# etc
> A collection of general-purpose utility skills that connect external AI CLIs (Antigravity, Codex, Copilot) to Claude Code

## Overview
`etc` is a "miscellaneous" plugin that gathers general-purpose utility skills not tied to any specific domain. Currently it provides two skills that invoke external AI CLI tools as slash commands from within a Claude Code session. One is a fallback fetcher that uses the Antigravity CLI (`agy`) to fetch web pages as clean Markdown; the other is an orchestrator that routes tasks to Codex, Antigravity, and Copilot based on complexity and runs them in collaborate, delegate, or parallel modes. Both skills are set to `disable-model-invocation: true`, so the model does not activate them on its own — they run opt-in, only when the user explicitly types the slash command.

## Components

### Skills
- `web-fetch` (`/web-fetch <url> [extraction instruction]`) — Fetches URL content as clean Markdown using the native web browsing of the Antigravity CLI (`agy`). Use it as a fallback when Claude's native `WebFetch` fails, or for explicit URL lookups and partial extraction; it uses the `Gemini 3.5 Flash (Low)` model for speed. Allowed tools are restricted to `Bash(agy *)`.
- `with` (`/with <agent|all> <task description>`) — An orchestrator that passes tasks to the Codex, Antigravity, and Copilot external AI CLI agents. It automatically scores task complexity across 6 items (0–5+) to select the model and effort per agent, and operates in three modes: collaborate (Claude-led + agents for reference), delegate (agent-led), and parallel (compare and synthesize responses from all agents). It runs with `context: fork` for context isolation.

## Usage
Neither skill activates automatically, so call them directly via slash command.

**web-fetch**
- `/web-fetch https://docs.python.org/3/library/asyncio.html`
- `/web-fetch https://react.dev/reference/react/useState extract only the API reference table`

**with** — Specify the agent as the first word (`codex` / `antigravity` (alias `agy`) / `copilot` / `all`), or omit it to auto-select by task type (code→Codex, research→Antigravity, GitHub→Copilot). The mode is determined by keywords in the prompt ("together, opinion"→collaborate, "take it, handle it"→delegate, "compare, all, all"→parallel; default is collaborate when no keyword is present).
- `/with codex refactor this function` → Simple, Codex only
- `/with antigravity take it - design the REST API` → Medium delegate
- `/with all compare these architecture approaches` → Complex parallel
- `/with debug this error` → auto-select agent (Codex)

## Notes
- The plugin itself has no declarative dependencies, but each skill requires the external CLI to be installed to work.
  - `web-fetch`: requires the Antigravity CLI `agy` (`curl -fsSL https://antigravity.google/cli/install.sh | bash`)
  - `with`: at least one of `codex`, `agy`, `copilot`. If none are installed, it guides you through the install command, and in parallel runs it shows only the results of installed agents.
- Pass a quoted display name — not an identifier — to `agy --model` (check the exact list with `agy models`).
- URLs that require authentication or are inaccessible will fail, and on failure the user is notified.
- External agent calls can take up to 20 minutes depending on complexity (in parallel runs, the per-agent timeout is applied individually).
