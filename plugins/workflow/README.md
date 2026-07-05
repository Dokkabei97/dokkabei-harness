> **English** · [한국어](README_KO.md)

# workflow

> A workflow plugin that automates the entire development lifecycle (planning → spec → review → post-merge processing → retrospective) with commands, skills, and hooks.

## Overview

`workflow` is not a plugin that writes code itself; it automates the development process surrounding the code.
It bundles into a single plugin everything from upfront stages such as idea refinement and spec gating, to MR code review, session handoff, release notes,
post-merge issue closing and documentation refresh, and even the retrospective that turns lessons learned in a session into assets.
Skills that integrate with external tools/wikis such as GitLab (`glab`), Plane, and Outline are an opt-in setup that only works when the corresponding tool is present,
while planning, spec, shipping, and deprecation guides activate as pure methodology with no external dependency.
The `/retro` retrospective router and the automatic session snapshot hook are designed to respect ownership boundaries with other sessions and other plugins (base, harness),
so in a session where a loop harness is running they step back on their own to avoid conflicts.

## Components

### Commands

- `/handoff` — Saves the session context (goals, attempts, next steps + git status) to `HANDOFF.md` so the next session can pick it up. Use when nearing the context limit or ending a session.
- `/release-notes` — Collects MRs merged since the previous release tag via `glab`, classifies the change types by conventional commit / MR titles to produce a Korean changelog and release notes draft, and proposes the next semver version along with the tag/Release creation commands (remote application only after approval).
- `/retro` — A retrospective compounding router that extracts this session's corrections, mistakes, and discoveries and routes them by type. Convention changes go to `sync-claude-md`, recurring mistakes to `tasks/lessons.md` (including guard-hook candidate tags), and domain knowledge is distributed as skill-edit proposals. Every application passes through a user approval gate.
- `/review-mr` — Analyzes a GitLab MR diff to detect bugs, security vulnerabilities, and logic errors, and writes review comments on the MR. Depending on the nature of the diff, it selectively dispatches the `analyze` plugin's specialist agents (arch-reviewer/perf-reviewer/sql-analyzer), and excludes or downgrades low findings based on confidence.

### Skills

- `spec-driven-dev` — A gated workflow that finalizes the spec before writing code (SPECIFY → PLAN → TASKS → IMPLEMENT) to prevent scope drift and rework.
- `planning-guide` — Converts vague ideas into concrete plans and implementable tasks (idea refinement, dependency mapping, vertical slicing, task sizing).
- `shipping-guide` — Pre/post production deployment verification (pre-launch checklist, feature flags, staged rollout, rollback, post-launch monitoring).
- `deprecation-guide` — A systematic process for deprecating systems/modules/APIs and migrating consumers (deprecation decision framework, Strangler/Adapter/Feature Flag, safe removal).
- `issue-tracker` — Plane issue integration based on `plane-cli`. Auto-detects issues from branch names, tracks status, records change history, and proposes subtask splitting.
- `document-latest` — Automatically refreshes Outline wiki documents after a code change is complete. Auto-classifies document type, decides new vs. update, writes in Korean, and auto-masks sensitive information.
- `post-merge` — An orchestrator that, after an MR merge, runs `issue-tracker` and `document-latest` in tandem to batch-process Plane issue closing and Outline document updates.
- `sync-claude-md` — Analyzes code changes before commit/PR to determine whether `CLAUDE.md` needs updating, and if there are architecture, integration, convention, or environment changes, proposes and executes the update. It activates silently and automatically on commit/push/PR/MR requests.
- `retro-compound` — The retrospective methodology that `/retro` follows. It filters lessons by reproducibility, generalizability, and judgeability criteria, distributes them according to a per-type routing table, and embeds duplicate/conflict checks and principles for preventing the accumulation of low-quality rules. CLAUDE.md reflection is delegated to `sync-claude-md`, and guard-hook scaffolding to `harness:create-flow`.
- `doc-collab-guide` — A thin protocol for co-authoring long-form documents such as plans, proposals, and reports with the user. It defines only the official `doc-coauthoring` skill installation guidance, the outline approval gate, and the workaround path for the base hook (`block-md-creation`) conflict, delegating the authoring techniques themselves to the official skill.

### Hooks

- `PreToolUse(Bash)` → `hooks/remind-claude-md-sync.js` — Blocks `git commit`/`git push` once per session with exit 2 to deterministically enforce the `sync-claude-md` review (whether CLAUDE.md needs updating). Retrying the same command after the review passes, and it does not fire in projects without a CLAUDE.md. Kill switch: `CLAUDE_MD_SYNC_REMIND=0`.
- `PreCompact` / `SessionEnd` → `hooks/session-snapshot.sh` — Just before compaction and at session end, deterministically records the git status (branch, changed files, recent commits) and the count of incomplete markers only into the `<!-- auto-snapshot -->` marker section of `HANDOFF.md`. It never touches manually written content outside the marker via any path, and always exits 0 even on failure so as not to disrupt the session. In a loop session where `.planning/loop-active` exists, it steps back immediately (the anchor is under mvp/floop's purview).

## Usage

- Upfront stage: For a new feature, gate the spec with `spec-driven-dev`, and for vague requirements decompose down to tasks with `planning-guide` before starting.
- During development: When an MR is opened, review it with `/review-mr [number|URL]` (auto-detects the current branch if no argument is given). At commit/PR time, `sync-claude-md` automatically checks whether CLAUDE.md needs updating.
- Session management: When the context grows long or you hand off work, leave a semantic summary with `/handoff`, while the mechanical git status is automatically preserved into `HANDOFF.md` by the snapshot hook (the two are complementary).
- Post-merge: Batch-process Plane issue closing + Outline document updates with `post-merge`, and at release close, organize the changelog and next version with `/release-notes`.
- Wrap-up: At the end of work/review/loop, extract session lessons with `/retro` and route them to lessons.md, CLAUDE.md, and skills (approval before every application).

## Dependencies

- There is no separate plugin `requires`. However, some components only work fully when an external tool/plugin is present.
  - `/review-mr`, `/release-notes` — Require the GitLab CLI `glab`. `/review-mr` selectively dispatches the `analyze` plugin's review agents (arch-reviewer/perf-reviewer/sql-analyzer).
  - `issue-tracker` — Requires `plane-cli` (Plane). `document-latest` — Requires Outline MCP. `post-merge` — Requires both (Plane + Outline).
  - `retro-compound` — Guard-hook scaffolding is delegated to `harness:create-flow`.
  - `doc-collab-guide` — Presupposes installation of the official `doc-coauthoring` skill (anthropics/skills).

## Notes

- The snapshot hook and `doc-collab-guide` are designed not to conflict with the `base` plugin's `block-md-creation` hook (direct shell writes are not tool calls, so they are not subject to blocking; document authoring uses the workaround path).
- Operations that affect the remote (tag/GitLab Release creation, CLAUDE.md/document updates, lessons/skill reflection) are always executed only after user approval.
- `sync-claude-md` activates silently and automatically in the commit/push/PR/MR flow, and if no update is needed it does nothing and moves on.
- External-integration skills (`glab`/Plane/Outline) are an opt-in setup that does not activate without the corresponding tool/authentication.
