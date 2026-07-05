> **English** · [한국어](README_KO.md)

# harness

> A meta-plugin that designs, generates, and validates harnesses (multi-agent teams), and even provides a lightweight loop for safely running one-shot iterative tasks.

## Overview

`harness` is a harness for building other harnesses. It analyzes a domain to design an agent team (`team-harness`),
scaffolds the decided design into actual component files (`create-flow` + `flow-scaffolding`),
and machine-validates the output against 10 rulesets (`verify-flow` + `flow-validation`). In other words, it splits
the single responsibility of "design → generate → validate" across three skills + two commands. It is a fork that starts
from the monolithic single skill of [revfactory/harness](https://github.com/revfactory/harness) (Apache-2.0) and
restructures it to fit the in-house marketplace; the detailed mapping is in `docs/ARCHITECTURE.md`.

On top of this, it embeds a **lightweight general-purpose loop engine** (`/loop-run`·`/loop-stop`) that iterates only "until the gate is green"
without an output structure (prd/tasks). This loop records `engine=generic` in `loop-active`, forming a triple boundary
whose ownership does not overlap with the greenfield pipeline (mvp) or brownfield task-decomposition (feature-loop) loops.
The owner of the completion decision is not the model but the harness — the Stop hook directly verifies the deterministic gate and
the completion promise.

## Components

### Commands

- `/create-flow` — Interactively scaffolds agents, commands, skills, hooks, plugins, and teams following project conventions. When `--type` is unspecified it auto-detects from the name pattern, `--team` batch-generates team components, and `--from-lessons` turns `#가드-훅-후보`-tagged entries from `tasks/lessons.md` into warn/block guard hook drafts (a user approval gate is required).
- `/verify-flow` — Validates existing components against conventions. It judges structure, content quality, cross-references, and security by severity to produce a Health Score report, and with `--fix auto` auto-fixes deterministic defects.
- `/loop-run` — Initializes `loop-active(engine=generic)`·`loop-state.json` with a goal prompt and `--gate-cmd` (required), then enters the Stop hook loop engine. Used for one-shot iterations where completion is defined by a single validation command, such as "until lint is 0"·"until tests are green".
- `/loop-stop` — A manual kill switch for the `engine=generic` loop. It deletes `loop-active` to immediately disable the Stop hook and leaves a handoff of the goal·iteration·last gate result in `progress.md`. It does not touch loops owned by other engines (mvp/floop) and instead points to the relevant kill switch.

### Skills

- `team-harness` — A multi-agent team design meta-skill. It performs domain analysis, selection among 6 architecture patterns (Pipeline/Fan-out·Fan-in/Expert Pool/Producer-Reviewer/Supervisor/Hierarchical), validation·loop reinforcement patterns, and orchestrator design, delegating generation to `/create-flow` and validation to `/verify-flow`. Activates on things like "하네스 구성해줘", "팀 설계해줘".
- `flow-scaffolding` — A standard template system for each component type (9 kinds: command·agent·skill·hook·plugin·team agent·orchestrator·team config·loop Stop hook). It includes a frontmatter field reference and naming conventions and is used by `/create-flow`.
- `flow-validation` — A component validation ruleset and checklist. It holds the rules of 10 categories (CMD·AGT·SKL·HK·LOOP·TEAM·ORC·XRF·SEC·QUA), a severity scale, and the Health Score calculation method, and is used by `/verify-flow`. Among them, the LOOP ruleset (10 rules) is a safety protocol exclusive to the Stop hook loop engine.

### Hooks

- `Stop` (`*`) → `hooks/generic-loop-stop-hook.sh` — The lightweight general-purpose loop engine. It activates only when `engine=generic` is specified in `.planning/loop-active`, and on every termination attempt it verifies the stop conditions (① the deterministic gate is green ② the exact completion promise string in `progress.md`). If unmet, it blocks termination with `exit 2` and re-injects the task along with the failure output; when met or when a guardrail is reached, it releases `loop-active` and permits termination. It does not intervene (`exit 0`) with legacy/other-engine `loop-active`.

## Usage

- **Harness design**: For requests like "팀 설계해줘"·"하네스 구성해줘", `team-harness` auto-activates and proceeds through domain analysis → pattern selection → orchestrator design, with actual file creation continuing via `/create-flow --team` and validation via `/verify-flow --target team`.
- **Component generation·validation**: When you need a single component, call it directly like `/create-flow <name> --type skill`, and right after generation confirm convention compliance with `/verify-flow <path> --target skill`. The two commands are a mutually complementary pair.
- **Starting/stopping the lightweight loop**:
  ```
  /loop-run "ESLint 에러를 0으로 만들어라" --gate-cmd "npx eslint src --max-warnings 0"
  # gate dry-run → initialize loop-active(engine=generic)·loop-state.json → enter loop
  # guardrails: max-iter 12 / 60 min / no-progress 2 times / kill switch /loop-stop
  # normal termination when gate is green + <promise>LOOP_COMPLETE</promise> is recorded in progress.md
  /loop-stop
  # delete engine=generic loop-active → immediately disable Stop hook + record progress.md handoff
  ```
  You can adjust the stop string and limits with `--promise`·`--max-iter`·`--max-minutes`. When it grows large enough to need a story/task list, promote it to `/mvp-new`·`/floop-new`.

## Dependencies

`plugin.json` has no hard dependencies. It has synergy when used together with the following plugins.

- `mvp`(`/mvp-run`)·`feature-loop`(`/floop-run`) — Greenfield/brownfield loops that need an output structure. Via the shared `engine` scope contract they form a triple boundary with `/loop-run`.
- `observe`(`/observe-report`) — Observes and improves which prompts the harnesses built here actually activated on·completed.
- `workflow`(`/retro`) — Tags recurring mistakes into `tasks/lessons.md` as `#가드-훅-후보`. It is the input source for `/create-flow --from-lessons`.

## Notes

- **The loop is opt-in**: The Stop hook intervenes only when there is an `engine=generic` `loop-active`. It never obstructs termination of an ordinary session that did not use `/loop-run`.
- **The harness is the owner of the completion decision**: The stop condition is judged not by the model's self-assessment but by the hook, via the deterministic gate (exit code + failure-marker correction) and the exact promise string (`grep -qF`).
- **Guardrail defaults**: max-iter 12 times · time limit 60 min · no-progress (same failure signature 2 times in a row). On reaching them, it automatically releases the loop and records the reason in `BLOCKED.md`.
- **`jq` required**: The loop engine uses `jq` for state judgment. If not installed, judgment is impossible and termination is permitted (graceful degrade), while `loop-active` is retained.
- **Source·license**: A `revfactory/harness` (Apache-2.0) fork. The principle for upstream synchronization is selective concept porting, not version chasing (see `docs/ARCHITECTURE.md`).
