# Orchestrator Validation Rules (ORC-*)

## ORC-001: Orchestrator Skill Identification
- **Severity**: Critical
- **Check**: Must contain a `## Team Members` table (the team definition, see team-rules.md) or an `## Orchestration Phases` / `## Workflow Phases` section
- **Auto-fixable**: No

## ORC-002: Team Member Coverage
- **Severity**: High
- **Check**: Must reference every Name from its own `## Team Members` table at least once in the phase sections
- **Auto-fixable**: No

## ORC-003: Phase Sequence Completeness
- **Severity**: High
- **Check**: Each phase must have name/number, assigned member(s), input, expected output
- **Auto-fixable**: No

## ORC-004: Data Flow Continuity
- **Severity**: High
- **Check**: Output of Phase N must match input of Phase N+1
- **Auto-fixable**: No

## ORC-005: Error Handling Strategy
- **Severity**: Medium
- **Check**: Must contain error handling or failure recovery section
- **Auto-fixable**: No

## ORC-006: Re-run/Maintenance Mode
- **Severity**: Low
- **Check**: Should document partial re-execution capability
- **Auto-fixable**: No

## ORC-007: Pattern-Specific Structure
- **Severity**: Medium
- **Check**: If a pattern is declared (TEAM-002), phase structure must match it:
  - `pipeline` = linear sequential phases
  - `fan-out-fan-in` = distribute + parallel + aggregate phases
  - `expert-pool` = dispatch + specialist + merge phases
  - `producer-reviewer` = produce + review + iterate phases
  - `supervisor` = plan + delegate + evaluate phases
  - `hierarchical` = multi-level delegation phases
- **Auto-fixable**: No

## ORC-008: CLAUDE.md Pointer Registration
- **Severity**: Medium
- **Check**: The harness must be registered in the **project** `CLAUDE.md` (repo root, not `claude/CLAUDE.md`) with a trigger-only entry: harness name/goal line + invocation condition naming the orchestrator skill. Flag an entry that carries a change-history table or agent/skill listings (change history lives in git commits; details live in the orchestrator skill)
- **Auto-fixable**: Yes (generate a trigger-only entry from the orchestrator frontmatter `name`/`description`)
- **Entry shape**:
  ```markdown
  ## Harness: {Domain}
  **Goal:** {one line}
  **Trigger:** Use the `{orchestrator-skill-name}` skill for {domain} tasks. Simple questions may be answered directly.
  ```
- **Exception**: Orchestrators shipped inside a plugin (`plugins/<name>/skills/…`) are discovered through the plugin skill listing — no project `CLAUDE.md` entry is required

## ORC-009: Orchestrator Skill Line Budget
- **Severity**: High
- **Check**: Orchestrator SKILL.md must be under 500 lines. Excess content should be split to `references/` directory
- **Auto-fixable**: No (content reduction requires judgment)
- **Thresholds**: Optimal < 300 lines, Acceptable < 500 lines, Over > 500 lines
- **Rationale**: Team-generated skills follow Harness convention (stricter than general 5,000-token SKL-004 rule) to keep context window lean for multi-agent coordination

## ORC-010: v1 Team API Artifact Detection
- **Severity**: Critical
- **Check**: Orchestrator skills and team agents must not contain v1 agent-team constructs: `TeamCreate`, `TeamDelete`, `team_name`, broadcast `SendMessage({to: "all"})` (or `to: "*"`), `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, "one team per session" constraints, or a **written** blanket `model: "opus"`-for-all-agents policy (prose/rule text mandating it). Agents that merely all happen to declare the same model are not ORC-010 — that observation belongs to AGT-024 (Medium)
- **Auto-fixable**: No (requires re-expressing the flow in an execution mode)
- **Remediation**: Follow the v1→v2 migration table in team-harness `references/execution-modes.md` (section `v1에서 v2로 전환`): `TeamCreate` → parallel `Agent(name: ...)` in one message; `TeamDelete`/cleanup phase → delete (use `TaskStop` if needed); broadcast → one named `SendMessage` per recipient; experimental flag → remove
- **Exception**: Files whose purpose is detecting or migrating v1 artifacts (validation rules, migration guides) are exempt

## ORC-011: Execution Mode Declaration
- **Severity**: Medium
- **Check**: The orchestrator declares its execution mode — accept a `**실행 모드:**` / `**실행 모드**:` / `- **실행 모드**: …` line, an `**Execution mode:**` line, or a `## 실행 모드: …` heading. Accept English/legacy values as aliases: `Workflow` → A, `Persistent` / `named agents` → B, `Sub-agents` / `Subagent` → C (`Agent Teams` is v1 → ORC-010). The value must be one of **A** workflow orchestration (`Workflow`), **B** persistent agent collaboration (`Agent(name:)` + `SendMessage` + `TaskCreate`/`TaskUpdate`), **C** subagent delegation (`Agent` calls, parallel calls in one message). Mixed-mode orchestrators declare the mode on **every phase**
- **Auto-fixable**: No
- **Also check**: The declared mode matches the tools actually used in the phase body (e.g., a phase declared C must not rely on `SendMessage`); mode A requires the skill to state that `Workflow` runs only with explicit user consent

## ORC-012: Embedded Workflow Script Pitfalls
- **Severity**: High
- **Check**: Applies only when the orchestrator embeds a `Workflow` script (mode A). Flag any of:
  1. `meta` contains variables, calls, or expressions — it must be a pure literal
  2. `Date.now()`, `Math.random()`, or argument-less `new Date()` anywhere in the script (breaks resume replay — pass timestamps/seeds via `args`)
  3. Results of `agent()` / `parallel()` / `pipeline()` used without `.filter(Boolean)` (failed or skipped agents return `null`)
  4. `phase()` titles that do not match the `meta.phases` titles
  5. `parallel()` used where no barrier is needed (results not compared as a whole) — prefer `pipeline()`
  6. TypeScript syntax (type annotations) in the script
- **Auto-fixable**: No
- **Reference**: team-harness `references/workflow-recipes.md` (pitfall checklist)

## ORC-013: Test Scenarios Section
- **Severity**: Low
- **Check**: The orchestrator has a `## 테스트 시나리오` (or `## Test Scenarios`) section with at least 1 normal-flow scenario and at least 1 error-flow scenario
- **Auto-fixable**: No
