---
name: sync-claude-md
description: |
  Analyzes code changes before commit/PR to determine whether CLAUDE.md needs to be updated.
  Detects architecture changes, new integrations, convention changes, environment/tool changes, etc.,
  and proposes and executes CLAUDE.md updates when necessary.
metadata:
  version: 1.0.0
  category: workflow
  domain: project-context
triggers:
  - "CLAUDE.md sync"
  - "CLAUDE.md update check"
  - "sync claude md"
  - "update claude config"
auto_suggest:
  keywords:
    - "commit"
    - "commit"
    - "commit"
    - "push"
    - "create PR"
    - "create MR"
  action: "Shall I check whether CLAUDE.md needs to be updated?"
  phase: 3
---

# Sync CLAUDE.md - Automatic CLAUDE.md Synchronization Based on Code Changes

## Overview

Automatically analyzes whether work should be reflected in CLAUDE.md before commit/push or PR/MR, and performs updates when necessary.
If the `monorepo-init` skill is responsible for **creating** CLAUDE.md, this skill is responsible for **maintaining** CLAUDE.md after work is completed.

---

## 1. Activation Rules

| Trigger Type | Condition | Behavior |
|-------------|-----------|----------|
| **Manual** | Explicit invocation such as "CLAUDE.md sync", "sync claude md" | Execute full Phase 1~5 |
| **Auto-suggest** | Completion signal detected such as "commit", "push", "create PR" | Ask "Shall I check whether CLAUDE.md needs to be updated?" → Execute upon approval |

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

### Phase 4: Decision and Proposal

**When no update is required:**

```
No CLAUDE.md update is needed.

Analysis results:
- Change type: {bug fix / feature addition within existing patterns / test addition / ...}
- Changed files: {N}
- Impact scope: Within existing architecture/rules
```
→ Stop here

**When update is required:**

```
1. Identify which sections need to be added/modified
   - Match against existing CLAUDE.md section structure
   - Determine whether a new section is needed or updating an existing section is sufficient

2. Propose draft update content:
   - Provide rationale linked to changed files
   - Preview specific content to be added/modified

3. Share "Proceeding with CLAUDE.md update" with user
   → Proceed to Phase 5 without waiting for user response
```

### Phase 5: Execute CLAUDE.md Update

```
1. Read current CLAUDE.md content (Read)
2. Apply changes:
   - Update existing sections: Modify section content (Edit)
   - Add new sections: Insert at appropriate location (Edit)
   - Remove obsolete content: Delete information that is no longer valid
3. Write CLAUDE.md file (Write/Edit)
4. Provide agents-md-copy skill integration guidance:
   → "To also update AGENTS.md, run the agents-md-copy skill."
5. Display change diff summary:
   → Summarize added, modified, and deleted content
6. Suggest git add:
   → "Stage the changes with git add {CLAUDE.md path}."
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

### Example 1: Sync after adding an MCP server

```
User: "Sync CLAUDE.md"

[Phase 1] CLAUDE.md discovery → ./CLAUDE.md found, content loaded
[Phase 2] git diff --cached → mcp/grafana.json added
[Phase 3] Classification: New integration/MCP → Update required
[Phase 4] Proposal:
  - Add Grafana MCP server to "Integrations" or "MCP" section
  - Rationale: mcp/grafana.json new file

Agent: Adding Grafana MCP integration info to CLAUDE.md.
[Phase 5] Execute CLAUDE.md update → Display diff summary
```

### Example 2: Sync after adding a new skill

```
User: "I'm going to commit"
Agent: Shall I check whether CLAUDE.md needs to be updated?
User: "Yes"

[Phase 1] CLAUDE.md discovery → ./CLAUDE.md found
[Phase 2] git diff --cached → skills/sync-claude-md/SKILL.md added
[Phase 3] Classification: Skill/command addition → Update required
[Phase 4] Proposal:
  - Add sync-claude-md skill to "Skills" section
  - Rationale: skills/sync-claude-md/SKILL.md new file

Agent: Adding sync-claude-md skill info to CLAUDE.md.
[Phase 5] Execute CLAUDE.md update → Display diff summary
         → Sync AGENTS.md as well using the agents-md-copy skill.
```

### Example 3: Simple bug fix (no update required)

```
User: "Sync CLAUDE.md"

[Phase 1] CLAUDE.md discovery → ./CLAUDE.md found
[Phase 2] git diff HEAD → src/utils/format.ts 1 file, 3 lines modified
[Phase 3] Classification: Simple bug fix → No update required

Agent:
No CLAUDE.md update is needed.

Analysis results:
- Change type: Bug fix
- Changed files: 1
- Impact scope: Within existing architecture/rules
```

### Example 4: Full change analysis before PR

```
User: "Check CLAUDE.md before creating the PR"

[Phase 1] CLAUDE.md discovery → ./CLAUDE.md found
[Phase 2] "PR" mention detected → Analyze git diff main...HEAD
          → 12 files changed, docker-compose.yml added, .github/workflows/ci.yml modified
[Phase 3] Classification:
  - Environment/tool change (docker-compose.yml) → Update required
  - Workflow change (CI config) → Update required
[Phase 4] Proposal:
  - Add Docker environment to "Development Setup" section
  - Add new CI pipeline stages to "CI/CD" section
  - Rationale: docker-compose.yml new, ci.yml modified

Agent: Reflecting Docker environment and CI pipeline changes in CLAUDE.md.
[Phase 5] Execute CLAUDE.md update
```

---

## 6. Boundaries

**Will:**
- Automatically analyze changes and determine whether CLAUDE.md update is necessary
- Propose specific update content when update is needed
- Execute CLAUDE.md update after user confirmation
- Provide agents-md-copy skill integration guidance

**Will Not:**
- Modify CLAUDE.md without user confirmation
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
