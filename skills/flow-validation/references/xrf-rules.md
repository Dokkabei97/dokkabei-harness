# Cross-Reference Validation Rules (XRF-*)

## XRF-001: Command-Agent References
- **Severity**: High
- **Check**: If command frontmatter `personas` lists agent names, verify `agents/{name}.md` exists
- **Auto-fixable**: No (missing agent needs creation)

## XRF-002: Command-Skill References
- **Severity**: Medium
- **Check**: If command references skills in behavioral flow, verify `skills/{name}/SKILL.md` exists
- **Auto-fixable**: No

## XRF-003: Hook Tool References
- **Severity**: High
- **Check**: Hook matcher tool names reference valid Claude Code tools
- **Auto-fixable**: No
- **Valid tools in matchers**: Bash, Write, Edit, Read, Glob, Grep

## XRF-004: Skill Cross-Links
- **Severity**: Low
- **Check**: If SKILL.md references other skills, verify they exist
- **Auto-fixable**: No

## XRF-005: Naming Consistency
- **Severity**: Medium
- **Check**: Frontmatter `name` matches filename (commands) or directory name (skills)
- **Auto-fixable**: Yes (update frontmatter name to match filesystem)
- **Examples**:
  - `commands/deploy-check.md` -> name should be `deploy-check`
  - `skills/redis-best-practices/` -> name should be `redis-best-practices`
