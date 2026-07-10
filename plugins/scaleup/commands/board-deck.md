---
name: board-deck
description: |
  분기 보드덱(섹션 구조 고정) + 표준 KPI 팩을 작성한다. board-reporter maker 가 Sequoia/Sacks 표준과 board-governance §덱 표준 헤딩으로 작성하고 gate-board-deck 가 필수 헤딩·분기 간 구조 일관성·Asks 담당/기한을 검증한다. 재무 슬라이드 수치는 finance, 법 판단은 legal 위임.
  Authors the quarterly board deck (fixed section structure) and standard KPI pack: board-reporter writes it to Sequoia/Sacks and board-governance deck-standard headings, and gate-board-deck verifies required headings, cross-quarter structural consistency, and Asks owner/date. Use when: preparing a board deck or KPI pack. Financial figures to finance, legal judgments to legal.
category: scaleup
complexity: advanced
---

# /board-deck — 분기 보드덱

Sequoia 5블록 / Sacks 6섹션 표준의 보드덱을 `.planning/scaleup/board/YYYYQn-deck.md` + `kpi-pack.json` 으로 물화한다. `board-reporter` maker 가 작성하고 결정론 게이트가 구조를 검증한다.

## Triggers
- 분기 이사회 준비
- "보드덱 만들어줘", "이사회 자료 준비"

## Usage
```
/board-deck [분기(YYYYQn)]
```

## Behavioral Flow

### Phase 0: 사전 점검
- 최신 OKR·KPI·investor 이력, 전분기 덱(`board/*-deck.md`)을 읽어 구조·델타 기준을 확보.

### Phase 1: board-reporter 디스패치 (maker)
- `board-reporter` 를 호출해 board-governance §덱 표준 H2 헤딩을 **글자 그대로** 사용: `## 실적 요약` / `## KPI 스코어카드` / `## 하이라이트·로우라이트` / `## 재무·런웨이` / `## 전략·OKR 진척` / `## Asks`.
- 헤딩 집합은 분기마다 동일해야 함(구조 일관성). `## Asks` 각 항목은 `담당:` + `기한: YYYY-MM-DD` 짝.
- KPI 팩(`kpi-pack.json`)을 시계열로 갱신. **재무 슬라이드 수치는 "finance 검증 필요" 마킹**.

### Phase 2: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-board-deck.sh"`:
  - 필수 헤딩 전부 존재, 전분기 덱과 H2 목록 일치, Asks 담당/기한 짝.
  - 정본: scaleup-orchestrator/references/gate-policy.md.

## Examples

```
/board-deck 2026Q2
```
- 산출: `board/2026Q2-deck.md` + `board/kpi-pack.json`.

## Boundaries

**Will:** 보드덱·KPI 팩 작성, 표준 헤딩·Asks 규율, gate-board-deck 판정.
**Will Not:**
- 재무제표·실적 수치 정본 검증 → **finance 위임**
- SHA 사전동의·상법 등 법 판단 → **legal 위임**
- 투자자 업데이트(→ `/investor-update`)
- 대외 배포(사람 승인 전제)
