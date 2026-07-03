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
- **Valid tools in matchers**: Bash, Write, Edit, Read, Glob, Grep, WebSearch, WebFetch, Agent, Skill, NotebookEdit

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

## XRF-006: Agent Skill Preload References
- **Severity**: Medium
- **Check**: If agent frontmatter `skills` lists skill names, verify skills exist
- **Auto-fixable**: No

## XRF-007: Agent MCP Server References
- **Severity**: Medium
- **Check**: If agent frontmatter `mcpServers` references named servers, verify they exist in MCP config
- **Auto-fixable**: No

## XRF-008: Skill Agent References
- **Severity**: Medium
- **Check**: If skill has `context: fork` and `agent` field referencing a custom agent, verify agent exists in `.claude/agents/`
- **Auto-fixable**: No

## XRF-009: Plugin Namespace Consistency
- **Severity**: High
- **Check**: Plugin skills use `plugin-name:skill-name` namespace correctly, no conflicts with project skills
- **Auto-fixable**: No

## XRF-010: Team to Agent References Valid
- **Severity**: High
- **Check**: Every `members[].agent` in team definition resolves to `agents/{name}.md` or a valid built-in type
- **Auto-fixable**: No

## XRF-011: Team to Orchestrator Skill Reference Valid
- **Severity**: Critical
- **Check**: Team's orchestrator reference resolves to an existing `skills/{name}/SKILL.md`
- **Auto-fixable**: No

## XRF-012: Orchestrator to Team Member References Valid
- **Severity**: High
- **Check**: All member names referenced in orchestrator phases exist in the team's `members` list
- **Auto-fixable**: No

## XRF-013: Agent Team Self-Reference Consistency
- **Severity**: Medium
- **Check**: Agent frontmatter `team` and `teamRole` values match the corresponding team definition entry
- **Auto-fixable**: No

## XRF-014: Workspace Artifact Path Consistency
- **Severity**: Medium
- **Check**: `_workspace/` artifact paths referenced by producers match paths expected by consumers within the team
- **Auto-fixable**: No

## XRF-015: Team Hook Event Utilization
- **Severity**: Low
- **Check**: If team agents define hooks, verify hook events are relevant to team coordination (advisory)
- **Auto-fixable**: No

## XRF-016: Marketplace-Plugin Dependency Drift
- **Severity**: High
- **Check**: Dependency declarations must agree across three sources for each plugin: marketplace.json `plugins[].requires`, the plugin's plugin.json `dependencies`, and prose statements in the plugin's docs (README/commands referencing another plugin's hooks/commands as prerequisites). Flag any plugin where one source declares a dependency the others omit or contradict
- **Auto-fixable**: No (source of truth must be decided by the maintainer — report drift only)
- **Example**: `plugins/mvp/.claude-plugin/plugin.json` declares `"dependencies": ["base"]` → marketplace.json's `mvp` entry must declare `"requires": ["base"]`, and vice versa; a command doc stating "base 플러그인의 보안 훅 전제" with neither manifest declaring it is also drift
