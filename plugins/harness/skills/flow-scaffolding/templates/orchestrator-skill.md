---
name: {{TEAM_NAME}}-orchestrator
description: |
  {{ORCHESTRATOR_DESCRIPTION_LINE_1}}
  {{ORCHESTRATOR_DESCRIPTION_LINE_2}}
# --- Agent Skills Open Standard (optional) ---
# license: {{LICENSE}}
# compatibility: [{{COMPATIBLE_TOOLS}}]
# metadata:
#   version: {{VERSION}}
#   category: {{CATEGORY}}
# --- Claude Code Extensions (optional) ---
# argument-hint: {{ARGUMENT_HINT}}
# disable-model-invocation: {{true|false}}
# user-invocable: {{true|false}}
# allowed-tools: [{{ALLOWED_TOOLS}}]
# model: {{MODEL_OVERRIDE}}
# context: {{fork}}
# agent: {{AGENT_TYPE}}
# hooks:
#   PreToolUse:
#     - type: {{command|http|prompt|agent}}
#       command: {{HOOK_COMMAND}}
---

# {{TEAM_NAME}} Orchestrator

{{BRIEF_DESCRIPTION}}

## When to Apply

Activate this orchestrator when:
- {{APPLY_CONDITION_1}}
- {{APPLY_CONDITION_2}}
- {{APPLY_CONDITION_3}}
- {{APPLY_CONDITION_4}}

## Team Members

| Name | Agent | Role | Skills | Output |
|------|-------|------|--------|--------|
| {{MEMBER_NAME_1}} | `{{AGENT_1}}` | leader | {{SKILLS_1}} | {{OUTPUT_1}} |
| {{MEMBER_NAME_2}} | `{{AGENT_2}}` | member | {{SKILLS_2}} | {{OUTPUT_2}} |
| {{MEMBER_NAME_3}} | `{{AGENT_3}}` | specialist | {{SKILLS_3}} | {{OUTPUT_3}} |
| {{MEMBER_NAME_4}} | `{{AGENT_4}}` | member | {{SKILLS_4}} | {{OUTPUT_4}} |

## Workflow Phases

### Phase 1: {{PHASE_1_NAME}}

- **Assigned to**: {{PHASE_1_MEMBER}}
- **Input**: {{PHASE_1_INPUT}}
- **Output**: {{PHASE_1_OUTPUT}}

{{PHASE_1_DESCRIPTION}}

### Phase 2: {{PHASE_2_NAME}}

- **Assigned to**: {{PHASE_2_MEMBER}}
- **Input**: {{PHASE_2_INPUT}}
- **Output**: {{PHASE_2_OUTPUT}}

{{PHASE_2_DESCRIPTION}}

### Phase 3: {{PHASE_3_NAME}}

- **Assigned to**: {{PHASE_3_MEMBER}}
- **Input**: {{PHASE_3_INPUT}}
- **Output**: {{PHASE_3_OUTPUT}}

{{PHASE_3_DESCRIPTION}}

### Phase 4: {{PHASE_4_NAME}}

- **Assigned to**: {{PHASE_4_MEMBER}}
- **Input**: {{PHASE_4_INPUT}}
- **Output**: {{PHASE_4_OUTPUT}}

{{PHASE_4_DESCRIPTION}}

## Completion Criteria

All of the following must be satisfied before the workflow is marked complete:

- [ ] {{COMPLETION_CRITERION_1}}
- [ ] {{COMPLETION_CRITERION_2}}
- [ ] {{COMPLETION_CRITERION_3}}
- [ ] {{COMPLETION_CRITERION_4}}
- [ ] All phase outputs collected and validated
- [ ] Final summary delivered to the user

## Error Handling

| Error Type | Detection | Recovery Action |
|-----------|-----------|-----------------|
| {{ERROR_TYPE_1}} | {{DETECTION_1}} | {{RECOVERY_1}} |
| {{ERROR_TYPE_2}} | {{DETECTION_2}} | {{RECOVERY_2}} |
| Agent timeout | No response within maxTurns | Reassign to fallback agent or report partial results |
| Phase failure | Agent reports unrecoverable error | Skip phase, log gap, continue with available data |
| Data inconsistency | Output validation fails | Re-run phase with corrected input |

## Re-run Support

This orchestrator supports partial and full re-runs:

- **Full re-run**: Invoke the orchestrator again with the same input to repeat all phases
- **Partial re-run**: Specify `--from-phase={{PHASE_NUMBER}}` to resume from a specific phase
- **Single phase**: Specify `--only-phase={{PHASE_NUMBER}}` to re-run one phase in isolation

**State recovery:**
- Phase outputs are stored as artifacts between phases
- Previously completed phase outputs are reused unless `--force-refresh` is specified
- Failed phases can be retried up to {{MAX_RETRIES}} times before escalation
