# Orchestrator Skill Templates

팀 전체를 조율하는 상위 스킬인 오케스트레이터. 실행 모드별 3가지 템플릿 제공.

---

## Template A: Agent Team Mode (기본, 최우선)

2명 이상 협업 시 최우선 선택. `TeamCreate`와 공유 작업 목록, `SendMessage`로 팀 조율.

### Frontmatter
```yaml
---
name: {domain}-orchestrator
description: |
  {domain} 팀 오케스트레이터. {초기 키워드}, {후속 작업 키워드}.
  재실행/업데이트/수정/보완, "{도메인}의 {부분}만 다시",
  "이전 결과 기반으로", "결과 개선" 시에도 사용.
---
```

### Agent Configuration Table
| 팀원 | 에이전트 타입 | 역할 | 스킬 | 출력 파일 |
|------|-------------|------|------|----------|
| {name} | {general-purpose/custom} | {역할} | {스킬명} | {_workspace/path} |

### Workflow (5 Phases + Phase 0)

**Phase 0: Context Check**
- `_workspace/` 존재 확인
- 초기 실행 / 부분 재실행 / 새 입력 분기
- 부분 재실행: 이전 산출물 경로를 에이전트 프롬프트에 포함

**Phase 1: Preparation**
- 사용자 입력 분석
- `_workspace/` 생성 (초기 실행)
- 입력 데이터 → `_workspace/00_input/`

**Phase 2: Team Formation**
- `TeamCreate`로 팀 생성 (팀원당 역할/모델/프롬프트)
- `TaskCreate`로 작업 등록 (의존성 포함, 팀원당 5~6개 적정)

**Phase 3: Execution**
- 팀원들이 공유 작업 목록에서 작업 요청/수행
- `SendMessage`로 팀원 간 정보 전달
- 산출물: `_workspace/{phase}_{teammate}_{artifact}.md`
- 리더가 `TaskGet`으로 진행률 모니터링

**Phase 4: Integration**
- `TaskGet`으로 전원 완료 대기
- `Read`로 산출물 수집 → 통합/검증 → 최종 산출물

**Phase 5: Cleanup**
- `SendMessage`로 종료 요청 → `TeamDelete`
- `_workspace/` 보존 (감사 추적)
- 사용자에게 결과 요약

### Team Reconstitution
Phase별로 다른 전문가 조합이 필요하면, `TeamDelete` → 새 `TeamCreate`. 이전 팀 산출물은 `_workspace/`에 보존.

### Error Handling
| 상황 | 전략 |
|------|------|
| 팀원 1명 실패 | `SendMessage`로 상태 확인 → 재시작 또는 대체 |
| 과반 실패 | 사용자에게 알리고 진행 여부 확인 |
| 타임아웃 | 부분 결과 사용, 미완료 팀원 종료 |
| 데이터 충돌 | 출처 명시 후 병기 (삭제하지 않음) |

---

## Template B: Sub-agent Mode (대안)

팀 통신 오버헤드가 불필요한 경우. `Agent` 도구로 직접 호출, 반환값으로 결과 수집.

### Workflow

**Phase 0: Context Check** (Template A와 동일)

**Phase 1: Preparation**
- 입력 분석, `_workspace/` 생성

**Phase 2: Parallel Execution**
단일 메시지에서 N개 `Agent` 도구 동시 호출:

```
Agent({
  name: "{agent-1}",
  prompt: "{task description}",
  model: "opus",
  run_in_background: true
})
```

**Phase 3: Integration**
- 반환값 수집 + `Read`로 파일 산출물 수집
- 통합 → 최종 산출물

**Phase 4: Cleanup**
- `_workspace/` 보존, 결과 보고

### Error Handling
- 에이전트 1개 실패: 1회 재시도, 재실패 시 누락 명시
- 과반 실패: 사용자에게 보고
- 타임아웃: 부분 결과 사용

---

## Template C: Hybrid Mode (고급)

Phase마다 다른 실행 모드 사용. 각 Phase에 실행 모드 명시.

### Example Configuration
| Phase | 모드 | 이유 |
|-------|------|------|
| Phase 2 (병렬 수집) | Sub-agents | 독립 자료 수집, 통신 불필요 |
| Phase 3 (합의 통합) | Agent Teams | 상충 데이터 토론/합의 필요 |
| Phase 4 (독립 검증) | Sub-agents | QA 에이전트 객관 검증 |

### Mode Transition Rules
- **팀 → 서브**: `TeamDelete` 후 `Agent` 호출
- **서브 → 팀**: 서브 에이전트 파일 산출물을 팀원에게 `Read` 경로로 전달
- **팀 → 팀**: 이전 팀 정리 후 새 `TeamCreate` (세션당 1팀)

---

## Description Keywords (후속 작업 지원)

오케스트레이터 description에 반드시 포함:
- 재실행/다시 실행/업데이트/수정/보완
- "{도메인}의 {부분}만 다시"
- "이전 결과 기반으로", "결과 개선"
- 도메인 관련 일상적 요청

> 후속 키워드가 없으면 첫 실행 후 하네스가 죽은 코드가 된다.

---

## Hook Integration (agent-utils 확장)

팀 라이프사이클에 훅을 연결하여 관찰성 확보:

```json
{
  "hooks": {
    "TeammateIdle": [{
      "matcher": "",
      "hooks": [{"type": "command", "command": "echo 'Teammate idle: check progress'"}],
      "description": "팀원 유휴 시 알림"
    }],
    "TaskCompleted": [{
      "matcher": "",
      "hooks": [{"type": "command", "command": "echo 'Task completed'"}],
      "description": "작업 완료 시 로깅"
    }]
  }
}
```

---

## Writing Principles

1. **실행 모드를 먼저 명시** — 상단에 "에이전트 팀" / "서브 에이전트" / "하이브리드"
2. **팀 모드는 구체성** — TeamCreate/SendMessage/TaskCreate 사용법 구체 기술
3. **서브 모드는 파라미터 완전 명시** — name, subagent_type, prompt, run_in_background, model
4. **파일 경로는 절대적** — `_workspace/` 기준 명확한 경로
5. **Phase 간 의존성 명시** — 어떤 Phase가 어떤 결과에 의존하는지
6. **에러 핸들링은 현실적** — "모든 것이 성공한다" 가정 금지
7. **테스트 시나리오 필수** — 정상 흐름 1개 + 에러 흐름 1개 이상
