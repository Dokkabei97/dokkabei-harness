# {{TEAM_NAME}} Team Configuration

## Team Metadata

| Field | Value |
|-------|-------|
| Name | {{TEAM_NAME}} |
| Pattern | {{hub-spoke|pipeline|parallel|swarm}} |
| Description | {{TEAM_DESCRIPTION}} |
| Creation Date | {{CREATION_DATE}} |

## Member Registry

| Agent Name | Role | Model | Skills | Background |
|-----------|------|-------|--------|------------|
| `{{AGENT_1}}` | leader | {{MODEL_1}} | [{{SKILLS_1}}] | {{true\|false}} |
| `{{AGENT_2}}` | member | {{MODEL_2}} | [{{SKILLS_2}}] | {{true\|false}} |
| `{{AGENT_3}}` | specialist | {{MODEL_3}} | [{{SKILLS_3}}] | {{true\|false}} |
| `{{AGENT_4}}` | member | {{MODEL_4}} | [{{SKILLS_4}}] | {{true\|false}} |

## Communication Protocols

### Message Routing

| From | To | Channel | Format |
|------|----|---------|--------|
| leader | all members | SendMessage | Task assignment |
| member | leader | SendMessage | Status report / Handoff |
| specialist | leader | SendMessage | Analysis result |
| any | orchestrator | Escalation | Error report |

### Status Reporting

Members report status at these checkpoints:
- **Phase start**: Acknowledge task receipt and confirm input
- **Phase midpoint**: Progress update with preliminary findings
- **Phase complete**: Final output with handoff notes
- **On error**: Immediate escalation with context

### Message Format

```
[{{TEAM_NAME}}] {{AGENT_NAME}} -> {{TARGET_AGENT}}
Type: {{task|status|handoff|escalation}}
Phase: {{CURRENT_PHASE}}
Content: {{MESSAGE_CONTENT}}
```

## Shared Resources

### Skills

| Skill | Purpose | Used By |
|-------|---------|---------|
| `{{SHARED_SKILL_1}}` | {{SKILL_PURPOSE_1}} | all |
| `{{SHARED_SKILL_2}}` | {{SKILL_PURPOSE_2}} | {{USING_AGENTS_2}} |
| `{{SHARED_SKILL_3}}` | {{SKILL_PURPOSE_3}} | {{USING_AGENTS_3}} |

### MCP Servers

| Server | Purpose | Used By |
|--------|---------|---------|
| `{{MCP_SERVER_1}}` | {{SERVER_PURPOSE_1}} | {{USING_AGENTS_1}} |
| `{{MCP_SERVER_2}}` | {{SERVER_PURPOSE_2}} | {{USING_AGENTS_2}} |

## CLAUDE.md Registration

Add the following to your project's `.claude/CLAUDE.md` or `~/.claude/CLAUDE.md` to register this team:

```markdown
## Teams

### {{TEAM_NAME}}
- Pattern: {{hub-spoke|pipeline|parallel|swarm}}
- Orchestrator: `{{ORCHESTRATOR_SKILL_NAME}}`
- Members: {{AGENT_1}}, {{AGENT_2}}, {{AGENT_3}}, {{AGENT_4}}
- Trigger: "{{TRIGGER_PHRASE}}"
```

### Agent Registration

Each team agent should be placed in the agents directory:
```
agents/
  {{AGENT_1}}.md
  {{AGENT_2}}.md
  {{AGENT_3}}.md
  {{AGENT_4}}.md
```

### Orchestrator Registration

The orchestrator skill should be placed in the skills directory:
```
skills/
  {{TEAM_NAME}}-orchestrator/
    SKILL.md
```
