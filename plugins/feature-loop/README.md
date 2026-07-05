> **English** · [한국어](README_KO.md)

# feature-loop

> A loop-engineering harness that takes a one-line natural-language feature request on top of an existing (brownfield) codebase and drives it to completion without regressions.

## Overview

`feature-loop` is an orchestrator that, when adding to or modifying a feature in an already in-progress or completed project, autonomously drives a one-line natural-language request like "add this feature" to completion through **codebase-analysis-based task decomposition (`tasks.json`) → baseline capture → regression-safe development loop**. Its core proposition is **"completion is judged by the harness, not the model,"** and — tailored to brownfield — it adds **"no-regression is also judged by the harness against the baseline."**

By design it reuses the `mvp` harness's proven loop infrastructure (Stop-hook loop engine + maker/checker refutation verification + guardrails + `.planning/` memory), but swaps two points for brownfield. The input is not PRD generation but **task decomposition**, and the gate is not generation verification but **baseline regression prevention**. Inside the loop it calls the stack plugins (`kotlin-spring`·`python-fastapi`·`go-mux`·`nextjs`), `analyze` (checker lens), `test` (tdd/e2e), and `workflow` (spec/ship) as needed.

The boundary is clear. **It does not activate for greenfield new services that start from planning in an empty/new repo; in that case it delegates to the `mvp` plugin (`/mvp-new`).** User intervention is minimized to a single task-list approval (★G1) gate.

## Components

### Commands

- `/floop-new` — The harness entry point. It takes a one-line natural-language feature request and runs Stage A (intake + stack detection + baseline capture) → Stage B (codebase-analysis-based task decomposition + ★G1 task-list approval) as a gated state machine. Brownfield-only, and it supports isolated startup in a dedicated git worktree via `--worktree`.
- `/floop-run` — Starts/resumes the development loop (Stage C). After performing the resume protocol based on the master file status, it initializes the `loop-active` flag and `loop-state.json` and enters the Stop-hook loop engine. `--max-iter` sets this run's iteration cap and `--headless` handles unattended-runner execution.
- `/floop-status` — Read-only inquiry into progress. It reports task passes n/m, iteration count/cap, elapsed time, baseline status, the verified marker, BLOCKED status, and whether `loop-active` remains, in a single screen. It changes no state.
- `/floop-stop` — Safe loop stop (kill switch). It deletes `loop-active` to immediately neutralize the Stop-hook loop engine, records the current task state as a handoff in `progress.md`, and switches the master status to `paused`. It is a manual stop mechanism separate from the guardrails, and is idempotent.
- `/floop-gate` — Manual (re)run of the current Stage gate. It determines the Stage from the master file, runs the corresponding deterministic gate script (`hooks/gates/*.sh`), checks baseline regression, then dispatches `feature-verifier` to report ✅pass/⚠️fail/❓ambiguous. It does not transition Stages or modify artifacts.

### Agents (all `opus`)

- `task-planner` — The brownfield task-decomposition maker. It decomposes a natural-language request into vertical-slice-unit `tasks.json`, grounded in analysis of the existing codebase (impact scope, existing patterns, reuse points). Each AC is a Given-When-Then verification-form sentence that `feature-verifier` can refute, and 1 task = 1 loop-iteration size.
- `feature-builder` — The development-loop maker discipline. In the default mode the main session embodies the discipline and performs it directly. It picks exactly one incomplete (`passes:false`) task at a time, writes tests first, then makes the gate green (new AC green AND baseline regression 0) with a minimal implementation, and after passing verification closes the implementation, `tasks.json`, and `progress.md` in a single `feat: T-xx` commit. Only for parallel implementation is it dispatched as a worktree-isolated subagent.
- `feature-verifier` — The skeptical verifier (checker). Fully separated from the maker, it performs triple refutation (① task AC refutation, ②ᴿ regression refutation against baseline, ③ test-fraud detection). **It intentionally does not hold the `Edit` tool**, structurally blocking the path where the verifier directly fixes the target to make it pass, and it creates the `.planning/verified/{task-id}` marker only when refutation fails.

### Skills

- `feature-loop-orchestrator` — The harness orchestrator. It autonomously drives a natural-language request to completion via the Stage A–C gated state machine and delegates each Stage's maker/checker to specialized agents. It applies when `/floop-new`·`/floop-run` is run or on brownfield feature add/modify requests.
- `floop-loop-protocol` — The Stage C development-loop operating protocol. It defines the standard cycle per iteration, the 4-step `/floop-run` resume protocol, the stop-condition conjunction, environment-variable tuning, the `loop-active` lifecycle, the 5 guardrails, and BLOCKED escalation. `references/worktree-lanes.md` holds the 3-stage roadmap of worktree isolation → parallel lanes → Agent Teams.
- `task-decomposition` — The task-decomposition standard. It specifies vertical-slice sizing, how to write Given-When-Then verification-form ACs, the mandatory regression-preservation AC, the `tasks.json` schema and jq validation expressions, and the `gate-tasks.sh` pass criteria (id `^T-[0-9]{2}$` · count 2–10 · all-items `passes:false`).

### Hooks

- `SessionStart` → `floop-session-init.sh` — Injects resume-guidance context only when it detects an in-progress feature-loop (master file status `in_progress`), and does nothing otherwise.
- `Stop` → `floop-loop-stop-hook.sh` — The loop engine. Only when `loop-active` exists does it verify the stop-condition conjunction (gate green + baseline regression 0 + verified marker + completion promise), and when unmet it re-injects with exit 2 to keep the loop going.
- `PreCompact` → `precompact-anchor.sh floop` — The loop-resume anchor just before compaction. Only when `loop-active` is present and the engine is floop does it print the master path, next target, gate, iteration, and discipline within 5 lines, and it does not intervene in ordinary sessions.
- `SubagentStop` → `subagent-stop-verify.sh floop` — Verifier-result recording enforcement. If it exits in the `verify-round/{id}` pending state without a verified/refuted marker, it re-injects with exit 2 (up to 2 rounds).
- `PreToolUse(Bash)` → `test-guard.sh` — Blocks test-file deletion while the loop is active, deterministically preserving regression-gate trustworthiness (the `rm test|spec` pattern filter is inside the script).
- `PostToolUse(Edit|Write)` → `tasks-guard.sh` — Enforces maker/checker separation. It blocks a `passes:true` without a verified marker via exit 2 and reverts it to `false`.

### Other Components

- `bin/floop-headless.sh` — A headless runner for unattended/overnight batch (context-reset-style Ralph pattern). An external `while` loop spins up a fresh `claude -p` each iteration, an auxiliary engine that shares the same `.planning` and the same gates (including the ②ᴿ baseline regression gate) as the Stop-hook engine.
- `hooks/gates/capture-baseline.sh`, `hooks/gates/gate-tasks.sh` — Deterministic gate scripts. They are not registered to hooks; the orchestrator/commands invoke them via Bash (baseline capture · tasks.json schema gate).

## Usage

1. **Start** — In an existing codebase, call `/floop-new "<one-line feature request>"`. Stage A detects the stack and captures the baseline, then Stage B decomposes `tasks.json` and gets user confirmation at the ★G1 (task-list approval) gate. With `--worktree` you can start isolated in a dedicated worktree/branch, and `--gate-cmd`·`--e2e-cmd`·`--tasks-max` adjust the gate commands and the task cap.
2. **Run the loop** — Enter the Stage C development loop with `/floop-run`. Each iteration the Stop-hook loop engine implements one incomplete task test-first → verifies → commits, and judges the stop conditions by itself.
3. **Stop conditions (conjunction)** — The loop terminates only when all of ① deterministic gate green (exit 0 + failure-marker correction) ∧ jq all-passes, ②ᴿ baseline regression 0, ② verified marker, ②ᴱ E2E acceptance gate green (when configured), and ③ `<promise>FEATURE_COMPLETE</promise>` are satisfied.
4. **Status/stop** — Read the status anytime with `/floop-status`, and immediately stop safely (switch to paused + handoff) with `/floop-stop`. A stopped loop is taken over by `/floop-run` via the resume protocol.

Automatic activation: The `feature-loop-orchestrator` skill triggers on feature-work requests for a project that already has code, like "add this feature," "refactor X," or "attach Y to this codebase." It does not activate on empty/new repo requests.

## Dependencies

- `requires`: `base`
- Plugins that pair well: the stack plugins (`kotlin-spring`·`python-fastapi`·`go-mux`·`nextjs`), `analyze` (checker lens), `test` (tdd/e2e), `workflow` (spec/ship). Greenfield new services are delegated to `mvp`.

## Notes

- **Guardrails**: The loop prevents infinite iteration with 5 safeguards including max-iter (default 24) · no-progress (2 times) · time cap (default 120 minutes). `/floop-stop` is a manual kill switch separate from these.
- **Environment variables** (loop tuning): `LOOP_TEST_CMD` · `LOOP_E2E_CMD` · `LOOP_PROMISE` · `LOOP_MAX_ITER` · `LOOP_MAX_MINUTES`.
- **Worktree isolation** is stage① (implemented) and the sequential loop is invariant. Parallel lanes (stage②) · Agent Teams (stage③) are roadmap stages and disabled by default (`references/worktree-lanes.md`).
- **Preserving regression-gate trust**: Deletion, weakening, or reverse-editing of expected values in existing tests is blocked by the hooks and the verifier. Since this is an autonomous loop that presupposes a paid plan/token consumption, confirm the iteration cap and gate commands before running, especially for `--headless` unattended execution.
