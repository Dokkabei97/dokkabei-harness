---
name: {{TEAM_NAME}}-orchestrator
# FOLLOW_UP_TRIGGERS = 후속 요청 표현: 다시 실행·재실행·업데이트·보완·이전 결과 기반
description: |
  {{ORCHESTRATOR_DESCRIPTION_LINE_1}}
  {{FOLLOW_UP_TRIGGERS}}
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

**실행 모드:** {{A 워크플로 조율 | B 지속형 에이전트 협업 | C 서브에이전트 위임 | 혼합(단계별 표기)}} — {{MODE_REASON}}
<!-- 결정 순서: 제어흐름을 코드로 정할 수 있으면 A(`Workflow`) → 대화·맥락 유지가 필요하면 B(`Agent(name:)` + `SendMessage({to:"<name>"})` + `TaskCreate`/`TaskUpdate`) → 결과만 필요하면 C(`Agent` 호출, 병렬은 한 메시지에). 혼합이면 아래 각 Phase에 `**실행 모드:**`를 적는다. A는 사용자 명시 동의가 있을 때만 실행하고 기본 규모를 작게 둔다. -->
**Pattern:** {{pipeline|fan-out-fan-in|expert-pool|producer-reviewer|supervisor|hierarchical}}

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
| {{MEMBER_NAME_4}} | `{{AGENT_4}}` | checker | {{SKILLS_4}} | {{OUTPUT_4}} |

<!-- 이 표가 팀 정의다(별도 팀 설정 파일 없음). Name = `Agent(name:)`·`SendMessage({to:})` 주소. Role 키워드: leader / member / specialist / checker. 모델은 각 에이전트 정의의 `model:`에 업무 티어 + 이유 주석으로 지정한다. -->

## Data Transfer

| Method | Used for | Path / Mechanism |
|--------|----------|------------------|
| {{구조화 반환값 (A: `agent(prompt, {schema})`) / 일반 반환값 (C) / 메시지 (B: `SendMessage`) / 공유 작업 목록 (B: `TaskCreate`/`TaskUpdate`) / 파일}} | {{WHAT_IS_TRANSFERRED}} | {{MECHANISM}} |
| 파일 | 중간 산출물 | `_workspace/{phase}_{agent}_{artifact}.{ext}` (사후 검증용으로 보존, 최종 산출물만 사용자 지정 경로) |

## Workflow Phases

### Phase 1: {{PHASE_1_NAME}}

**실행 모드:** {{PHASE_1_MODE}}  <!-- 혼합 모드일 때만 필수 -->

- **Assigned to**: {{PHASE_1_MEMBER}}
- **Input**: {{PHASE_1_INPUT}}
- **Output**: {{PHASE_1_OUTPUT}}

{{PHASE_1_DESCRIPTION}}

### Phase 2: {{PHASE_2_NAME}}

**실행 모드:** {{PHASE_2_MODE}}  <!-- 혼합 모드일 때만 필수 -->

- **Assigned to**: {{PHASE_2_MEMBER}}
- **Input**: {{PHASE_2_INPUT}}
- **Output**: {{PHASE_2_OUTPUT}}

{{PHASE_2_DESCRIPTION}}

### Phase 3: {{PHASE_3_NAME}}

**실행 모드:** {{PHASE_3_MODE}}  <!-- 혼합 모드일 때만 필수 -->

- **Assigned to**: {{PHASE_3_MEMBER}}
- **Input**: {{PHASE_3_INPUT}}
- **Output**: {{PHASE_3_OUTPUT}}

{{PHASE_3_DESCRIPTION}}

### Phase 4: {{PHASE_4_NAME}}

**실행 모드:** {{PHASE_4_MODE}}  <!-- 혼합 모드일 때만 필수 -->

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
| Data inconsistency | Output validation fails | Keep conflicting data with sources; re-run phase with corrected input |
| Non-retryable failure (usage limit, auth expiry, permission denied) | Same error on retry | Do not retry; inspect partial artifacts, record gaps to a file, report to user (include limit reset time) |
| Workflow `agent()` returned `null` (mode A) | `.filter(Boolean)` drops it | `log()` the dropped count; report the gap in the final summary |
| Persistent agent unresponsive (mode B) | No reply to `SendMessage` | Re-instruct via `SendMessage`; if still failing, start the same agent type under a new name with the needed context |

## Re-run Support

Phase 0 checks existing context before running:

- **`_workspace/` exists + partial-fix request** → re-run only the affected phase/agent, reusing other phase outputs
- **`_workspace/` exists + new input** → move it to `_workspace_{{TIMESTAMP}}/`, then run from the start
- **No `_workspace/`** → full run from the start
- **Mode A with a previous `runId`** → resume via `Workflow` `resumeFromRunId`; unchanged `agent()` calls reuse cached results
- Retry a failed phase once; on a second failure continue without it and record the gap (max {{MAX_RETRIES}} retries)

## 테스트 시나리오

### 정상 흐름
1. 입력: {{NORMAL_INPUT}}
2. 기대: {{NORMAL_PHASE_SEQUENCE}} → {{NORMAL_EXPECTED_OUTPUT}}

### 오류 흐름
1. 상황: {{ERROR_CONDITION}} (예: Phase {{N}} 에이전트 실패, 사용량 한도 소진)
2. 기대: {{ERROR_HANDLING_BEHAVIOR}} — 누락 사실이 최종 보고에 기록됨
