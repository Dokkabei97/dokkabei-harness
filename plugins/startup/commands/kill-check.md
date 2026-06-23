---
name: kill-check
description: "비즈니스 산출물 적대적 검토(kill-gate) — .planning/business/ 산출물의 하중 가정을 식별·공격하고 GO/PIVOT/KILL 판정. 모든 산출물이 'GO'로 수렴하는 확증 편향을 깨기 위한 반대 평형추."
category: strategy
complexity: advanced
mcp-servers: []
personas: []
---

# /kill-check - 비즈니스 가정 적대적 검토

`/lean-canvas`·`/market-research`·`/validate-idea`·`/unit-economics`가 만든 비즈니스 산출물을
**의사결정 전에** 적대적으로 반증한다. 비즈니스 산출물은 거의 항상 "기회 있음(GO)"으로 수렴하므로,
이 커맨드는 "이 사업을 하지 말아야 할 이유"를 찾는 반대 방향의 게이트다. `assumption-killer`
에이전트(maker와 분리된 checker, Edit 미보유)를 디스패치한다.

## Triggers
- 린 캔버스·시장조사·유닛 이코노믹스를 만든 뒤 진짜로 투자/착수할지 결정하기 직전
- `/mvp-from-startup`으로 코드 단계에 들어가기 전, 스코프를 굳히기 전 마지막 점검
- "이 사업 진짜 되는 거 맞아?", "가정 깨봐", "냉정하게 평가해줘" 요청
- 투자 자료(IR)의 시장 규모·유닛 이코노믹스를 외부에 내보내기 전 자체 반증

## Usage
```
/kill-check [옵션]

Options:
  --focus market|economics|wtp|growth   특정 산출물의 가정에 집중
  --verdict-only                        리포트 생략, 판정 1줄만
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/business/` 산출물 존재 확인. 없으면 중단하고 `/lean-canvas <아이디어>` 등 선행 안내.
- 최소 1개 산출물(린 캔버스 권장)이 있어야 동작.

### Phase 1: assumption-killer 디스패치
`assumption-killer` 에이전트를 호출해 네 갈래 반증을 수행:
1. **하중 가정 식별** — 틀리면 사업이 무너지는 1~3개
2. **인용·출처 적대 검증** — `[추정]`·무출처 계수 전수 추출 + WebSearch 1차 재확인
3. **민감도 / 반대 시나리오** — 비관값 재계산으로 결론 뒤집히는 임계점
4. **내적 정합성** — 산출물 간 숫자 충돌

### Phase 2: 판정 보고
- `.planning/business/kill-report.md` 생성.
- GO / PIVOT / KILL 판정 + "가장 위험한 단일 가정" 1줄 + 근거 보고.
- **PIVOT**이면 무엇을 바꿔야 살아남는지(세그먼트·가격·스코프) 구체안 제시.
- **KILL**이면 어느 가정이 재검증에서 무너졌는지 명시.

## Boundaries

**Will:**
- 비즈니스 산출물의 가정을 적대적으로 반증하고 GO/PIVOT/KILL 판정
- 인용 웹 재검증·민감도 재계산으로 근거 있는 판정만 산출
- kill-report.md 작성

**Will Not:**
- 비즈니스 산출물 수정 (assumption-killer는 Edit 미보유)
- 산출물 없이 동작 (→ `/lean-canvas` 등 선행 안내)
- 막연한 비관으로 KILL 남발 — 재현 가능한 근거 필수
