---
name: sync-claude-md
description: |
  커밋·푸시·PR/MR 직전에 이번 변경이 프로젝트 CLAUDE.md 를 낡게 만드는지 검토하고, 필요할 때만 갱신 diff 를 제안한다 — 아키텍처·디렉터리 구조, 새 통합/MCP, 컨벤션, 빌드·CI·도구, 주요 의존성 변화가 대상. 해당 없으면 한 줄로 끝낸다.
  Reviews whether pending changes make the project CLAUDE.md stale (architecture, integrations, conventions, build/CI/tooling, major dependencies) and proposes a minimal update diff only when needed.
  Use when: "CLAUDE.md 갱신 필요해?", "CLAUDE.md 동기화", 커밋/푸시/MR 전에 구조·도구가 바뀐 변경을 정리할 때, sync CLAUDE.md, check CLAUDE.md before commit or PR.
---

# Sync CLAUDE.md — 변경 기반 CLAUDE.md 유지보수

## Overview

Before a commit/push or PR/MR, check whether the pending change makes the project CLAUDE.md
stale, and if so propose a minimal update. Creation and stack facts of a project's CLAUDE.md
belong to `workflow:project-rules`; this skill **maintains** it afterwards.

The workflow plugin ships a non-blocking `PreToolUse(Bash)` hook that adds a one-line reminder
to context on the session's first `git commit`/`git push` (kill switch `CLAUDE_MD_SYNC_REMIND=0`).
The reminder arrives with the command's result, so a needed update usually goes into a follow-up
commit (or `--amend` if the user prefers and the commit is not pushed).

## 1. When it helps

| Situation | Suggested depth |
|-----------|-----------------|
| Explicit request ("CLAUDE.md sync", "CLAUDE.md 갱신 필요해?") | Phase 1~5, always report the verdict |
| About to commit/push/open an MR, and the change touched structure/tooling/conventions | Phase 1~3; if no update needed, one line at most |
| Reminder from the hook after the first commit/push | Phase 1~3 on the just-committed range (`git diff HEAD~1`) |

Skip it for changes that clearly stay within existing patterns (bug fix, feature in an existing
layout, tests, docs) — the check should cost nothing when nothing changed.

## 2. Behavioral Flow

### Phase 1: Locate CLAUDE.md
1. Look for `CLAUDE.md` > `claude/CLAUDE.md` > `.claude/CLAUDE.md` at the project root.
2. If none exists: say so and point to `workflow:project-rules` (creation is not this skill's job).
3. Read it and note the existing sections, plus any `<!-- project-rules:start -->…<!-- project-rules:end -->`
   block — that block is owned by `workflow:project-rules`; suggest `/project-rules --check` instead of editing it.
4. `git diff --cached -- '**/CLAUDE.md'` — mention if CLAUDE.md is already staged.

### Phase 2: Collect the change scope

| Condition | Target |
|-----------|--------|
| Staged changes exist | `git diff --cached` |
| PR/MR context | `git diff <default-branch>...HEAD` (detect default branch, do not assume `main`) |
| Just committed (hook reminder) | `git diff HEAD~1` |
| Fallback | `git diff HEAD` |

Use `--name-only` and `--stat` first; read the full diff only for files that look structural.

### Phase 3: Classify

**Update likely needed:**

| Category | Signals |
|---|---|
| Architecture | new top-level/module directories, changed module boundaries, new layers |
| Integration/MCP | `.mcp.json`/`mcp/` changes, new external service clients |
| Conventions | linter/formatter config, new shared base classes or utilities that others must use |
| Build/tooling/env | Dockerfile, compose, CI config (`.gitlab-ci.yml`, `.github/workflows/`), Makefile/justfile, new verify commands |
| Major dependency | new framework/library (not version bumps) in build.gradle(.kts), go.mod, pyproject.toml, package.json |
| Claude assets | new `skills/`, `commands/`, `agents/`, `.claude/` config |

**Usually not needed:** bug fixes, features inside existing patterns, tests, docs, renames.

A version bump of the JDK/Kotlin/Go/Spring/Next toolchain is a stack fact — route it to
`workflow:project-rules --check` rather than editing the managed block here.

### Phase 4: Propose
- No update needed → manual invocation: report briefly; reminder/commit context: one line or nothing.
- Update needed → show the target section(s) and a minimal diff (add/modify/remove lines).
  Prefer removing stale lines over adding new ones; keep the file under ~200 lines
  (official guidance: longer files consume more context and reduce adherence).
  Content that matters only for part of the codebase belongs in a path-scoped `.claude/rules/` file.

### Phase 5: Apply (after the user agrees)
1. Edit CLAUDE.md.
2. Stage it with the change if a commit is about to happen; otherwise leave it for a follow-up commit.
3. Summarize in 1–2 lines: "CLAUDE.md 갱신: {sections}".

## 3. Section mapping

| Category | CLAUDE.md section |
|---|---|
| Architecture | Architecture / Structure |
| Integration/MCP | Integrations / MCP |
| Conventions | Conventions / Coding Standards |
| Build/tooling/env | Commands / Development Setup |
| Major dependency | Tech Stack |
| Claude assets | Skills / Commands |

## 4. Examples

### Commit with a structural change
```
User: "커밋 푸시 해줘"
[Phase 2] git diff --cached → docker-compose.yml added, .gitlab-ci.yml modified
[Phase 3] Build/tooling change → update likely needed
[Phase 4] Proposed diff: Commands section +2 lines (docker compose up, CI stage name)
User agrees → [Phase 5] CLAUDE.md staged with the commit
```

### Commit within existing patterns
```
User: "커밋해줘"
[Phase 2] src/.../OrderService.kt 1 file, 3 lines
[Phase 3] Bug fix → no update; continue with the commit (no extra output)
```

### Manual check
```
User: "CLAUDE.md 갱신 필요해?"
→ "필요 없음 — 변경 유형: 버그 수정, 1 file, 기존 구조 내"
```

## 5. Boundaries

**Will:**
- Review pending changes and propose minimal CLAUDE.md diffs; apply after agreement
- Stay quiet when nothing structural changed

**Will Not:**
- Modify `~/.claude/CLAUDE.md` (global) — project-level only
- Create CLAUDE.md from scratch or rewrite the `project-rules` managed block (→ `workflow:project-rules`)
- Run `git commit`/`git push` itself or modify files other than CLAUDE.md

## 6. Related

| Component | Relationship |
|-----------|-------------|
| `workflow:project-rules` | Creates CLAUDE.md stack facts and `.claude/rules/`; `--check` audits version drift |
| `workflow:retro` (`/retro`) | Routes convention-change lessons here |
| `hooks/remind-claude-md-sync.js` | Non-blocking first-commit reminder (`CLAUDE_MD_SYNC_REMIND=0` to disable) |
