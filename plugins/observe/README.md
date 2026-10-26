> **English** · [한국어](README_KO.md)

# observe

> Measures how the harness is really used (which skills and agents fire, why, and how each turn ends) and turns those measurements into improvement proposals. Proposals only: it never edits a file.

## Overview

`observe` records, per repository, which skill or agent each prompt invoked, why it was invoked, and how the turn ended: `committed`, `cancelled`, `corrected` (correction candidate), `failed` or `unknown`. Hooks and transcript readers write everything to `<repo>/.tracer/`. `/observe-report` then runs a deterministic aggregation, has the LLM interpret it, and produces proposals: missed activations, description-tuning drafts, stale or dead assets, orchestration candidates and instrumentation gaps. It produces only proposals and never edits a file. Its sole write is appending events with no raw text to its own `.tracer/recommendations.jsonl`. You answer each proposal (accept, reject or snooze), and those answers become the feedback that tunes later reports.

Where Nous Research's Hermes Agent grows by **creating** skills from experience, observe takes the evaluation-first path. It checks whether an **already-built** harness fires as designed and whether its turns lead to results, then proposes fixes. It ports the deterministic half of Hermes's curator: the usage lifecycle (stale ≥30 days, archive candidate ≥90 days) and correction signals.

Claude Code's `/usage` shows usage by skill, subagent and MCP at one point in time. observe adds the reason each one fired, how its turn ended, the activations that were missed and the correction signals, and it keeps the trace so results build up across sessions.

Recording is **opt-in** (`OBSERVE_TRACE=1`) because prompt text is stored locally. With it unset, every hook exits immediately.

## Components

### Commands

| Command | What it does |
|---|---|
| `/observe-report` | Harness health report: aggregation → interpretation → proposals → asks for your answer to each recommendation ID. Options: `--raw` (aggregation JSON only), `--window <days>`, `--focus skills\|agents\|prompts`, `--stale-days`/`--archive-days`, `--followups <n>`, `--all` (sum over every registered repo, raw text excluded), `--theta`/`--margin`/`--min-sample`/`--orch-min` (experiments, not recorded), `--no-record`. |
| `/observe-git-hooks` | Opt-in commit-boundary git hooks: `install [--no-pre-commit] [--trailer]`, `uninstall`, `status`, `print <hook>`. |

### Claude Code hooks (`hooks/hooks.json`)

The hooks print nothing to stdout (no context pollution) and always `exit 0`, so a tracing failure never blocks work. They do nothing unless `OBSERVE_TRACE` is on, and they return immediately when `OBSERVE_CHILD=1`, which observe sets on its own child processes.

| Event (matcher) | Script (`bin/hooks/adapters/claude/`) | Records |
|---|---|---|
| `SessionStart` | `trace-session.js` | `session_start` (source, plugin install root, the denominator of the unused-asset list). It also catches up on earlier sessions that were never closed. |
| `UserPromptSubmit` | `trace-prompt.js` | `prompt` (metadata in events; the text goes to `raw/`) |
| `PreToolUse` (`Skill`) | `trace-skill.js` | `skill_use`: name, trigger (user/model), the turn preamble as `why`, `tool_use_id` |
| `PreToolUse` (`Agent\|Task`) | `trace-agent.js` | `subagent`: type, why, description and prompt head (in `raw/`) |
| `PostToolUse` (`Skill\|Agent\|Task`) | `trace-result.js` | `tool_result`: `response_bytes` and elapsed time. A Skill result is stamped when the skill body is **loaded**, so the report calls it `loaded`, not completion. |
| `PostToolUse`/`PostToolUseFailure` (`*`, async) | `trace-tool.js` | `tool_call` counters, only with `OBSERVE_TRACE_SCOPE=tools` (otherwise it exits before reading stdin). Under Codex it also detects skills and `spawn_agent` (see Runtimes). Plugin hooks cannot be registered conditionally on an env var, so a node process (about 20–30 ms, async, non-blocking) still starts on every tool call. |
| `Stop` | `trace-stop.js` | **Turn digest** (`turn_summary`), read incrementally from the transcript cursor. It only records: it never blocks and never emits a decision or context, and it exits at once on `stop_hook_active`. |
| `SessionEnd` | `trace-session.js` | `session_end`, then a detached worker closes the session (last turn plus `session_summary`). |

Matchers are tool-name regexes only (an expression matcher never fires, measured 2026-07). Any finer filtering happens inside the scripts.

### CLIs (`bin/`)

| CLI | Purpose |
|---|---|
| `observe-report.js` | Deterministic aggregator behind `/observe-report` (`--json` or Korean text). It does not make LLM judgments. It also records the feedback answers (see Feedback loop). |
| `observe-backfill.js` | Digests past Claude Code, Codex and Antigravity sessions whose working directory belongs to this repo: `[--root] [--runtime claude\|codex\|antigravity\|all] [--claude-dir <dir>]… [--codex-dir <dir>]… [--antigravity-dir <dir>] [--dry-run] [--json]`. It is idempotent. |
| `observe-migrate.js` | One-shot 1.x → 2.0 move of `.claude/skill-trace.jsonl(.1)` into `.tracer/`: `[--root] [--dry-run]`. The old files are renamed to `*.migrated`, never deleted. |
| `observe-git-hooks.js` | Installer behind `/observe-git-hooks`. |
| `observe-export.js` | Turns the aggregate JSON (stdin) into a wiki snapshot (stdout) for `wiki-ops:wiki-harness-feed`. If the input contains any raw-text field it fails closed with `exit 2`. |

### How it works

- **Turn digest** (`adapters/claude/transcript.js`, `_lib/digest.js`). Turns are split by `promptId`. Each `turn_summary` holds the tool flow `seq_compact` (e.g. `S1>B(other)2>B(git)2`), counts, failures, interrupts and rejections, exec kinds, edited files (repo-relative, ≤20), skills, subagents, commits and pushes, tokens (deduplicated by message id), model, effort and duration. `outcome` is picked in priority order:
  1. `committed`: the turn has a commit SHA.
  2. `cancelled`: a `[Request interrupted by user…]` marker, or a tool rejection with no progress after it.
  3. `corrected`: a plain prompt follows a skill or agent turn. This is only a candidate; the LLM phase decides.
  4. `failed`: at least half of the tool results failed.
  5. `unknown`: none of the above.

  System-injected turns (task notifications, `!` bash mode) are tagged `prompt_kind` and kept out of outcome counts. Each turn is settled one turn late (at the next Stop, SessionEnd or catch-up), and writes are upsert-skip on `(runtime, session, turn)`, so nothing is written twice.
- **Commit SHAs.** The digest takes them from `gitOperation.commit`, then from a stdout `[branch sha]` line, then from `git log --all --reflog` over the run window of a successful `git commit`. The `git-log`/`git-log-weak` paths are heuristics and are labelled as such.
- **Recommendation engine** (`bin/lib/match.js`, `recommend.js`). BM25 ranks each prompt against skill and command descriptions. Korean is matched as character bigrams and English as words. Quoted phrases weigh most, then `triggers:`, then "Use when", then prose. The engine produces three types:
  - `missed`: a settled turn that used no skill but has top1 ≥ θ (10) and margin ≥ 3, or a gold label (the next human turn invoked that slash command).
  - `tune`: prompt terms that the description lacks.
  - `orchestrate`: chains or tool flows that repeat across ≥3 sessions.

  Noise limits: nothing below 20 human prompts, evidence counted once per session, one-offs dropped, at most 3 per type. IDs are `sha1(type|target)` and are appended to `.tracer/recommendations.jsonl` (append-only, no raw text).
- **Feedback loop.** `/observe-report` ends by asking for your answer to each recommendation ID and records only those answers with `observe-report.js --accept|--reject|--snooze <id>[,<id>…]` (`--snooze-days <n>`, a positive integer; a reshown item is passed as `<id>@<evidence_n>` so an answer to it always opens a new round, even from a run that did not record). An unknown ID or conflicting answers write nothing and exit 1. The state is one of `proposed`, `accepted`, `rejected` (30-day cooldown, reshown early only if the evidence doubles), `snoozed` (default 7 days) or `expired` (no answer for 30 days, derived rather than written). Only your explicit answers are written. The report head shows per-type `precision = accepted / (accepted + rejected)` once there are at least 10 answers; below that it shows `표본 부족` (insufficient sample). θ, the margin, the expiry and the minimum denominator are manual constants; nothing is auto-calibrated.
- **Compatibility reader** (`bin/lib/reader.js`). It reads `.tracer/` v1 and the legacy `.claude/skill-trace.jsonl(.1)` v0 as one stream. The legacy fallback stays for the whole 2.x major.

## Setup

Settings apply from the **next new session**; a session that is already open does not pick them up.

### 1. Claude Code

Global (all projects), in `~/.claude/settings.json`:

```json
{ "env": { "OBSERVE_TRACE": "1" } }
```

Per project: put the same key in `<project>/.claude/settings.local.json` (personal) or `.claude/settings.json` (shared). The project setting beats the global one, so `"OBSERVE_TRACE": "0"` turns recording off for one sensitive repo. A shell `export OBSERVE_TRACE=1` also works.

| Variable | Effect |
|---|---|
| `OBSERVE_TRACE=1` | Turns recording on (`1`, `true`, `on` and `yes` are accepted). |
| `OBSERVE_TRACE_SCOPE=tools` | Also writes per-tool `tool_call` counters. |
| `OBSERVE_LLM=1` | Lets the git post-commit worker add an LLM section to `commits/<sha>.md`. |
| `OBSERVE_LLM_DAILY=<n>` | Daily cap on those LLM calls (default 5). |
| `OBSERVE_CHILD=1` | Set by observe on its own children. Every hook exits immediately. |

### 2. Codex (optional)

Codex loads the same `hooks/hooks.json` (Claude-format plugin hooks). To set it up:

1. Install the plugin in Codex.
2. Trust its hooks with `/hooks`. Trust is tied to the hook hash, so trust them again after every update.
3. Start Codex with `OBSERVE_TRACE=1` in the environment, e.g. `OBSERVE_TRACE=1 codex`.

Codex runs `async` hooks synchronously, so once the hooks are trusted, the `*` PostToolUse hook adds one node start (about 20–30 ms) to every Codex tool call, even with `OBSERVE_TRACE` unset. To remove that cost, disable or untrust the hook in `/hooks`.

### 3. Antigravity and past Claude Code / Codex sessions (backfill)

Antigravity has no hooks. Its transcripts (`~/.gemini/antigravity-cli/brain/`), Codex rollouts (`~/.codex/sessions`, `~/.codex/archived_sessions`) and this repo's past Claude Code transcripts (`~/.claude/projects/<encoded repo path>/*.jsonl`, written before the hooks were on) are read by:

```sh
node <observe>/bin/observe-backfill.js            # this repo's sessions only; rerun freely
node <observe>/bin/observe-backfill.js --dry-run  # count only
```

A session is closed only after its file has been idle for more than 30 minutes; for a session still running, the last human turn is held back. Codex Desktop imports of external sessions (`external-import-turn-N` turns, or the `<EXTERNAL SESSION IMPORTED>` marker) are skipped, with one stderr line each, so the same work is not counted twice. `.jsonl.zst` rollouts need the `zstd` CLI; without it they are skipped and reported. Run the backfill before `/observe-report`.

### 4. Git hooks (optional, per repo)

```
/observe-git-hooks install        # post-commit + non-blocking pre-commit
/observe-git-hooks install --trailer   # also add an Agent-Session trailer (off by default)
/observe-git-hooks status | uninstall
```

- **post-commit** passes HEAD to a detached analyzer and returns at once. The analyzer appends a `commit` event (`events/git-hook/<YYYY-MM>.jsonl`) and writes `.tracer/commits/<sha>.md`: subject, changed files, the attributed session and turn, that turn's tool flow and the open recommendations, with no raw text.
- **Attribution order**:
  1. A transcript SHA match.
  2. The `Agent-Session` trailer.
  3. `CLAUDE_CODE_SESSION_ID` in the hook environment.
  4. For a human commit: the turn that ended within the previous 2 hours and whose edited files overlap the commit most.
- **pre-commit** prints one deterministic line of open recommendations to stderr from a cache. It never uses an LLM and never blocks the commit.
- **Existing hooks** are moved to `observe-orig/<hook>` inside the hooks directory. They run first, and their exit code is returned unchanged. `uninstall` restores them byte for byte.
- With `core.hooksPath`, husky or lefthook present, nothing is installed. The command explains how to paste `print <hook>` output into that tool's hook instead.
- Measured cost (temp repo, 40 alternating pairs): `git commit` gets about 30 ms slower at p95.
- Human commits in a terminal are recorded only if that shell also has `OBSERVE_TRACE=1`, because `settings.json` `env` applies only inside Claude Code.
- The hooks embed the plugin's absolute path. After `/plugin update`, `status` reports them as stale; run `install` again.

### 5. Upgrading from 1.x

The legacy `.claude/skill-trace.jsonl` is still read as v0, so no history is lost. To move it into `.tracer/`, run `node <observe>/bin/observe-migrate.js` once.

## Usage

Work as usual; records accumulate in `<repo>/.tracer/`. Once some traces exist, run:

```
/observe-report                    # aggregation → interpretation → proposals → your answers
/observe-report --raw --window 14  # last 14 days, aggregation JSON only
/observe-report --focus skills     # missed-activation and user-only skill diagnosis
/observe-report --all              # every registered repo (no raw text, no per-turn judgments)
```

If the trace is empty, the report explains how to turn recording on and exits. With fewer than 5 sessions, the interpretation carries a small-sample warning. Each proposal names the target file, the current description, a draft revision and the evidence turns. Applying a proposal is a separate task that you approve.

## `.tracer/` layout

```text
<repo>/.tracer/
├── .gitignore                         # "*" — the whole folder stays out of git status
├── VERSION                            # schema version (1)
├── events/<runtime>/<YYYY-MM>/<session>.jsonl   # canonical events — no raw text
├── events/git-hook/<YYYY-MM>.jsonl    # commit events (git hooks)
├── raw/<YYYY-MM>/<session>.jsonl      # prompt text, why, args (redacted) — referenced by raw_ref/why_ref
├── digests/<YYYY-MM>/<session>.jsonl  # turn_summary / session_summary — no raw text
├── cursors/<runtime>/<session>.json   # incremental transcript offsets
├── recommendations.jsonl              # recommendation created/status events — append-only, no raw text
├── commits/<sha>.md                   # per-commit analysis (git hooks) — no raw text
└── index/                             # derived, safe to delete (precommit.txt, llm-budget.json)

~/.tracer/index/repos.d/<sha1(root)>   # one marker per repo (its path only) for --all
```

`<runtime>` is `claude-code`, `codex` or `antigravity`. The repo's own `.gitignore` is not touched. The report and migrate commands walk up from the cwd to the nearest `.tracer/` (stopping at the git toplevel), so running them from a subdirectory or a monorepo package finds the right store.

## Runtime support

| Runtime | How | Turn key | Skill detection | Notes |
|---|---|---|---|---|
| Claude Code | hooks + transcript digest | `promptId` | explicit (Skill tool) | Full support. |
| Codex | the same hooks + rollout digest (`adapters/codex/rollout.js`), plus backfill | `turn_id` | heuristic: a shell read of `…/skills/<name>/SKILL.md`, named `<plugin>:<skill>` | No Skill/Agent tools, so `trace-skill`/`trace-agent`/`trace-result` never fire. A `$skill` mention injected without a tool call is not seen. Approval denials are not modeled. Hooks have not yet been run in a live Codex session (checked against the 0.164 binary's hook schema). |
| Antigravity CLI | backfill only (`adapters/antigravity/transcript.js`) | `step:<USER_INPUT index>` | heuristic (same as Codex) | The source has no tokens, model or cancel marker. The repo root is the most frequent `run_command` Cwd. |

Heuristic skill use means a skill was opened, not necessarily used. Reads of a skill's own source inside the session repo, as when editing a plugin, are not counted.

## Privacy

- `OBSERVE_TRACE` stores prompt **text**. It lives only in the git-ignored `<repo>/.tracer/raw/`, after write-time redaction of AWS `AKIA…`, `ghp_…`/`github_pat_…`, `sk-…`, `xox[bp]-…`, JWTs, PRIVATE KEY blocks, e-mail addresses, IPv4 addresses and home paths (→ `~`). Regex redaction cannot catch names or internal jargon, which is why raw text is kept apart. Nothing expires automatically; delete `raw/` to drop it.
- Events, digests, recommendations and commit `.md` files hold names, counts, relative paths, SHAs and join keys, but no prompt, command or output text. Tool-result bodies are never stored, only `response_bytes`.
- The global layer `~/.tracer/` holds only repo path markers. A session whose root is the home directory is not recorded at all.
- Nothing is uploaded, with one exception: with `OBSERVE_LLM=1`, the git worker sends the deterministic commit `.md` (no raw text) to `claude -p` (no tools, capped daily). `observe-export.js` refuses any input that carries raw text.
- OTel (Claude Code's built-in telemetry) is not supported: observe neither reads nor exports it.

## Dependencies

- `requires`: none. observe is self-contained and bundles its own copy of `hook-stdin`. Node 22 built-ins only.
- Works well with: `workflow:deprecation-guide` (for dead assets), `harness:create-flow` (for new skill or hook candidates), `skill-creator` eval (for checking a description draft's activation rate before you adopt it), `workflow:retro` (anecdote-based lessons, complementary) and `wiki-ops:wiki-harness-feed` (wiki snapshots via `observe-export.js`).

## Notes

- **Out of scope**: cost dashboards and tool_decision instrumentation (the digest keeps only token totals), and benchmarking description activation rates in advance (use `skill-creator` eval).
- **Headless slash commands** (`claude -p "/command"`) do not go through the Skill tool, so for those the `prompt` record's `is_command` flag is the only evidence of the call.
- **Proposals only**: `/observe-report` never modifies a SKILL.md, command or hook, not even to fix a hook bug. Its only writes are appends to its own `.tracer/recommendations.jsonl`: `created` events and the status events for your answers.
- **Known gaps**: Codex hooks are unverified in a live session. Attributing a commit to a subagent works only through `CLAUDE_CODE_SESSION_ID`. Commits that never fire post-commit (e.g. `git merge`) appear only through the transcript digest. `corrected` stays a candidate until the LLM phase judges it.
