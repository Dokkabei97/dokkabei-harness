> **English** · [한국어](README_KO.md)

# test

> Test-first guidance plus browser E2E verification — with an index of testing pitfalls that even strong seniors miss.

## Install

```
/plugin install test@dokkabei-harness
```

## Overview

`test` has two axes. `tdd-workflow` keeps the RED → GREEN → REFACTOR cycle short and acts mainly as a triage index
into specialist testing pitfalls (Spring context cache fragmentation, Kotest hook order, `runTest` virtual time, Go test
cache and `synctest`, fake timers with promises, DB rollback isolation, Elasticsearch refresh and per-shard IDF,
mutation testing). Browser verification is split into a model-invocable checklist (`e2e-chrome`, for Claude in Chrome
or Playwright MCP) and a user-invoked generator for repository Playwright specs (`/e2e`).

Nothing here assumes a stack: each guide first reads the project's build files, existing tests and `CLAUDE.md`/
`.claude/rules`. Coverage numbers are guidance, not enforcement.

## Components

### Skills

- `tdd-workflow` (`test:tdd-workflow`) — Test-first cycle, Prove-It bug reproduction, test-level choice, coverage
  interpretation, and a symptom → reference table. References (each item has an ID such as `TST-JVM-01` with
  applicability, signal, mechanism, fix, counter-case, verification and source):
  `jvm-kotlin.md`, `go.md`, `typescript.md`, `python.md`, `integration-data.md`, `coverage-mutation.md`.
- `e2e-chrome` (`test:e2e-chrome`) — Browser verification checklist: pick the tool, pre-flight checks, scenario
  decomposition, per-step evidence (snapshot, screenshot, console, network), completion criteria and report format.
  References: `browser-tools.md` (Claude in Chrome / Playwright MCP notes), `playwright.md` (`TST-PW-01..10`).

### Commands

- `/e2e <journey>` — Writes and runs Playwright specs that stay in the repository; trace-based failure diagnosis,
  flaky checks, and use as a `/loop-run --gate-cmd` gate. User-invoked only (`disable-model-invocation: true`).

### Agents

- `chrome-e2e-runner` — Runs a browser verification plan in a separate context and returns per-step evidence and a
  PASS/FAIL/SKIP report. Inherits the session's MCP browser tools (no `tools` restriction); preloads `e2e-chrome`.

## Usage

- Test-first work or a flaky/slow test: just describe it — `tdd-workflow` activates on its own, or call `/test:tdd-workflow`.
- "Check this page in the browser": `e2e-chrome` activates; long journeys can be delegated to `chrome-e2e-runner`.
- A regression E2E test in the repo: `/e2e Checkout with a saved card`.

## Dependencies

None required. Works well with:

- `harness` — pass a test command to `/loop-run --gate-cmd` to iterate until green.
- Stack plugins (`kotlin-spring`, `go-mux`, `python-fastapi`, `nextjs`, `search`) for stack-specific performance, GC
  and concurrency knowledge.

## Notes

- Claude in Chrome drives the user's real profile and sessions; irreversible actions require confirmation.
- Retired in 2026-10: the `/tdd` command (merged into `tdd-workflow`) and the `/e2e-chrome` command (rewritten as the
  `e2e-chrome` skill). Originals are in `archive/components/test/commands/`.
