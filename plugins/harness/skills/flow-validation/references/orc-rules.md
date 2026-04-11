# Orchestrator Validation Rules (ORC-*)

## ORC-001: Orchestrator Skill Identification
- **Severity**: Critical
- **Check**: Must be referenced as orchestrator in team definition or contain `## Orchestration Phases` section
- **Auto-fixable**: No

## ORC-002: Team Member Coverage
- **Severity**: High
- **Check**: Must reference every member from team definition at least once
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
- **Check**: Phase structure must match team's declared pattern:
  - `pipeline` = linear sequential phases
  - `fan-out-fan-in` = distribute + parallel + aggregate phases
  - `expert-pool` = dispatch + specialist + merge phases
  - `producer-reviewer` = produce + review + iterate phases
  - `supervisor` = plan + delegate + evaluate phases
  - `hierarchical` = multi-level delegation phases
- **Auto-fixable**: No

## ORC-008: CLAUDE.md Pointer Registration
- **Severity**: Medium
- **Check**: Team entry must be registered in `claude/CLAUDE.md`
- **Auto-fixable**: Yes (generate entry from team definition)

## ORC-009: Orchestrator Skill Line Budget
- **Severity**: High
- **Check**: Orchestrator SKILL.md must be under 500 lines. Excess content should be split to `references/` directory
- **Auto-fixable**: No (content reduction requires judgment)
- **Thresholds**: Optimal < 300 lines, Acceptable < 500 lines, Over > 500 lines
- **Rationale**: Team-generated skills follow Harness convention (stricter than general 5,000-token SKL-004 rule) to keep context window lean for multi-agent coordination
