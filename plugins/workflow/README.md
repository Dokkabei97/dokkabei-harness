> **English** · [한국어](README_KO.md)

# workflow

> A workflow plugin that automates the entire development lifecycle (planning → spec → review → post-merge processing → retrospective) with commands, skills, and hooks.

## Overview

`workflow` is not a plugin that writes code itself; it automates the development process surrounding the code.
It bundles into a single plugin everything from upfront stages such as idea refinement and spec gating, to MR code review, session handoff, release notes,
post-merge issue closing and documentation refresh, and even the retrospective that turns lessons learned in a session into assets.
Skills that integrate with external tools/wikis such as GitLab (`glab`), Plane, and Outline are an opt-in setup that only works when the corresponding tool is present,
while planning, spec, shipping, and deprecation guides activate as pure methodology with no external dependency.
`project-rules` is the entry point that detects the project's stack (build-file versions, tools, git host) and proposes a stack-facts + specialist-core block in the project-root AGENTS.md
(read by Claude Code, Codex and Antigravity alike; CLAUDE.md links it with `@AGENTS.md`) plus Claude-only path-scoped specialist rules under `.claude/rules/` (only the stack-plugin items that match the detected versions).
User-run integrations and generators carry `disable-model-invocation: true`, so they run only from the slash menu.

## Components

### Commands (all user-invoked only)

- `/handoff` — Saves the session context (goals, attempts, next steps + git status) to `HANDOFF.md` so the next session can pick it up. Use when nearing the context limit or ending a session.
- `/release-notes` — Collects MRs merged since the previous release tag via `glab`, classifies the change types by conventional commit / MR titles to produce a Korean changelog and release notes draft, and proposes the next semver version along with the tag/Release creation commands (remote application only after approval).
- `/review-mr` — Analyzes a GitLab MR diff to detect bugs, security vulnerabilities, and logic errors, and writes review comments on the MR. It excludes or downgrades low findings based on confidence.

### Skills

- `project-rules` — Detects the project stack (JDK/Kotlin/Spring Boot, go.mod, pyproject, next, ES client and mappings, migration tool, ORM or not, git host) and proposes, as diffs: a marker block (`<!-- project-rules:start/end -->`, stack facts ≤30 lines + always-on specialist core ≤15 lines, ≤6,000 bytes) in the project-root `AGENTS.md`, which Codex and Antigravity read directly; an `@AGENTS.md` line in an existing `CLAUDE.md` (Claude Code reads AGENTS.md on its own only when there is no CLAUDE.md); and Claude-only `.claude/rules/<stack>-specialist.md` (`paths`-scoped, ≤15 items selected by ID for the detected versions), with an optional Antigravity glob-rule mirror. It also prints per-runtime commands to enable stack plugins for this project (Claude `--scope local`, Codex project `.codex/config.toml`, Antigravity `agy plugin install` / `.agents/plugins/`). Output from the earlier layout (block in CLAUDE.md, `.claude/rules/specialist-core.md`) gets a migration proposal. `--check` reports block placement, a missing `@AGENTS.md` link, version drift, missing tools, vanished IDs, and size limits (AGENTS.md ≤24,000 bytes for Antigravity, ≤32 KiB along the path for Codex, CLAUDE.md+imports ≤200 lines). Every write needs approval.
- `retro` (`/retro`) — Extracts this session's corrections, mistakes, and discoveries and routes them by type: convention changes to `sync-claude-md`, recurring mistakes to `tasks/lessons.md` (with guard-hook candidate tags), domain knowledge as skill-edit proposals. Criteria live in `references/compound-criteria.md` (the former `retro-compound` skill, merged 2026-10). Every application needs approval.
- `spec-driven-dev` — A gated workflow that finalizes the spec before writing code (SPECIFY → PLAN → TASKS → IMPLEMENT) to prevent scope drift and rework.
- `planning-guide` — Converts vague ideas into concrete plans and implementable tasks (idea refinement, dependency mapping, vertical slicing, task sizing).
- `shipping-guide` — Pre/post production deployment verification (pre-launch checklist, feature flags, staged rollout, rollback, post-launch monitoring).
- `deprecation-guide` — A systematic process for deprecating systems/modules/APIs and migrating consumers (deprecation decision framework, Strangler/Adapter/Feature Flag, safe removal).
- `issue-tracker` (user-invoked only) — Plane issue integration based on `plane-cli`. Auto-detects issues from branch names, tracks status, records change history, and proposes subtask splitting.
- `document-latest` (user-invoked only) — Refreshes Outline wiki documents after a code change is complete. Auto-classifies document type, decides new vs. update, writes in Korean, and auto-masks sensitive information.
- `post-merge` (user-invoked only) — An orchestrator that, after an MR merge, runs `issue-tracker` and `document-latest` in tandem to batch-process Plane issue closing and Outline document updates.
- `sync-claude-md` — Analyzes code changes before commit/PR to determine whether `CLAUDE.md` needs updating, and if there are architecture, integration, convention, or environment changes, proposes a minimal diff and applies it after approval. It leaves the `project-rules` block alone.
- `doc-collab-guide` — A thin protocol for co-authoring long-form documents such as plans, proposals, and reports with the user. It defines only the official `doc-coauthoring` skill installation guidance and the outline approval gate, delegating the authoring techniques themselves to the official skill.

### Hooks

- `PreToolUse(Bash)` → `hooks/remind-claude-md-sync.js` — A non-blocking nudge: on the session's first `git commit`/`git push` it adds one line suggesting a `sync-claude-md` review via `additionalContext` (exit 0, no permission decision). The line arrives with the command's result, so a needed update goes into a follow-up commit. It does not fire in projects without a CLAUDE.md. Kill switch: `CLAUDE_MD_SYNC_REMIND=0`.

## Usage

- Project start: run "set up this project" / `/project-rules` (Codex `$workflow:project-rules`, Antigravity `/workflow:project-rules`) for stack facts and specialist rules; after bumping versions, run it with `--check` for drift.
- Upfront stage: For a new feature, gate the spec with `spec-driven-dev`, and for vague requirements decompose down to tasks with `planning-guide` before starting.
- During development: When an MR is opened, review it with `/review-mr [number|URL]` (auto-detects the current branch if no argument is given). On the first commit/push the hook suggests a `sync-claude-md` review in one line.
- Session management: When the context grows long or you hand off work, record the session summary and git status into `HANDOFF.md` with `/handoff` — explicit invocation only; nothing is written automatically.
- Post-merge: Batch-process Plane issue closing + Outline document updates with `post-merge`, and at release close, organize the changelog and next version with `/release-notes`.
- Wrap-up: At the end of work/review/loop, extract session lessons with `/retro` and route them to lessons.md, CLAUDE.md, and skills (approval before every application).

## Dependencies

- There is no separate plugin `requires`. However, some components only work fully when an external tool/plugin is present.
  - `/review-mr`, `/release-notes` — Require the GitLab CLI `glab`.
  - `issue-tracker` — Requires `plane-cli` (Plane). `document-latest` — Requires Outline MCP. `post-merge` — Requires both (Plane + Outline).
  - `retro` — Guard-hook scaffolding is delegated to `harness:create-flow`.
  - `project-rules` — Reads specialist items from installed stack plugins' references (`kotlin-spring`, `go-mux`, `python-fastapi`, `nextjs`, `search`, `backend-shared`, `test`); depends on the item format `### <PREFIX>-<AREA>-<NN> · title` plus an `- 적용:` line. `scripts/specialist-index.sh auto` finds them next to the running workflow install (repo, Claude/Codex cache, Antigravity) and falls back to the other runtimes' install paths.
  - `doc-collab-guide` — Presupposes installation of the official `doc-coauthoring` skill (anthropics/skills).

## Notes

- Operations that affect the remote (tag/GitLab Release creation, CLAUDE.md/document updates, lessons/skill reflection) are always executed only after user approval.
- `sync-claude-md` is not enforced — the hook only suggests it; ignore the line when nothing structural changed.
- External-integration skills (`glab`/Plane/Outline) are an opt-in setup that does not activate without the corresponding tool/authentication.
