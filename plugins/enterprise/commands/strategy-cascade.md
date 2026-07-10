---
name: strategy-cascade
description: |
  Playing to Win 5선택 1페이저 + Three Horizons 포트폴리오 태그 + 7S 사전 진단 → plan-challenger 반증(게이트 없음).
  Writes a Playing to Win 5-choice one-pager with a Three Horizons portfolio tagging and a 7S pre-diagnosis, then runs plan-challenger falsification (no deterministic gate). Use when: setting or refreshing corporate strategy direction.
category: strategy
complexity: advanced
mcp-servers: []
personas: []
---

# /strategy-cascade - 전사 전략 캐스케이드

Lafley/Martin Playing to Win 5선택을 논리 연쇄로 작성하고, Three Horizons(H1/H2/H3) 포트폴리오 태그와
7S 사전 진단을 붙인다. `strategy-analyst`(maker) 초안 → `plan-challenger`(checker, Edit 미보유) 반증.
**게이트 없음**(서사형 산출물) — 대신 반증 리포트가 품질 관문이다. 프레임워크는 `strategy-frameworks`.

## Triggers
- "전략 방향", "Playing to Win", "Three Horizons 포트폴리오", "전사 전략 1페이저" 요청
- `/annual-plan` 앞단에서 전략 대원칙을 세울 때

## Usage
```
/strategy-cascade [옵션]

Options:
  --horizon-only   3H 포트폴리오 태깅만(전체 캐스케이드 생략)
```

## Behavioral Flow

### Phase 0: 입력 수집
- 사업 현황·경쟁·역량을 수집. `.planning/scaleup/`(OKR 이력·kpi-pack)이 있으면 초안 시드로 승계.

### Phase 1: strategy-analyst 디스패치 (maker)
- Playing to Win 5선택(aspiration→where→how→capabilities→systems)을 **논리 연쇄**로 작성.
- Three Horizons 로 사업을 태깅(core/emerging/option), 7S 정합 진단.
- → `.planning/enterprise/strategy-cascade.md` + `portfolio.json`(H1/H2/H3 태그).

### Phase 2: plan-challenger 디스패치 (checker)
- 캐스케이드 논리 단절(where↔how 불일치), one-box/three-box truncation 을 반증 → verdict.json.
- **게이트가 없으므로** 반증 리포트의 REBASELINE/REJECT 를 사람이 검토해 반영한다.

## Boundaries

**Will:**
- PtW/3H/7S 캐스케이드 작성(maker), 논리 단절·편중 반증(checker)

**Will Not:**
- 실적·세무·세제 수치 → finance 위임
- 시장조사·유닛이코노믹스 재생성 → startup 위임
- 캐스케이드를 checker 가 수정 (plan-challenger Edit 미보유)
- 산술 게이트 강제 (서사형 — 반증이 관문)
