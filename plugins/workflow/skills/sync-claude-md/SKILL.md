---
name: sync-claude-md
description: |
  TRIGGER FIRST — when the user requests commit, push, or PR/MR creation (direct prompt or any
  custom command), invoke this skill BEFORE running any git commit/push/PR action.
  Analyzes the pending code changes to determine whether CLAUDE.md needs to be updated —
  architecture changes, new integrations, new top-level directories/infra, convention changes,
  environment/tool changes, etc. — and proposes and executes CLAUDE.md updates when necessary.
  Auto-activates silently: updates CLAUDE.md if needed, skips silently if not.
metadata:
  version: 2.0.0
  category: workflow
  domain: project-context
triggers:
  - "CLAUDE.md sync"
  - "CLAUDE.md update check"
  - "sync claude md"
  - "update claude config"
auto_activate:
  patterns:
    - "커밋"
    - "commit"
    - "푸시"
    - "push"
    - "PR 생성"
    - "MR 생성"
    - "create PR"
    - "create MR"
    - "merge request"
    - "pull request"
  custom_commands:
    - "/commit"
    - "/review-pr"
    - "/review-mr"
    - "any command involving commit, push, or MR/PR creation"
  behavior: "auto-execute"
  silent_skip: true
---

# Sync CLAUDE.md - Automatic CLAUDE.md Synchronization Based on Code Changes

## Overview

Automatically analyzes whether work should be reflected in CLAUDE.md before commit/push or PR/MR, and performs updates when necessary.
If the `monorepo-init` skill is responsible for **creating** CLAUDE.md, this skill is responsible for **maintaining** CLAUDE.md after work is completed.

---

## 1. Activation Rules

| Trigger Type | Condition | Behavior |
|-------------|-----------|----------|
| **Manual** | Explicit invocation such as "CLAUDE.md sync", "sync claude md" | Execute full Phase 1~5, always report results |
| **Auto (prompt)** | User prompt contains commit/push/MR/PR keywords: "커밋해줘", "푸시해줘", "MR 만들어줘" 등 | Auto-execute Phase 1~3 → update if needed, **silent skip** if not |
| **Auto (command)** | Custom command triggers commit/push/MR flow: `/commit`, `/review-mr`, or any command that results in commit/push/MR creation | Auto-execute Phase 1~3 → update if needed, **silent skip** if not |

**Auto-activation detection keywords:**
- Commit: `커밋`, `commit`, `커밋해`, `커밋하고`
- Push: `푸시`, `push`, `푸시해`, `푸시하고`
- MR/PR: `MR`, `PR`, `merge request`, `pull request`, `MR 생성`, `PR 생성`, `MR 만들어`
- Combined: `커밋 푸시`, `커밋하고 푸시`, `commit and push`

**Execution timing:** CLAUDE.md analysis runs **before** the actual commit/push/MR command executes. If CLAUDE.md is updated, the changes are staged together with the existing changes.

---

## 2. Behavioral Flow

### Phase 1: CLAUDE.md Discovery and Loading

```
1. Search for CLAUDE.md location from the project root (Glob: **/CLAUDE.md)
   - Priority: CLAUDE.md > claude/CLAUDE.md > .claude/CLAUDE.md
2. If CLAUDE.md does not exist:
   → Output "CLAUDE.md does not exist. Please run monorepo-init or project initialization first." and stop
3. Read current CLAUDE.md content and identify existing section list
4. Check if CLAUDE.md already has staged changes:
   → git diff --cached -- "**/CLAUDE.md"
   → Notify user if changes are already staged
```

### Phase 2: Collecting Change Scope

Auto-detect mode:

| Condition | Analysis Target | Description |
|-----------|----------------|-------------|
| Staged changes exist | `git diff --cached` | Pre-commit scenario |
| User mentions "PR", "MR" | `git diff main...HEAD` | Pre-PR scenario |
| Fallback | `git diff HEAD` | All uncommitted changes |

Collected items:
```
1. git diff --name-only → List of changed files
2. git diff --stat → Change statistics (number of files, added/deleted lines)
3. git diff → Actual diff content (for change classification)
```

### Phase 3: Change Classification (Determining Update Necessity)

Analyzes the collected diff to determine whether CLAUDE.md update is necessary.

**Update Required (Yes):**

| Change Category | Detection Signals |
|---|---|
| Architecture change | New directory structure created, module boundary changes, layer additions |
| New integration/MCP | `mcp/` file changes, new external service clients, API integration additions |
| Convention/pattern change | Linter config changes, new coding standard files, new common utility/base classes |
| Environment/tool change | Dockerfile, docker-compose, CI/CD config, Makefile changes |
| Major dependency addition | New framework/library additions (excluding patch updates) |
| Workflow change | New git hooks, new scripts, new CI stages |
| Skill/command addition | New files in `skills/`, `commands/`, `claude/commands/` |

**No Update Required (No):**

| Change Category | Description |
|---|---|
| Simple bug fix | Minor changes to existing files, no new patterns |
| Feature addition within existing patterns | New feature files following existing structure |
| Test addition | Test files following existing test conventions |
| Documentation changes | README, docs, comment changes |
| Refactoring | Renames, moves within existing patterns |

**Detection Pattern Details:**

```
# Architecture change detection
- Were new directories created? (new path patterns in diff)
- Were new submodules added to core directories such as src/, lib/, packages/?

# New integration/MCP detection
- Were mcp/*.json files added/modified?
- Were new API client files added?

# Convention change detection
- Config file changes such as .eslintrc, .prettierrc, tsconfig.json, pyproject.toml
- New common pattern files such as base classes, mixins, decorators added

# Environment/tool change detection
- Dockerfile, docker-compose.yml added/modified
- .github/workflows/, .gitlab-ci.yml, Jenkinsfile changes
- Makefile, justfile, taskfile.yml changes

# Major dependency detection
- New dependency additions in package.json, requirements.txt, go.mod, build.gradle, etc.
  (Excluding version bumps only)

# Skill/command detection
- New skills/*/SKILL.md files
- New claude/commands/*.md files
- Config changes within .claude/ directory
```

### Phase 4: Decision and Execution

**When no update is required:**

```
→ Auto-activation: Silent skip. No output to user. Proceed with the original task (commit/push/MR).
→ Manual invocation: Report "No CLAUDE.md update needed" with brief analysis summary.
```

**When update is required:**

```
1. Identify which sections need to be added/modified
   - Match against existing CLAUDE.md section structure
   - Determine whether a new section is needed or updating an existing section is sufficient

2. Execute CLAUDE.md update immediately (proceed to Phase 5)
   - No user confirmation needed
   - Brief inline message: "CLAUDE.md 업데이트 중..." → then continue original task

3. Stage CLAUDE.md changes with git add
   → Include in the same commit/push/MR as the original changes
```

### Phase 5: Execute CLAUDE.md Update

```
1. Read current CLAUDE.md content (Read)
2. Apply changes:
   - Update existing sections: Modify section content (Edit)
   - Add new sections: Insert at appropriate location (Edit)
   - Remove obsolete content: Delete information that is no longer valid
3. Write CLAUDE.md file (Write/Edit)
4. Auto-stage: git add {CLAUDE.md path}
   → Include in the same commit as the original changes
5. Brief summary (1-2 lines):
   → "CLAUDE.md 업데이트: {변경 섹션} 반영 완료"
6. Continue with the original task (commit/push/MR) without pause
```

---

## 3. Update Section Mapping

Provides guidance on which sections of CLAUDE.md should be updated for each change category.

| Change Category | Target CLAUDE.md Section | Update Content |
|---|---|---|
| Architecture change | Architecture / Structure | Reflect new modules, directory structure |
| New integration/MCP | Integrations / MCP | Add new MCP servers, external integrations |
| Convention/pattern change | Conventions / Coding Standards | Document new rules, patterns |
| Environment/tool change | Development Setup / Commands | Add new tools, commands |
| Major dependency addition | Tech Stack / Dependencies | Record new libraries |
| Workflow change | Workflow / CI/CD | Document new workflow stages |
| Skill/command addition | Skills / Commands | Update skill, command listings |

---

## 4. Tool Coordination

| Tool | Purpose |
|------|---------|
| **Glob** | Search for `**/CLAUDE.md` file locations |
| **Read** | Read current CLAUDE.md content, analyze config files |
| **Bash** | Collect change scope with `git diff`, `git diff --cached`, `git diff main...HEAD`, etc. |
| **Grep** | Detect patterns in diff content (new imports, config files, MCP configs, etc.) |
| **Edit** | Modify existing CLAUDE.md sections |
| **Write** | Add new sections to CLAUDE.md (when needed) |

---

## 5. Examples

### Example 1: Auto-activate on commit (update needed)

```
User: "커밋 푸시 해줘"

[Auto-activate] commit/push 감지 → sync-claude-md 자동 실행
[Phase 1] CLAUDE.md discovery → ./CLAUDE.md found
[Phase 2] git diff --cached → skills/new-skill/SKILL.md added
[Phase 3] Classification: Skill/command addition → Update required
[Phase 4] Execute immediately
[Phase 5] CLAUDE.md 업데이트: Skills 섹션 반영 완료
          git add CLAUDE.md → 커밋에 포함
→ Continue: git commit + git push (original task)
```

### Example 2: Auto-activate on commit (no update needed — silent skip)

```
User: "커밋해줘"

[Auto-activate] commit 감지 → sync-claude-md 자동 실행
[Phase 1] CLAUDE.md discovery → ./CLAUDE.md found
[Phase 2] git diff --cached → src/utils/format.ts 1 file, 3 lines modified
[Phase 3] Classification: Simple bug fix → No update required
→ Silent skip. No output.
→ Continue: git commit (original task)
```

### Example 3: Auto-activate on MR creation

```
User: "MR 만들어줘"

[Auto-activate] MR 감지 → sync-claude-md 자동 실행
[Phase 1] CLAUDE.md discovery → ./CLAUDE.md found
[Phase 2] MR detected → git diff main...HEAD
          → 12 files changed, docker-compose.yml added, .github/workflows/ci.yml modified
[Phase 3] Classification: Environment/tool change + Workflow change → Update required
[Phase 4] Execute immediately
[Phase 5] CLAUDE.md 업데이트: Development Setup, CI/CD 섹션 반영 완료
          git add CLAUDE.md → 커밋에 포함
→ Continue: glab mr create (original task)
```

### Example 4: Auto-activate via custom command

```
User: "/commit" (custom command that triggers commit flow)

[Auto-activate] commit command 감지 → sync-claude-md 자동 실행
[Phase 1~3] Analysis → mcp/grafana.json added → Update required
[Phase 4~5] CLAUDE.md 업데이트: MCP 섹션에 Grafana 추가 완료
→ Continue: /commit command flow
```

### Example 5: Manual invocation (always reports)

```
User: "CLAUDE.md sync"

[Manual] Full Phase 1~5 execution
[Phase 3] Classification: Simple bug fix → No update required

Agent:
CLAUDE.md 업데이트가 필요하지 않습니다.
- 변경 유형: 버그 수정
- 변경 파일: 1개
- 영향 범위: 기존 아키텍처/규칙 내
```

---

## 6. Boundaries

**Will:**
- Auto-activate on commit/push/MR requests (prompt or custom command) without asking
- Silently skip when no CLAUDE.md update is needed (zero noise)
- Execute CLAUDE.md update and auto-stage changes for the same commit
- Report results only when update was performed (brief 1-2 line summary)

**Will Not:**
- Modify `~/.claude/CLAUDE.md` (global config) — only project-level targets
- Create CLAUDE.md from scratch when it does not exist (that is the monorepo-init role)
- Directly execute code modifications or git commit
- Modify project files other than CLAUDE.md

---

## 7. Related Skills

| Skill | Relationship |
|-------|-------------|
| `monorepo-init` | Initial CLAUDE.md creation → This skill handles subsequent maintenance |
| `agents-md-copy` | AGENTS.md synchronization after CLAUDE.md update |
| `issue-tracker` | Workflow skill that can operate alongside at commit/PR time |
