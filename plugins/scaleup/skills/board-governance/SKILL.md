---
name: board-governance
description: |
  보드 거버넌스 가이드 — Sequoia 5블록·Sacks 6섹션 기반 분기 보드덱 표준 헤딩(gate-board-deck 와 동일 문자열 정본)과 Asks 규율(담당·기한)을 정의하고, 한국 거버넌스 전환점(자본금 10억 미만 특례 종료 시 이사 3인 이사회+감사 전환, 외감 기준 자산·매출 500억, RCPS/SHA 정기보고 의무)을 Series A~B 시점에 매핑한다.
  Use when: 보드덱 구조 확인, 이사회 자료 표준화, 한국 거버넌스 전환 시점 판단, /board-deck·/investor-update 작성 시.
  Board-governance guide defining the quarterly board-deck standard headings (the canonical strings for gate-board-deck) and Asks discipline, plus Korean governance turning points (board formation, external-audit thresholds, RCPS/SHA periodic reporting).
  Use when: standardizing a board deck, or judging Korean governance transitions during Series A-B.
metadata:
  version: 1.0.0
  category: scaleup
---

# Board Governance — 보드·거버넌스 표준

이사회가 5분 안에 상태를 파악하고 Ask 를 결정하게 하는 표준 구조 + 한국 거버넌스 전환점.

## §덱 표준 (gate-board-deck 계약 — 아래 헤딩 문자열이 정본)

분기 보드덱(`board/YYYYQn-deck.md`)은 아래 H2 헤딩을 **글자 그대로** 포함하며, 헤딩 집합은 **분기마다 동일**해야 한다(gate-board-deck 이 전분기 덱과 diff 검사):

```
## 실적 요약
## KPI 스코어카드
## 하이라이트·로우라이트
## 재무·런웨이
## 전략·OKR 진척
## Asks
```

- Sequoia 5블록(비즈니스·재무·제품·팀·Ask)과 Sacks 6섹션을 이 6헤딩으로 통합.
- **`## Asks` 규율**: 각 Ask 는 `담당: <이름>` + `기한: YYYY-MM-DD` 를 짝으로 명시(gate-board-deck 이 개수 일치 검사).
- **`## 재무·런웨이`**: 구조·서사는 board-reporter 가 작성하되 수치 검증은 **finance 위임**("finance 검증 필요" 마킹).

## KPI 팩

`board/kpi-pack.json` — 분기 고정 지표(ARR·NRR·Gross Margin·번레이트·런웨이·파이프라인·헤드카운트)를 시계열로. 덱의 `## KPI 스코어카드` 가 이를 렌더.

## 한국 거버넌스 전환점 (Series A~B 매핑)

| 전환점 | 기준 | 시점 |
|--------|------|------|
| **이사회 구성** | 자본금 10억원 미만 특례 종료 → 이사 3인 이사회 + 감사 전환(1인/2인 이사 불가) | 자본 확충·투자 유치 라운드 |
| **외부감사 대상** | 자산·매출 500억 등 (4지표 중 2 충족), 감사인 45일 내 선임 | Series B 전후 |
| **RCPS/SHA 정기보고** | 상환전환우선주·주주간계약상 월 재무·분기 사업보고 의무 | 투자 유치 직후부터 |

> 위 전환점은 **인지·문서 준비 트리거**다. 상법·SHA 사전동의권·기업결합 등 **법적 판단은 legal 로 위임**한다. 외감 대상 판정의 재무 수치는 **finance 위임**.

## /investor-update 겸용

투자자 업데이트(`investor/YYYY-MM.md`)는 Wins/Misses/Asks + 현금·런웨이 형식이며, RCPS/SHA 계약상 정기보고 이행 문서를 겸한다.

## Boundaries

**Will:** 덱 표준 헤딩·Asks 규율·KPI 팩 구조 제공, 한국 거버넌스 전환점 매핑.
**Will Not:** 상법·SHA·기업결합 법 판단(→legal), 재무제표·외감 수치 검증(→finance), 덱 대외 배포(사람 승인).
