---
name: investor-update
description: |
  월간 투자자 업데이트(Wins/Misses/Asks + 현금·런웨이)를 작성한다. 주주간계약(SHA)상 정보권(information rights) 이행 문서를 겸한다 — 정기 재무·사업 보고. board-reporter maker 가 작성하며 게이트는 없다. 계약·법 판단(정보권 범위·사전동의 조항)은 legal 위임, 재무 수치 검증은 finance 위임.
  Authors the monthly investor update (Wins/Misses/Asks plus cash/runway), doubling as the shareholder-agreement information-rights document (periodic financial/business reporting); board-reporter writes it and there is no gate. Use when: writing an investor update or fulfilling investor information rights. Contract/legal interpretation to legal, figure verification to finance.
category: scaleup
complexity: intermediate
mcp-servers: []
personas: []
---

# /investor-update — 투자자 업데이트

Sequoia 형식(Wins/Misses/Asks + 현금·런웨이)의 월간 투자자 업데이트를 `.planning/scaleup/investor/YYYY-MM.md` 로 물화한다. 주주간계약(SHA)상 정보권 이행 문서를 겸한다.

## Triggers
- 매월 투자자 정기 업데이트
- 주주계약 정보권(정기 재무·사업 보고) 이행
- "투자자 업데이트 써줘", "월간 리포트"

## Usage
```
/investor-update [월(YYYY-MM)]
```

## Behavioral Flow

### Phase 0: 사전 점검
- 최신 KPI 팩·OKR·직전 investor 업데이트를 읽어 델타·이월 Ask 를 확보.

### Phase 1: board-reporter 디스패치 (maker)
- `board-reporter` 를 호출해 Wins / Misses / Asks + 현금·런웨이를 작성.
- 정직성 규율: Misses 은폐 금지. 현금·런웨이 수치는 **"finance 검증 필요" 마킹**.
- 톤은 `.planning/business/brand-voice.md`(있으면) 참조만.

### Phase 2: 보고 (게이트 없음)
- 이벤트성 문서라 결정론 게이트를 두지 않는다. 대신 주주계약 정보권 항목(정기 재무·사업 보고) 충족 여부를 체크리스트로 보고.
- **정보권 범위·사전동의 조항 등 계약·법 해석은 legal 로 위임**(문구만 삽입, 판단 금지).

## Examples

```
/investor-update 2026-07
```
- 산출: `investor/2026-07.md`(Wins/Misses/Asks + 현금·런웨이).

## Boundaries

**Will:** 투자자 업데이트 작성, 정보권 항목 체크리스트, 톤 참조.
**Will Not:**
- 주주간계약 사전동의·정보권 범위 등 계약·법 판단 → **legal 위임**
- 재무제표·실적·런웨이 수치 정본 검증 → **finance 위임**
- 보드덱(→ `/board-deck`)
- 대외 발송(사람 승인 전제)
