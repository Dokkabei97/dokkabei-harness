---
name: observe-report
description: "Harness health report from skill-trace telemetry — aggregates real usage (skill/agent calls, user vs model triggers, completion, unused assets, no-activation candidate turns), then interprets results into improvement proposals: description tuning drafts, deprecation candidates, and measurement-quality fixes. Proposals only — never edits files."
category: utility
complexity: intermediate
mcp-servers: []
personas: []
---

# /observe-report - 계측 기반 하네스 건강 리포트

## Triggers
- 하네스(스킬·커맨드·에이전트)가 실제로 잘 호출되고 잘 사용되는지 계측 결과로 점검하고 싶을 때
- "하네스 리포트", "스킬 사용 현황", "계측 결과 보여줘", "안 쓰는 스킬 찾아줘" 요청 시
- 스킬 description 튜닝·사장 자산 정리 등 하네스 개선 의사결정의 근거가 필요할 때
- OBSERVE_TRACE 수집을 켠 뒤 일정 기간이 지나 축적된 트레이스를 해석하고 싶을 때

## Usage
```
/observe-report [options]

Options:
  --raw               결정론 집계 JSON만 출력하고 해석(Phase 3~4)은 생략
  --window <days>     최근 N일 레코드만 집계 (기본 전체)
  --focus <area>      해석 초점: skills | agents | prompts (기본 전체)
```

## Behavioral Flow

전 과정은 "결정론 집계(스크립트) → 해석(LLM) → 제안(승인 전 제안서까지만)"의 경계를 지킨다.
비용/토큰 계측은 내장 OTel(CLAUDE_CODE_ENABLE_TELEMETRY) 위임, 발화율 사전 벤치마크는
skill-creator eval 소관 — 이 커맨드는 **실사용 텔레메트리의 사후 진단** 전용이다.

### Phase 1: 수집 상태 점검
1. **집계 실행**: `node ${CLAUDE_PLUGIN_ROOT}/bin/observe-report.js --json` (옵션 `--window` 전달).
   `${CLAUDE_PLUGIN_ROOT}` 미치환 환경이면 저장소의 `plugins/observe/bin/observe-report.js` 폴백
2. **가용성 판정**: `meta.trace_missing`이면 계측이 꺼진 상태 — OBSERVE_TRACE=1 활성화 방법
   (셸 프로필 또는 settings.json `env`)과 재수집 후 재실행 안내를 출력하고 **종료**
3. **분모 검증**: `meta.plugins_dir`이 마켓플레이스 루트인지 확인. 특정 플러그인 하나의 설치
   루트(예: `.../cache/<마켓>/observe/1.1.0`)로 잡혀 `inventory.plugins`가 1로 붕괴하면 커버리지
   분석이 "unused 없음"이라는 잘못된 안심을 준다(실측 2026-07) — 집계기가 버전 레이아웃을 상향
   인식하지만, 의심스러우면 `--plugins-dir <마켓 캐시 루트 또는 레포 plugins/>`로 명시 오버라이드
4. **표본 적정성**: 레코드 수·세션 수·기간을 보고하고, 표본이 작으면(세션 < 5) 이후 해석에
   "표본 부족 — 경향 참고용" 경고를 달아 과잉 일반화를 방지

### Phase 2: 결정론 집계 보고
집계 JSON을 요약 표로 제시한다 (`--raw`면 여기서 JSON 출력 후 종료).
1. **호출 현황**: 스킬/커맨드/에이전트별 호출수·user/model 트리거 비율·완주율·평균 소요시간
2. **커버리지**: 인벤토리(트레이스와 동일 설치 루트에서 열거) 대비 미사용 스킬/커맨드/에이전트 수
3. **계측 품질**: parse_errors, trigger null 비율, why 커버리지, 인벤토리 밖 호출(unknown_called)

### Phase 3: 해석 (LLM 판정)
집계가 제공한 후보를 판정한다 — 집계 스크립트는 후보 추출까지, 판정은 여기서만.
1. **미발화 판정**: `candidates`(스킬/에이전트 무동작 턴)의 프롬프트를 인벤토리 스킬
   description(SKILL.md frontmatter)과 대조해 "놓친 발화"(적합 스킬이 있었는데 미호출) vs
   "스킬 불필요"(해당 없음)로 분류. 놓친 발화는 어떤 스킬이 왜 매칭됐어야 하는지 근거 명시
2. **user-only 스킬 진단**: 호출 전부가 trigger=user인 스킬 — 모델이 자율 선택하지 못하는
   description 발견가능성 문제의 신호. why 코퍼스와 대조해 원인 가설 제시
3. **미사용 자산 분류**: 신생(추가된 지 얼마 안 됨 — git log 참조) / 중복(유사 스킬이 흡수) /
   사장(용도 소멸) 3분류. 분류 근거로 해당 SKILL.md description을 직접 읽어 인용
4. **오귀속·품질 이슈**: unknown_called, trigger null 급증, 완주율 낮은 스킬(호출 후 result
   부재) 등 계측 자체의 개선점. 단 unknown_called는 **인벤토리 밖 호출**의 총칭이다 —
   번들 스킬(claude-in-chrome, update-config 등)·타 마켓플레이스 스킬이 정상적으로 여기 잡히므로,
   네임스페이스 드리프트·개명 흔적으로 판정하려면 이름이 인벤토리의 기존 자산과 유사한지 먼저 대조하라
5. **교차 검증(선택)**: 로컬 OTel 스택(`infra/otel`)이 떠 있으면 내장 OTel의 `skill_activated`
   이벤트와 맞대본다 — observe와 `session_id`/`prompt_id`가 동일 값이라 그대로 join된다.
   observe에 없는데 Loki에 있는 호출은 헤드리스 user-slash(계측 경계, README 참고)거나 훅 미발화
   신호다. 조회: `{service_name="claude-code"} | event_name="skill_activated"`

### Phase 4: 개선 제안 라우팅
판정 결과를 유형별 제안서로 산출한다 — **파일은 일절 수정하지 않는다** (retro (c)형 계약).

| 유형 | 신호 | 제안 형식 |
|------|------|----------|
| **(a) description 튜닝** | 놓친 발화 반복, user-only 스킬 | 대상 SKILL.md 경로 + 현재 description + 수정안 + 근거 턴 인용. 적용 후 검증은 skill-creator eval 권고 |
| **(b) 사장 자산 정리** | 미사용 + 사장 분류 | `workflow:deprecation-guide` 절차로 넘길 후보 목록 |
| **(c) 하네스 구조** | 미발화가 스킬 부재 때문(기존 스킬로 커버 불가) | 신규 스킬/훅 후보 메모 — 스캐폴딩은 `harness:create-flow` 소관, 여기서는 후보 식별까지 |
| **(d) 계측 개선** | trigger null·조인 실패·표본 편향 | observe 플러그인 자체 개선 항목 (훅 버그는 플래그만 — 무단 수정 금지 원칙) |

### Phase 5: 보고
하네스 건강 요약(호출 집중도·커버리지·발화 정확도·계측 품질)과 제안 목록을 표로 제시하고,
제안 적용은 사용자 승인 후 별도 작업임을 명시한다. 표본이 부족했다면 재실행 주기를 함께
안내한다 — 통상 2주 뒤 `/observe-report --window 14`가 적절하며, 정기 실행은 전용 하네스를
만들지 말고 기존 `/loop`·`/schedule`을 재사용한다(하네스 신설은 반복이 입증된 뒤에).

## Tool Coordination
- **Bash**: `node ${CLAUDE_PLUGIN_ROOT}/bin/observe-report.js --json [--window N]` — 결정론 집계 (유일한 실행)
- **Read**: 판정 대상 SKILL.md·커맨드 md의 frontmatter description — 미발화 judge·미사용 분류 근거
- **Glob**: 인벤토리 경로 확인 보조 (`plugins/*/skills/*/SKILL.md`)
- **Grep**: why 코퍼스에서 특정 스킬 언급 탐색 — user-only 원인 가설 보강

## Examples

### 기본 리포트
```
/observe-report
# 집계 → 해석 → 제안까지 전체 흐름. 트레이스 없으면 OBSERVE_TRACE 활성화 안내 후 종료
```

### 최근 2주만, 집계만
```
/observe-report --raw --window 14
# 최근 14일 결정론 집계 JSON만 출력 — 해석·제안 생략 (외부 도구 연계용)
```

### 스킬 발화 정확도에 집중
```
/observe-report --focus skills
# 미발화 판정과 user-only 스킬 진단 중심으로 해석 — 에이전트/프롬프트 절은 요약만
```

## Boundaries

**Will:**
- observe-report.js 결정론 집계를 실행하고 결과를 해석 가능한 표로 보고
- 미발화 후보를 스킬 description과 대조해 "놓친 발화" vs "스킬 불필요"로 판정
- description 튜닝 제안서·사장 자산 후보·신규 스킬 후보·계측 개선 항목을 산출
- 표본 부족·트레이스 부재를 명시하고 과잉 일반화를 방지

**Will Not:**
- SKILL.md·커맨드·훅 등 어떤 파일도 수정하지 않음 — 제안서 산출까지만 (적용은 사용자 승인 후 별도 작업)
- 비용/토큰/tool_decision 계측을 재구현하지 않음 — 내장 OTel(CLAUDE_CODE_ENABLE_TELEMETRY) 위임
- 발화율 사전 벤치마크(트리거/비트리거 쿼리 eval)를 수행하지 않음 — skill-creator eval 소관
- OBSERVE_TRACE를 자동 활성화하지 않음 — 프롬프트 원문이 기록되는 opt-in은 사용자 결정
- 훅 로직 버그를 직접 수정하지 않음 — 플래그 후 별도 결정 (저장소 원칙)

## Related
- `observe` 훅 6종 (trace-prompt/skill/agent/result/session) — 이 리포트의 데이터 생산자
- `workflow:deprecation-guide` — (b) 사장 자산 후보의 폐기 절차 소관
- `harness:create-flow` — (c) 신규 스킬/훅 후보의 스캐폴딩 소관
- `workflow:retro` — 세션 일화 기반 교훈 라우팅 (본 커맨드의 데이터 기반 보완재)
- `skill-creator:skill-creator` eval — description 수정안의 사전 발화율 검증 경로
