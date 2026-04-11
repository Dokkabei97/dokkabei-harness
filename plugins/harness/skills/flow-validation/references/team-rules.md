# Team Validation Rules (TEAM-*)

## TEAM-001: Team Definition Structure
- **Severity**: Critical
- **Check**: Team definition must contain: `team_name`, `description`, `pattern`, and `members` array
- **Auto-fixable**: No

## TEAM-002: Team Pattern Validity
- **Severity**: Critical
- **Check**: `pattern` must be one of the recognized team patterns
- **Auto-fixable**: Yes (suggest closest match)
- **Valid values**: `pipeline`, `fan-out-fan-in`, `expert-pool`, `producer-reviewer`, `supervisor`, `hierarchical`

## TEAM-003: Member Registration Completeness
- **Severity**: High
- **Check**: Each member must have: `name`, `agent` (file reference or built-in type), `role` (worker|coordinator|supervisor)
- **Auto-fixable**: No

## TEAM-004: Member Role Assignment Validity
- **Severity**: High
- **Check**: `role` must be one of `worker`, `coordinator`, `supervisor`. Pattern-specific constraints apply:
  - `pipeline` requires 2+ workers
  - `supervisor` requires exactly 1 supervisor
  - `producer-reviewer` requires 1+ of each type
- **Auto-fixable**: No

## TEAM-005: No Orphaned Team Members
- **Severity**: High
- **Check**: Every `members[].agent` must resolve to `agents/{name}.md` or a built-in type
- **Auto-fixable**: No
- **Valid built-in types**: `general-purpose`, `Explore`, `Plan`

## TEAM-006: Orchestrator Skill Existence
- **Severity**: Critical
- **Check**: Team must reference an orchestrator skill that exists at `skills/{name}/SKILL.md`
- **Auto-fixable**: No

## TEAM-007: Unique Member Names
- **Severity**: High
- **Check**: All `members[].name` must be unique (used for SendMessage addressing)
- **Auto-fixable**: Yes (append numeric suffix)

## TEAM-008: Team Size Reasonableness
- **Severity**: Low
- **Check**: Team has 2-10 members. <2 is not a team, >10 introduces coordination overhead risk
- **Auto-fixable**: No
