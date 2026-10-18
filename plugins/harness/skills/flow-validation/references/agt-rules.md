# Agent Validation Rules (AGT-*)

## AGT-001: Frontmatter Present and Valid YAML
- **Severity**: Critical
- **Check**: File starts with `---` and contains valid YAML block
- **Auto-fixable**: No
- **Pattern**: `^---\n[\s\S]+?\n---`

## AGT-002: Required Frontmatter Fields
- **Severity**: Critical
- **Check**: YAML contains: name, description (tools is optional, inherits all if omitted)
- **Auto-fixable**: Yes (add missing tools with default `["Read", "Grep", "Glob"]`)

## AGT-003: Valid Tool Names
- **Severity**: High
- **Check**: Each tool in array is a recognized tool name
- **Auto-fixable**: Yes (remove invalid entries)
- **Valid tools**: Read, Grep, Glob, Bash, Write, Edit, WebFetch, WebSearch, Agent, Skill, NotebookEdit, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet, TaskStop (collaboration tools used by execution mode B — never auto-remove them)

## AGT-004: Role Description
- **Severity**: High
- **Check**: `## Your Role` or `## Role` section with 3+ bullet responsibilities
- **Auto-fixable**: No

## AGT-005: Workflow Section
- **Severity**: Critical
- **Check**: Section matching `Workflow` or `Analysis` with numbered steps
- **Auto-fixable**: No (requires domain expertise)

## AGT-006: Decision Matrices
- **Severity**: Medium
- **Check**: At least one markdown table or Grep/Glob pattern block in workflow
- **Auto-fixable**: No

## AGT-007: Output Format
- **Severity**: Medium
- **Check**: `## Output` section with report template
- **Auto-fixable**: No

## AGT-008: Boundaries
- **Severity**: High
- **Check**: `## Boundaries` with Will/Will Not lists
- **Auto-fixable**: No

## AGT-009: Description Trigger Quality
- **Severity**: Critical
- **Check**: Agent description must contain "Use when" or "Use PROACTIVELY when" phrase, clearly identify the agent's role, and specify technology scope
- **Auto-fixable**: No (requires understanding of agent purpose)
- **Good example**: "Architecture review specialist that analyzes codebase structure. Use when reviewing projects for architecture conformance. Supports Kotlin (Spring Boot), Python (FastAPI/Django)."
- **Bad example**: "A helpful agent that does code review."

## AGT-010: Tools Minimality
- **Severity**: Low
- **Check**: All tools declared in frontmatter `tools` array are actually referenced or used in the agent body
- **Auto-fixable**: Yes (remove unreferenced tools from array)
- **Rationale**: Declaring unused tools inflates the agent's capabilities description without purpose

## AGT-011: System Prompt Structure
- **Severity**: High
- **Check**: Agent body must contain these structural elements:
  1. Role definition paragraph starting with "You are a/an..."
  2. `## Your Role` or `## Core Responsibilities` with bulleted list
  3. Numbered workflow steps in `## Analysis Workflow` or `## Workflow`
  4. At least one BAD/GOOD code example pattern
  5. `## Output Format` with expected output structure
- **Auto-fixable**: No (requires domain expertise)

## AGT-012: Token Budget Warning
- **Severity**: Medium
- **Check**: Agent body should be flagged if exceeding 50,000 characters as it may cause context window issues
- **Auto-fixable**: No (content reduction requires judgment)
- **Thresholds**: OK < 30,000 chars, Warning < 50,000 chars, Critical > 50,000 chars

## AGT-013: Model Override Validity
- **Severity**: Medium
- **Check**: If `model` specified, valid value (fable, opus, sonnet, haiku, inherit, or full model ID)
- **Auto-fixable**: No

## AGT-014: Permission Mode Validity
- **Severity**: High
- **Check**: If `permissionMode` specified, valid value
- **Auto-fixable**: No
- **Valid**: default, acceptEdits, auto, dontAsk, bypassPermissions, plan

## AGT-015: MaxTurns Reasonableness
- **Severity**: Low
- **Check**: If `maxTurns` specified, value is between 1 and 100
- **Auto-fixable**: No

## AGT-016: Skills Preload Validity
- **Severity**: Medium
- **Check**: If `skills` array specified, each skill name exists in project or personal skills
- **Auto-fixable**: No

## AGT-017: MCP Server References
- **Severity**: Medium
- **Check**: If `mcpServers` specified, references are valid (inline config or name reference)
- **Auto-fixable**: No

## AGT-018: Memory Scope Validity
- **Severity**: Medium
- **Check**: If `memory` specified, valid scope (user, project, local)
- **Auto-fixable**: No

## AGT-019: Isolation Mode Validity
- **Severity**: Low
- **Check**: If `isolation` specified, must be `worktree`
- **Auto-fixable**: Yes (only valid value)

## AGT-020: Agent Hooks Validity
- **Severity**: High
- **Check**: If `hooks` in frontmatter, valid events and handler types
- **Auto-fixable**: No
- **Valid events**: PreToolUse, PostToolUse, Stop
- **Valid handler types**: command, http, prompt, agent
- **Plugin restriction**: Plugin-shipped agents do NOT support `hooks`, `mcpServers`, or `permissionMode`

## AGT-020a: Effort Field Validity
- **Severity**: Low
- **Check**: If `effort` specified, must be one of: low, medium, high, max
- **Auto-fixable**: No
- **Note**: Only effective with Opus 4.6 model

## AGT-020b: InitialPrompt Field
- **Severity**: Low
- **Check**: If `initialPrompt` specified, must be a non-empty string. Only used when agent runs as main session agent
- **Auto-fixable**: No

## AGT-020c: Color Field Validity
- **Severity**: Low
- **Check**: If `color` specified, must be one of: red, blue, green, yellow, purple, orange, pink, cyan
- **Auto-fixable**: No

## AGT-020d: Plugin Agent Restrictions
- **Severity**: High
- **Check**: If agent is shipped via a plugin (located under a plugin directory), it must NOT use `hooks`, `mcpServers`, or `permissionMode` in frontmatter (blocked for security)
- **Auto-fixable**: Yes (remove restricted fields)

---

> **Note**: AGT-021 through AGT-026 are **conditional rules** that only apply when the agent has `team` or `teamRole` in frontmatter, or is listed in an orchestrator skill's `## Team Members` table (the team definition — there is no separate team config file). AGT-021 additionally applies only to members of a **mode B** (persistent agent collaboration) orchestrator or phase — mode A (Workflow) and mode C (sub-agent delegation, incl. `Sub-agents` declarations) members never message peers and are exempt. AGT-027 applies to all agents.

## AGT-021: Team Communication Protocol Section
- **Severity**: High
- **Check**: If agent is a mode B team member, must have a `## Team Communication Protocol` section (heading kept for compatibility) whose content follows the v2 model:
  1. Messages go to **named** targets — `SendMessage({to: "<name>"})`, one call per recipient
  2. No broadcast — `SendMessage({to: "all"})` or "send to all members" wording is a violation
  3. Shared task list usage documented — which tasks the agent registers/claims/updates via `TaskCreate`/`TaskUpdate` (or that the leader updates on its behalf)
  4. First report lists the tools actually available at runtime (deferred tools such as `TaskCreate`/`TaskUpdate` may be missing even when declared)
- **Auto-fixable**: No
- **Note**: Workflow-only agents (execution mode A) replace this section with a structured-output section (JSON shape returned as data); do not flag them for missing SendMessage targets

## AGT-022: SendMessage Target Validity
- **Severity**: High
- **Check**: Named `SendMessage` targets in agent body must exist in the Name column of the orchestrator skill's `## Team Members` table
- **Auto-fixable**: No

## AGT-023: Task Assignment Pattern Documentation
- **Severity**: Medium
- **Check**: If `teamRole` is `coordinator` or `supervisor`, must document task assignment strategy
- **Auto-fixable**: No

## AGT-024: Team Agent Model Tier Selection
- **Severity**: Medium (blanket high-tier assignment) / Low (missing reason comment)
- **Check**: Each team agent's `model` is chosen per task tier, not per perceived importance, with the reason recorded as a comment (inline YAML comment on `model:` or a note in the orchestrator):
  - `fable` — long-horizon autonomous planning, coordination, large-scale synthesis
  - `opus` — scoped deep analysis, design/architecture, code generation, cross-verification
  - `sonnet` — routine/procedural work (collection, conversion, static checks, summaries); default when unsure
  - `haiku`, `inherit`, or a full model ID remain valid when deliberately chosen
- **Flag**: Every member of the team assigned the same high tier (`fable` or `opus`) → Medium. A `model:` without a reason comment → Low
- **Auto-fixable**: No (tier choice requires understanding of each agent's workload)
- **Rationale**: v1 forced `model: "opus"` on all team agents; v2 retires that policy (see team-harness `references/model-selection-guide.md`)

## AGT-025: Team Role Frontmatter Presence
- **Severity**: Medium
- **Check**: If agent is listed in an orchestrator skill's `## Team Members` table, frontmatter should contain `teamRole`
- **Auto-fixable**: Yes (copy role from the Role column of the `## Team Members` table)

## AGT-026: Workspace Artifact Awareness
- **Severity**: Medium
- **Check**: Team worker agents should document `_workspace/` artifact paths they read or produce
- **Auto-fixable**: No

## AGT-027: Tool Set Matches Edit Intent
- **Severity**: High (read-only agent holds `Edit`) / Medium (other mismatches)
- **Check**: Applies to all agents with an explicit `tools` list:
  1. **Read-only agents** (reviewer, checker, verifier, auditor — description/role says it reviews, verifies, or analyzes without changing the target) must not have `Edit`. `Write` is allowed only when the body restricts it to its own report/marker output; otherwise remove `Write` too
  2. **Modifying agents** (body says it fixes, edits, or updates artifacts) that have `Write` must also have `Edit` — with Write only, large artifacts get rewritten wholesale or the agent works around the edit
- **Auto-fixable**: No (intent classification requires judgment)
- **Rationale**: Upstream harness v2 step 3 — read-only reviewers drop Edit/Write; artifact modifiers need both
