---
name: annual-plan
description: |
  한국 4Q 경영계획 재현 — CEO 대원칙·수립지침 → 부서안 → budget.json(CLAP 5요소·시나리오·Σ부서=전사) → plan-challenger 반증 → 게이트.
  Reproduces the Korean 4Q annual-planning season — CEO principles/guidelines → department plans → budget.json (CLAP, scenarios, dept sum = org total) — with plan-challenger falsification and the budget gate. Use when: building the corporate annual plan/budget.
category: strategy
complexity: advanced
mcp-servers: []
personas: []
---

# /annual-plan - 경영계획 · 전사 예산

한국형 4Q 경영계획 시즌을 재현한다. CEO 대원칙·수립지침을 CLAP 5요소로 구조화하고 부서안을 전사로
합산해 `budget-*.json` 을 만든다. `fpna-planner`(maker) → `plan-challenger`(checker) → `gate-budget.sh`
(최강 산술 게이트: Σ부서=전사±0.5%·시나리오·CLAP·assumptions). 정본은 `fpna-planning`(clap-keys.json).

## Triggers
- "경영계획", "연간 예산", "4Q 계획 시즌", "수립지침", "CLAP" 요청
- `/strategy-cascade` 대원칙을 예산으로 전환할 때

## Usage
```
/annual-plan [옵션]

Options:
  --fy <year>   회계연도 지정(budget-<year>.json)
```

## Behavioral Flow

### Phase 0: 대원칙 수집
- CEO 경영방침·도전 목표·자원 배분 원칙을 수집. `strategy-cascade.md` 있으면 톤·대원칙 승계.

### Phase 1: fpna-planner 디스패치 (maker)
- CLAP 5요소(challenge/levers/allocation/assumptions/plan — clap-keys.json 정본)로 수립지침 구조화.
- 부서안 합산: **Σ부서 total_krw = org_total_krw (±0.5%)**, scenarios{base,best,worst} (worst≤base≤best),
  assumptions≥3(드라이버 연결). → `.planning/enterprise/budget-<fy>.json`.

### Phase 2: plan-challenger 디스패치 (checker)
- hockey-stick 예산·sandbagging 을 반증 → verdict.json(산술은 게이트가 선처리).

### Phase 3: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-budget.sh"`
- Σ부서=전사(±0.5%)·시나리오 순서·CLAP 키/값·assumptions≥3 을 검증. 실패 해소 후 재실행.

## Boundaries

**Will:**
- 4Q 경영계획·CLAP 예산·부서 합산·시나리오 작성, 반증, 산술 게이트 판정

**Will Not:**
- 유닛 이코노믹스(CAC/LTV/번레이트) → startup:financial-modeler 위임 (본 커맨드는 전사 레벨)
- 재무제표·세무·실적 수치 검증 → finance 위임
- CLAP 키를 정본 무시하고 임의 명명 (게이트 실패)
