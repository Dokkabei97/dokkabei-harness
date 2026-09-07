> **English** · [한국어](README_KO.md)

# observe

> An observation-and-improvement plugin that correlation-logs the harness's real usage via hooks and feeds that telemetry back as improvement proposals.

## Overview

`observe` correlation-logs, via hooks, "for which prompt which skill/agent was invoked **why**, and whether that invocation **completed**" in order to diagnose the health of the harness itself. Six hooks each append session start, prompt, skill invocation, agent invocation, invocation result, and session end to `.claude/skill-trace.jsonl`, using `session_id`·`prompt_id`·`tool_use_id` as join keys to retroactively combine the prompt↔skill↔agent↔result↔session boundaries. The accumulated traces are unpacked by `/observe-report` in the order "deterministic aggregation (script) → interpretation (LLM) → improvement proposal," but it produces **only proposals, without modifying any file at all**.

The reason observe exists becomes clear in contrast with the hermes agent. Whereas the hermes agent is a generative evolution that **autonomously creates** skills/harnesses based on user behavior and grows from there, observe is on the opposite side — an **instrumentation-based improvement loop** that measures whether an **already-built harness** is being invoked well in real usage, and improves the harness itself on the basis of that telemetry data. Rather than the side that creates and multiplies new assets, this plugin's role is the side that empirically measures whether existing assets activate and complete as designed, and feeds that back through description tuning, dead-asset cleanup, and filling instrumentation gaps.

The design intent lies in clear boundaries. This plugin is dedicated to **post-hoc diagnosis of real-usage telemetry**. It delegates cost/token/tool_decision instrumentation to Claude Code's built-in OTel (`CLAUDE_CODE_ENABLE_TELEMETRY`), and delegates the a-priori benchmarking of description activation rates to `skill-creator` eval — mutually non-overlapping orthogonal complements. Also, because it records prompt originals by nature, it only operates when `OBSERVE_TRACE=1` is opted in, so it has no effect by default on other loop-type plugins like `mvp`·`feature-loop`.

Claude Code's native `/usage` breaks down recent usage by skill / subagent / MCP — observe overlaps there but goes deeper: it adds *why* each fired, whether it *completed*, missed activations, usage lifecycle (stale / archive candidates), and correction signals, and persists the trace so it compounds across sessions rather than showing a point-in-time snapshot.

v1.3.0 ports the **deterministic half** of hermes-agent's curator into the aggregator: usage-lifecycle candidates (stale ≥30d / archive ≥90d since last observed use, thresholds configurable, `--now` injectable for tests) and correction-candidate pairs (`followups` — the plain user prompt immediately after a skill/agent invocation; whether it is a correction is judged only in the LLM phase). State transitions are still proposals only. If generative coupling (auto-creating/patching skills) is ever added, the preconditions come from hermes itself: agent-created assets isolated in their own namespace/marking, archive-only (never delete), and read-before-write — until all three exist, observe stays evaluative.

## Components

### Command

- `/observe-report` — A harness health report based on skill-trace telemetry. It runs deterministic aggregation (per-skill/agent invocation counts·user/model trigger ratios·completion rate·elapsed time, unused assets, missed-activation candidate turns), then compares those candidates against the skill description to judge "missed activation" vs "skill not needed," and produces a proposal of description tuning drafts·dead-asset candidates·new-skill candidates·instrumentation improvement items. Options: `--raw` (aggregation JSON only), `--window <days>` (last N days), `--focus skills|agents|prompts`, `--stale-days/--archive-days` (lifecycle thresholds), `--followups <n>` (correction-pair cap).

### Hooks

All hooks operate only when `OBSERVE_TRACE=1`, and since they emit no stdout (zero context pollution) they always exit with `exit 0` — a tracing failure never blocks skill/agent execution.

- `SessionStart` → `trace-session.js` — Appends session start (`source`, `plugin_root`=install-root basis) as a `session_start` record. `plugin_root` is the join basis for the report to enumerate the denominator (inventory) of unused assets from the **same install** as the trace.
- `UserPromptSubmit` → `trace-prompt.js` — Appends the user prompt original as a `prompt` record (including the `is_command` approximation flag). It is subsequently combined with skill invocations by `session_id`/`prompt_id`.
- `PreToolUse` (matcher `Skill`) → `trace-skill.js` — Appends the Skill invocation (skill·args) along with its basis (`why`=preamble extraction of the current turn)·`trigger` (user/model)·`turn_command` (command-chain provenance)·`tool_use_id` (result join key). The matcher is a tool-name regex, and it was empirically confirmed that expressions (`tool == …`) do not activate (2026-07).
- `PreToolUse` (matcher `Agent|Task`) → `trace-agent.js` — Appends the subagent invocation (`subagent_type`·description·first 300 chars of prompt) along with its basis (current turn preamble) as an `agent` record. `Agent` is the tool name that `Task` was renamed to in v2.1.63, so both matchers are listed together (legacy compatibility).
- `PostToolUse` (matcher `Skill|Agent|Task`) → `trace-result.js` — Appends invocation completion as a `result` record. It joins with the Pre record via `tool_use_id` to derive elapsed time, and proxies the presence of output via `response_bytes` (the body is not recorded due to size·sensitive-information concerns). Since PostToolUse activates only on successful invocations, the mere existence of the record is a completion signal.
- `SessionEnd` → `trace-session.js` — Appends session end (`reason`) as a `session_end` record. It is the basis for distinguishing session boundaries·completion ('last skill' vs 'log truncation').

### Aggregation engine

- `bin/observe-report.js` — A dependency-free deterministic aggregator and the output engine of `/observe-report`. Using a tolerant reader, it reads the traces and outputs a summary of invocations·completion·unused assets·missed-activation candidates·session boundaries as JSON (`--json`) or Korean text. Not making LLM judgments (confirming missed activation, diagnosing descriptions) is this file's contract. The inventory denominator is determined in the order `--plugins-dir` > the trace's `session_start.plugin_root` > back-derivation from the file's own location.
- `bin/observe-export.js` — A deterministic renderer that turns the aggregate JSON (stdin) into a wiki-ingestable markdown snapshot (stdout). It refuses input carrying raw-text fields (candidates/followups/why etc.) with exit 2 (fail-closed), drops absolute paths, and renders asset names as `[[wikilinks]]` (entity upsert + crossref). Being stdout-only it does not breach the proposals-only contract — materialization and ingest are the consumer's (`wiki-ops:wiki-harness-feed`) responsibility.

## Setup

Trace collection is opt-in — you must turn on `OBSERVE_TRACE=1` for the six hooks to operate. The settings file differs depending on whether it is **global** (all projects) or **per-project**, and settings always apply **starting from the next newly started session** (they are not retroactive to an already-open session). A shell-profile `export OBSERVE_TRACE=1` also works, but the `settings.json` approach below is recommended because its session scope is clearer.

### 1. Global — trace across all projects

Put it in the `env` block of `~/.claude/settings.json`. Every session started thereafter inherits it.

```json
{
  "env": {
    "OBSERVE_TRACE": "1"
  }
}
```

### 2. Per-project — only in this repo

Put the same key in the `env` of `<project>/.claude/settings.local.json` (personal, `.gitignore`d) or `.claude/settings.json` (team-shared, committed). **Since local beats global**, if you turn it on globally and then want to turn it off for only a specific sensitive project, override it with `"OBSERVE_TRACE": "0"` in that project.

### 3. Together with the built-in OTel stack — recommended (cross-validation)

observe is an orthogonal complement in charge of "**why**·completion," while Claude Code's built-in OTel is in charge of "cost·token·event·**what and when**." Turning both on lets them join directly since `session_id`·`prompt_id` have identical values, so you can cross-validate whether hooks activated (→ this repo's `infra/otel` provides a local receiving stack `docker-compose` and a Grafana dashboard). Configure them together in the global `env`:

```json
{
  "env": {
    "OBSERVE_TRACE": "1",
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317",
    "OTEL_LOG_TOOL_DETAILS": "1",
    "OTEL_LOG_USER_PROMPTS": "1"
  }
}
```

- `OTEL_LOG_TOOL_DETAILS` unmasks third-party (marketplace) skill names — without it, `skill_name` is stamped only as `custom_skill`, making per-harness aggregation impossible (empirically measured 2026-07).
- `OTEL_LOG_USER_PROMPTS` transmits the prompt original to populate the dashboard's prompt↔skill correlation view — without it, `<REDACTED>`.
- The session works normally even if the stack is down (OTLP export failures are silently ignored). `CLAUDE_CODE_ENABLE_TELEMETRY` alone does not turn on the observe hooks, so keep `OBSERVE_TRACE` separate — the two are orthogonal.

> ⚠️ **Privacy**: `OBSERVE_TRACE`·`OTEL_LOG_USER_PROMPTS` record the prompt **original**. Turning it on globally leaves every prompt, including those of sensitive projects, in the local store (`.claude/skill-trace.jsonl` + local Loki) — since it is local loopback there is no leakage off the machine, but recording originals is an explicit decision. To exclude only a specific project, turn it off with `"0"` in the `env` of that project's `.claude/settings.local.json`.

## Usage

Once setup is complete, simply proceeding with a session as usual causes the six hooks to automatically append records to `.claude/skill-trace.jsonl` (no separate invocation needed). Once traces have accumulated over a period, run the report.

```
/observe-report                    # full flow through aggregation → interpretation → improvement proposal
/observe-report --raw --window 14  # last 14 days deterministic aggregation JSON only (for external-tool integration)
/observe-report --focus skills     # centered on missed-activation judgment·user-only skill diagnosis
```

If the trace is empty (`OBSERVE_TRACE` unset), the report prints the activation method and re-collection guidance and exits. If the sample is small (sessions < 5), the interpretation is tagged with a "insufficient sample — for trend reference only" warning to prevent over-generalization. The proposal includes the target file path·current description·revision draft·cited basis turns, but **applying it is a separate task after user approval**.

## Dependencies

- `requires`: `base` — operates on top of the base plugin.
- Plugins good to use together: proposals produced by `/observe-report` route dead assets to `workflow:deprecation-guide` (deprecation procedure), new-skill/hook candidates to `harness:create-flow` (scaffolding), and a-priori activation-rate validation of description revision drafts to `skill-creator` eval. It is also a data-driven complement to `workflow:retro`, which handles session-anecdote-based lessons.

## Notes

- **opt-in premise**: All hooks operate only when `OBSERVE_TRACE=1`. This command/hook does not auto-activate `OBSERVE_TRACE` — the decision to record prompt originals is up to the user.
- **Privacy·storage**: Traces accumulate in the project root's `.claude/skill-trace.jsonl`, and on first record they idempotently add `.claude/skill-trace.jsonl*` to `.gitignore` to block commits. On exceeding 10MB it rotates one generation to `.1`. The invocation-result body is not recorded due to size·sensitive-information concerns, leaving only `response_bytes`.
- **Orthogonal boundary**: Cost/token/tool_decision instrumentation is delegated to built-in OTel (`CLAUDE_CODE_ENABLE_TELEMETRY`), and a-priori activation-rate benchmarking (trigger/non-trigger query eval) is delegated to `skill-creator` eval — this plugin does not reimplement these.
- **Instrumentation boundary (empirically confirmed, 2026-07)**: A headless (`claude -p "/command"`) user-slash command does not go through the Skill tool, so no `skill` record is left — in this case the `is_command` flag of the `prompt` record is the invocation basis (in an interactive session a user-slash has the model invoke the Skill tool, so it is tracked normally). The built-in OTel's `skill_activated` event (`invocation_trigger: user-slash|claude-proactive`) catches both paths, so matching it by `prompt_id` against the local OTel stack (`infra/otel`) lets you cross-validate whether hooks activated.
- **Proposal-only**: `/observe-report` does not modify any file — SKILL.md·command·hook, etc. It does not directly fix even hook-logic bugs, only leaving a flag (no-unauthorized-modification principle).
