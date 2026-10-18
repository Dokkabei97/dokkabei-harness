# Team Validation Rules (TEAM-*)

> **Team definition (v2)**: there is no team object and no separate team config file. The team definition is the
> orchestrator skill's `## Team Members` table (template: `flow-scaffolding/templates/orchestrator-skill.md`,
> columns `Name | Agent | Role | Skills | Output`). Existing orchestrators may use equivalent column labels —
> accept `ID`/`이름` for Name, `에이전트`/`에이전트 파일` for Agent, `역할`/`구분` for Role, `산출물` for Output.
> `Skills` is optional. A `team_name` key anywhere is a v1 artifact (see ORC-010).

## TEAM-001: Team Definition Structure
- **Severity**: Critical
- **Check**: The orchestrator SKILL.md contains a `## Team Members` heading followed by a markdown table with at least the Name, Agent, Role, and Output columns (or the accepted equivalents above), plus frontmatter `description`
- **Auto-fixable**: No

## TEAM-002: Team Pattern Validity
- **Severity**: Critical (invalid value) / Low (no pattern declared)
- **Check**: If the orchestrator declares a team pattern, at least one of its components must map to a recognized pattern. Accept every declaration form: `**Pattern:**`, `**패턴:**`, `**패턴**:`, `- **패턴**: …` (bold with the colon inside or outside). Composite declarations are allowed (team-harness Phase 2: 택일 또는 복합) — split on `+`/`,`, strip parenthesized notes, and match each part case-insensitively against the values and aliases below. Parts that match nothing (e.g. `PRD-Driven Loop`, `Verification Gate`) are augmentation patterns and are ignored, not flagged. Critical only when **no** part maps to a recognized pattern
- **Auto-fixable**: Yes (suggest closest match)
- **Valid values**: `pipeline` (aliases: Sequential Pipeline, Pipeline), `fan-out-fan-in` (Fan-out/Fan-in, Fan-out·Fan-in), `expert-pool` (Expert Pool), `producer-reviewer` (Producer-Reviewer, 생성·검증), `supervisor` (Supervisor, 감독자), `hierarchical` (Hierarchical, 계층형 위임)

## TEAM-003: Member Registration Completeness
- **Severity**: High
- **Check**: Every `## Team Members` row has a non-empty Name, Agent, Role, and Output cell
- **Auto-fixable**: No

## TEAM-004: Member Role Assignment Validity
- **Severity**: High (pattern constraint violated) / Low (Role cell has no recognized keyword — free-text roles in existing orchestrators are reported, not failed)
- **Check**: Each Role cell starts with (or contains) a recognized role keyword — `leader` (aliases: coordinator, supervisor), `member` (aliases: worker, maker), `specialist`, `checker` (alias: reviewer). Free-text explanation after the keyword is allowed. Pattern-specific constraints apply when TEAM-002 declares a pattern:
  - `pipeline` requires 2+ member/maker rows
  - `supervisor` requires exactly 1 leader row
  - `producer-reviewer` requires 1+ maker and 1+ checker rows
- **Auto-fixable**: No

## TEAM-005: No Orphaned Team Members
- **Severity**: High
- **Check**: Every Agent cell resolves to `agents/{name}.md` (or `.claude/agents/{name}.md`) or a built-in type. A `leader` row may name the main session itself (`main session` / `메인 세션`) instead of an agent file — mode B templates make the main session the leader
- **Auto-fixable**: No
- **Valid built-in types**: `general-purpose`, `Explore`, `Plan` (plus `main session` / `메인 세션` for leader rows)

## TEAM-006: Orchestrator Skill Existence
- **Severity**: Critical
- **Check**: Every agent carrying `team` or `teamRole` frontmatter is listed in the `## Team Members` table of an existing orchestrator skill (`skills/{team}-orchestrator/SKILL.md` or any skill with that table). A team agent with no owning orchestrator is unreachable
- **Auto-fixable**: No

## TEAM-007: Unique Member Names
- **Severity**: High
- **Check**: All Name cells in the `## Team Members` table are unique (they are the `Agent(name:)` / `SendMessage({to:})` addresses)
- **Auto-fixable**: Yes (append numeric suffix)

## TEAM-008: Team Size Reasonableness
- **Severity**: Low
- **Check**: The `## Team Members` table has 2-10 rows. <2 is not a team, >10 introduces coordination overhead risk (v2 default: keep teams small — 2-5 persistent agents)
- **Auto-fixable**: No
