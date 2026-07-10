---
name: board-governance
description: |
  보드 거버넌스 가이드 — Sequoia 5블록·Sacks 6섹션 기반 분기 보드덱 표준 헤딩(gate-board-deck 와 동일 문자열 정본)과 Asks 규율(담당·기한)을 정의하고, 일반 거버넌스 전환점(투자 라운드에 따른 이사회 구성, 감사 준비, 이사회 위원회 도입)을 Series A~C 시점에 매핑한다.
  Use when: 보드덱 구조 확인, 이사회 자료 표준화, 거버넌스 전환 시점 판단, /board-deck·/investor-update 작성 시.
  Board-governance guide defining the quarterly board-deck standard headings (the canonical strings for gate-board-deck) and Asks discipline, plus general governance turning points (board formation by round, audit readiness, board committees).
  Use when: standardizing a board deck, or judging governance transitions during Series A-C.
metadata:
  version: 1.0.0
  category: scaleup
---

# Board Governance — 보드·거버넌스 표준

이사회가 5분 안에 상태를 파악하고 Ask 를 결정하게 하는 표준 구조 + 스케일업 거버넌스 전환점.

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

## 거버넌스 전환점 (Series A~C 매핑)

| 전환점 | 기준 | 시점 |
|--------|------|------|
| **이사회 구성** | 창업자 중심 → 정식 이사회(창업자 + 투자자 이사 + 독립 이사), 의결·정족수 규칙 수립 | 시리즈 A 라운드 종료 |
| **감사 준비** | 매출 확대에 따른 재무 통제·연간 외부감사 준비, 회계 정책 정비 | Series B 전후 |
| **이사회 위원회** | 감사위원회·보상위원회 도입, 이사회 안건 표준화 | Series B~C |

> 위 전환점은 **인지·문서 준비 트리거**다. 관할별 회사법·주주간계약(SHA) 조항·M&A 등 **법적 판단은 legal 로 위임**한다. 감사·재무 통제의 수치 검증은 **finance 위임**.

## /investor-update 겸용

투자자 업데이트(`investor/YYYY-MM.md`)는 Wins/Misses/Asks + 현금·런웨이 형식이며, 주주간계약(SHA)상 정보권(정기 재무·사업 보고) 이행 문서를 겸한다.

## Boundaries

**Will:** 덱 표준 헤딩·Asks 규율·KPI 팩 구조 제공, 거버넌스 전환점 매핑.
**Will Not:** 회사법·SHA·M&A 법 판단(→legal), 재무제표·감사 수치 검증(→finance), 덱 대외 배포(사람 승인).
