---
name: handoff
description: "Save session context to HANDOFF.md for seamless continuation in the next session"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /handoff - Session Context Transfer

## Triggers
- When the conversation grows long and approaches context window limits
- When you need to end the session and resume work later
- When handing off work progress to another session/agent

## Usage
```
/handoff
```

## Behavioral Flow

### Phase 1: Collect Change State
Gather git status to understand the current working environment.

**Commands to execute:**
```bash
git branch --show-current     # Current branch
git status --short            # List of uncommitted changed files
git diff --stat               # Change statistics
git log --oneline -10         # Recent commit history
```

All git commands should be executed **in parallel**.

### Phase 2: Analyze Conversation Context
Analyze the current session's conversation to extract key information.

1. **Identify Session Goal**: Summarize the user's initial request into a one-line core objective
2. **Classify Attempted Approaches**: Categorize each approach/task as success or failure
   - Success: Completed tasks, created/modified files with brief descriptions
   - Failure: Failed approaches and their reasons
3. **Identify Unresolved Issues**: Incomplete tasks or discovered problems

### Phase 3: Generate HANDOFF.md
Write the `HANDOFF.md` file at the project root using the **Write tool**.
Structure it to be self-contained so the next agent can resume work by reading this single file.

**Output Template:**
```markdown
# HANDOFF - Session Context Transfer

> This file contains the work context from the previous session.
> Read this file in a new session to continue the work.

## Session Info
- Date: {YYYY-MM-DD}
- Branch: {current branch}
- Goal: {one-line summary of the session's core objective}

## What Was Tried
- {list of attempted approaches/tasks - with result indicated for each}

## What Succeeded
- {successful items}
- {list of modified/created files with brief descriptions}

## What Failed
- {failed approach: reason}

## Current State
- Branch: {branch name}
- Uncommitted: {list of uncommitted files}
- Build/Test: {build/test status if applicable}

## Next Steps
1. {next priority task}
2. {follow-up tasks}

## Key Files
- `path/to/file` - {role description}
```

### Phase 4: Provide Next Steps Guidance
After generating HANDOFF.md, guide the user with the following workflow:

```
HANDOFF.md has been created.

To resume work in the next session:
1. Run /clear to clean up the current session
2. In the new session, type:
   @HANDOFF.md Read this file and continue the work
```

## Tool Coordination
- **Bash**: `git status`, `git diff`, `git log`, `git branch` (parallel execution)
- **Read**: Check related files (if needed)
- **Write**: Create `HANDOFF.md` file

## Examples

### Basic Usage
```
/handoff
# Saves current session's work context to HANDOFF.md
# Includes git status + conversation summary + next steps
```

## Boundaries

**Will:**
- Collect git status (branch, status, diff, log)
- Analyze and summarize session conversation context
- Create a self-contained HANDOFF.md at the project root
- Provide next session workflow guidance

**Will Not:**
- Modify code or create commits
- Perform remote operations such as git push
- Overwrite existing HANDOFF.md without warning (will warn before proceeding)
