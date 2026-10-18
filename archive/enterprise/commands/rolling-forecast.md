---
name: rolling-forecast
description: |
  드라이버 기반 4~6분기 롤링 포캐스트 + variance/DERP 커멘터리(variance=actual−plan 재계산) → 게이트 → QBR 입력.
  Builds a driver-based 4-6 quarter rolling forecast with variance/DERP commentary (variance recomputed as actual − plan) and enforces the variance gate, feeding QBR. Use when: running rolling forecasts and variance analysis.
category: strategy
complexity: advanced
mcp-servers: []
personas: []
---

# /rolling-forecast - 롤링 포캐스트 · 편차 분석

드라이버 기반 4~6분기 롤링 포캐스트를 만들고, 계획 대비 실적의 편차를 variance/DERP 커멘터리로
분석한다. `fpna-planner`(maker)가 작성하고 `gate-variance.sh` 가 **variance = actual − plan 전 라인
재계산**과 임계 초과 라인의 DERP 4키를 검증한다. DERP 정본은 `fpna-planning/references/derp-template.md`.
포캐스트-보상 분리 원칙(sandbagging 방지)을 따른다.

## Triggers
- "롤링 포캐스트", "편차 분석", "variance", "DERP 커멘터리", "QBR 입력" 요청
- 분기 실적 확정 후 계획-실적 관리를 갱신할 때

## Usage
```
/rolling-forecast [옵션]

Options:
  --period <YYYYQn>   대상 분기 지정(variance/<period>.json)
```

## Behavioral Flow

### Phase 0: 입력 수집
- `budget-*.json`(계획)과 실적 수치를 수집. 실적 수치의 **검증**은 finance 소관(입력만 받음).

### Phase 1: fpna-planner 디스패치 (maker)
- 드라이버 트리로 4~6분기 롤링 포캐스트 작성.
- variance 라인: plan·actual(number)·variance(=actual−plan)·variance_pct. 임계(|variance_pct|>threshold_pct)
  초과 라인은 DERP 4키(describe/explain/respond/prevent) 커멘터리 필수.
- → `.planning/enterprise/variance/<period>.json` + 동명 `.md`(서사 커멘터리).

### Phase 2: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-variance.sh"`
- plan/actual number·variance 재계산 일치·임계 초과 라인 DERP 비공백을 검증. 실패 라인 보완 후 재실행.

## Boundaries

**Will:**
- 드라이버 롤링 포캐스트, variance 재계산·DERP 커멘터리, QBR 입력 생성, 게이트 판정

**Will Not:**
- 실적·재무제표·세무 수치 **검증** → finance 위임 (포캐스트는 입력 수치를 신뢰)
- 유닛 레벨 재무 → startup:financial-modeler 위임
- 포캐스트를 인센티브 목표로 전용 (보상 분리 원칙 위반)
