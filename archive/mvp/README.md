> **English** · [한국어](README_KO.md)

# mvp

> A greenfield MVP loop engineering harness that carries a one-line idea through planning (PRD) → design → stack selection·scaffolding → a PRD-driven development loop to completion.

## Overview

`mvp` is a harness that, when building a new business/service from an empty repo, starts from a one-line idea where even "what to build" is undecided and drives it all the way to a working MVP as a **gate-based state machine**. It proceeds through Stage 0 (intake) → 1 (planning PRD) → 2 (design spec) → 3 (stack selection·scaffolding) → 4 (PRD-driven development loop), and each Stage transition opens only after passing both the deterministic gate script and the skeptical checker agent's refutation.

The core of the design is that **the arbiter of completion is the harness, not the model**. The Stage 4 development loop's `Stop` hook loop engine, on every iteration, verifies the stop conditions (deterministic gate green + all-stories passes + verified marker + E2E gate (optional) + completion promise), and when unmet, sustains the loop via `exit 2` re-injection. It blocks "test fraud" through Producer-Reviewer cross-verification that fully separates the maker (implementation) and the checker (refutation), and it seals off runaway behavior with guardrails such as max-iter·no-progress·time cap·kill switch. The `.planning/` directory becomes both memory and a resume point, so work can continue even if the session is interrupted.

This harness is **greenfield-only**. Feature additions·modifications on an existing (brownfield) codebase are delegated to `feature-loop` or the stack-specific plugins (kotlin-spring·python-fastapi·go-mux·nextjs·search). Conversely, the business-hypothesis phase is handled by the `startup` plugin, and its output is taken over via `/mvp-from-startup`.

## Components

### Commands (7)

- `/mvp-new "<one-line idea>"` — Harness entry point. Runs Stage 0~3 (intake→planning→design→scaffolding) on a gate basis and confirms whether to start the development loop.
- `/mvp-from-startup` — A bridge that succeeds the `startup` plugin's output (`.planning/business/`) into Stage 0 intake. Enters straight into the planning PRD from a validated business hypothesis.
- `/mvp-run` — Starts/resumes the Stage 4 development loop. After performing the resume protocol, it initializes `loop-active`·`loop-state.json` and enters the Stop hook loop engine.
- `/mvp-status` — Read-only lookup of progress (story n/m·iteration count·elapsed time·verified marker·BLOCKED·leftover loop-active). Changes no state.
- `/mvp-stop` — Loop safe-stop kill switch. Immediately neutralizes the Stop hook engine by deleting `loop-active`, records a handoff, then switches status to paused.
- `/mvp-gate` — Manual (re)run of the current Stage gate. Determines the Stage from the master file, runs the corresponding gate script and checker, and reports pass/fail/ambiguous.
- `/mvp-eval` — Runs product validation (evaluation). When the PRD success metric is model quality (F1·accuracy, etc.), it measures against a golden set + real model calls and decides thresholds via `gate-eval.sh`.

### Agents (6, all opus)

- `product-strategist` — Planning strategist. Idea intake (up to 3 questions + recommended defaults), PRD authoring, prd.json user story draft, Stage 2 coverage matrix verification.
- `ux-designer` — Design spec designer. Converts the PRD into a single `design-spec.md` output (IA·user flow·screen spec·wireframe·tokens·4 states). No code generation.
- `tech-architect` — Stack selection·scaffolding specialist. Comparative recommendation of 2~3 candidates from the standard 4 stacks (non-coercive), repo skeleton + smoke test generation, `.planning/` initialization·gate-cmd recording·initial commit.
- `mvp-builder` — Development loop maker discipline. Implements one unfinished story test-first to make the gate green, and after passing verification closes it with one commit (by default the main session internalizes this).
- `mvp-verifier` — Skeptical checker. Double refutation separated from the maker (Stage 1 PRD refutation / Stage 4 story AC refutation). Creates the `verified/{story-id}` marker only when refutation fails.
- `eval-engineer` — Product validation engineer. Fills the "verified code ≠ verified product" gap. Performs golden-set construction·real model calls·metric computation (macro F1, etc.) separately from the deterministic regression.

### Skills (5)

- `mvp-orchestrator` — The canonical harness orchestrator. Performs the entire Stage state machine logic and auto-triggers on "build me an MVP"·greenfield new builds·`/mvp-new`·`/mvp-run`. (references: gate-policy·headless-recipe·stack-presets)
- `mvp-loop-protocol` — Stage 4 loop operating protocol. Standard cycle per iteration, `/mvp-run` 4-step resume, 3-way stop-condition combination, environment variable tuning, `loop-active` lifecycle, 5 guardrails, BLOCKED escalation.
- `prd-authoring` — PRD authoring standard. Required sections, Given-When-Then AC (falsifiable verification form), prd.json schema·jq validation expression, scope-cut 2-week rule, 1 story = 1 iteration sizing.
- `mvp-design-spec` — Design spec authoring standard. Required structure of IA·user flow·screen spec·tokens, `[story: S-xx]` mapping tag format (gate-design.sh compatible), mandatory 4 states, coverage matrix.
- `mvp-eval-harness` — Product validation (evaluation) harness standard. Golden-set construction criteria, `@pytest.mark.eval` separation (skip by default), report.json schema, `gate-eval.sh` soft-gate contract, threshold = PRD canon principle.

### Hooks (6)

- `SessionStart` → `mvp-session-init.sh` — Injects resume-guidance context only when the `.planning/mvp-*.md` status is in_progress; otherwise no action.
- `Stop` → `mvp-loop-stop-hook.sh` — The loop engine. Verifies the 3-way stop-condition combination only when `loop-active` exists, and re-injects via `exit 2` when unmet.
- `PreCompact` → `precompact-anchor.sh mvp` — Just before compaction, prints a resume anchor (master path·next target·gate·iteration·discipline) within 5 lines; does not intervene in ordinary sessions.
- `SubagentStop` → `subagent-stop-verify.sh mvp` — If a verify-round is pending but it exits without a verified/refuted marker, re-injects via `exit 2` (up to 2 rounds, self-healing when blocked).
- `PreToolUse(Bash)` → `test-guard.sh` — Blocks test file deletion (`rm test|spec`) while the loop is active. Deterministic enforcement of the no-test-deletion rule.
- `PostToolUse(Edit|Write)` → `prd-guard.sh` — Enforces maker/checker separation. Blocks `passes:true` without a verified marker via `exit 2` and reverts it to false.

### Gate scripts (not hook-registered — called via Bash by the orchestrator/commands)

- `gate-prd.sh` (Stage 1) — prd.md required headings + prd.json jq schema + story count 3~10.
- `gate-design.sh` (Stage 2) — grep-checks that every story id's `[story: S-xx]` tag appears in design-spec.md.
- `gate-scaffold.sh` (Stage 3) — clean working tree + initial commit exists + `.planning/` required files·verified directory.
- `gate-eval.sh` (evaluation) — report.json exists·required fields·`value ≥ threshold`. A data/model-dependent soft gate (unmeasured = warning exit 2).

### Runner

- `bin/mvp-headless.sh` — Stage 4 unattended/overnight loop runner (context-reset Ralph pattern). An external `while` spins up a fresh `claude -p` each iteration. An auxiliary engine that shares the same `.planning`·same gates·same decision protocol as the Stop hook engine.

## Usage

1. **Start**: `/mvp-new "resume-polishing service for job seekers"` → intake questions (up to 3) → PRD → design spec → stack selection·scaffolding. Along the way, confirmation is taken at 2 user gates (★G1 scope approval, ★G2 stack selection).
2. **Loop start**: Once scaffolding passes, enter the Stage 4 development loop with `/mvp-run`. From then on the completion decision is performed automatically by the Stop hook.
3. **Status check**: At any time, use `/mvp-status` (read-only) to look up story progress·iteration count·elapsed time·leftover flags.
4. **Stop**: Immediately safe-stop (kill switch) with `/mvp-stop`. Resume afterward with `/mvp-run`.
5. **Re-verification·evaluation**: After touching up an artifact, re-run the current Stage gate with `/mvp-gate`. If there is a model quality metric, measure it with `/mvp-eval`.

Options: `--auto` (auto-adopt the 2 gates as recommendations, for hackathons), `--stack <preset>` (pre-specify kotlin-spring·python-fastapi·react-next·go-mux to skip ★G2), `--stories-max <n>` (story count cap, default 10), `--max-iter`/`--max-minutes` (adjust this run's guardrails), `--headless` (guidance for running the unattended runner), `--cross-check` (opt-in cross-model refutation).

Auto-activation: the `mvp-orchestrator` skill triggers on requests like "build me an MVP"·"new service prototype"·"turn an idea into a working product" and on greenfield new builds. It does not activate for single-feature work on an existing codebase.

## Dependencies

- **requires**: `base` — common hook/config foundation.
- **linkage**: `startup` (business hypothesis → succeeded via `/mvp-from-startup`), `feature-loop` (brownfield-facing loop, shares the loop engine), stack-specific plugins (kotlin-spring·python-fastapi·go-mux·nextjs·search — called within the loop), `etc` (uses `etc:with` for `--cross-check`'s cross-model refutation; falls back to same-model 2 rounds when not installed).

## Notes

- **Model quality evaluation does not replace regression**: `/mvp-eval`·`eval-engineer` are a soft gate separate from the deterministic regression suite (`@pytest.mark.eval` separation, skip by default). The threshold can be overridden with `MVP_EVAL_F1_MIN`, but the canon is the PRD success metric.
- **Environment variable tuning**: `LOOP_TEST_CMD`·`LOOP_PROMISE`·`LOOP_MAX_ITER` (default 24)·`LOOP_MAX_MINUTES` (default 120)·`MVP_STORIES_MAX` (default 10)·`LOOP_CLAUDE_BIN`·`LOOP_WATCHDOG_INTERVAL`.
- **Guardrails**: max-iter (default 24)·no-progress (2 times)·time cap (default 120 minutes)·kill switch (`/mvp-stop`). On abnormal session termination, check for leftover `loop-active` with `/mvp-status` and tidy up with `/mvp-stop`.
- **One MVP per repo premise**: if `.planning/mvp-*.md` already exists, `/mvp-new` does not create a new one but guides toward resuming.
- **The standard 4 stacks are non-coercive**: `tech-architect` recommends candidates comparatively but does not force them, and requires justification for proposals outside the 4 stacks.
