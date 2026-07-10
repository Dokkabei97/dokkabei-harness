---
name: org-plan
description: |
  forward-looking 조직도 + 헤드카운트 플랜을 작성한다. 각 채용을 마일스톤에 연결하고 AOP(연간운영계획) 인건비 예산과 정합시킨다. org-planner maker 가 작성하고 gate-headcount 가 계약을 검증한다. JD·온보딩은 hr, 재무제표는 finance 위임.
  Authors a forward-looking org chart and headcount plan, linking each hire to a milestone and aligning to the AOP personnel budget; org-planner writes it and gate-headcount verifies the contract. Use when: building a headcount plan, planning org scaling, or aligning hiring to budget. JD/onboarding to hr, financials to finance.
category: scaleup
complexity: advanced
mcp-servers: []
personas: []
---

# /org-plan — 조직·헤드카운트 플래닝

SignalFire 조직설계 관점의 forward-looking 조직도와 헤드카운트 플랜을 `.planning/scaleup/org/` 에 물화한다. `org-planner` maker 가 작성하고 결정론 게이트가 검증한다.

## Triggers
- 다음 분기/연도 채용 계획 수립
- AOP(연간운영계획) 인건비 배분 정합
- "헤드카운트 플랜 짜줘", "조직도 그려줘"

## Usage
```
/org-plan [회계연도(YYYY)] [옵션]
Options:
  --against-budget   enterprise/budget-*.json 대비 인건비 정합만 점검
```

## Behavioral Flow

### Phase 0: 사전 점검
- 현 조직 상태(`org/headcount.json` 존재 시)와 `scaleup-master.json` 사이클을 확인.
- `.planning/enterprise/budget-*.json` 존재 여부 확인(정합 크로스체크 대상).

### Phase 1: org-planner 디스패치 (maker)
- `org-planner` 를 호출해 `org/org-chart.md`(span-of-control·리더십 갭)와 `org/headcount.json` 을 작성.
- 각 row 는 `role/dept/level/start_quarter(YYYYQn)/fte/annual_cost_krw`(+milestone). 각 채용을 트리거 마일스톤에 연결.
- 인건비 총액을 budget 의 `personnel_total_krw`(존재 시) ±5% 이내로 정합.

### Phase 2: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-headcount.sh"`:
  - rows 필수 6필드·fte>0·annual_cost_krw>0·start_quarter 형식
  - 인건비-예산 정합(둘 다 존재 시), 10/30/50인 교차 경고
  - 정본: scaleup-orchestrator/references/gate-policy.md.

## Examples

```
/org-plan 2027
/org-plan --against-budget      # 정합만 재점검
```

## Boundaries

**Will:** 조직도·헤드카운트 플랜 작성, 마일스톤 연결, AOP 정합, gate-headcount 판정.
**Will Not:**
- JD·채용 프로세스·온보딩·징계 작성 → **hr 위임**
- 노동법 의무의 법적 이행 판단 → **legal 위임**
- 인건비 세무·재무제표 영향 → **finance 위임**
- 확정 인사 결정(사람 승인 전제)
