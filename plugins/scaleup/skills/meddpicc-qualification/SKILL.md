---
name: meddpicc-qualification
description: |
  엔터프라이즈 딜 자격 검증(MEDDPICC) 가이드 — 8요소(Metrics·Economic Buyer·Decision Criteria·Decision Process·Paper Process·Identify Pain·Champion·Competition)의 정의와 status(unknown|identified|verified) 규격을 정의한다. 이 8요소 키·status enum 이 gate-meddpicc.sh 의 계약이며, deal-qualifier 반증(EB 실권·coach vs champion·do-nothing 경쟁) 관점을 포함한다.
  Use when: 딜 MEDDPICC 스코어카드 작성, 8요소 정의 확인, 딜 자격 판정, /deal-review 작성 시.
  Enterprise deal qualification (MEDDPICC) guide defining the 8 elements and their status spec; the element keys and status enum are the gate-meddpicc contract, and it includes deal-qualifier falsification angles.
  Use when: filling a MEDDPICC scorecard, checking the 8-element definitions, or qualifying a deal.
metadata:
  version: 1.0.0
  category: scaleup
---

# MEDDPICC Qualification — 엔터프라이즈 딜 자격

복잡한 B2B 딜의 자격을 8요소로 구조화한다. **8요소 키·status enum 이 gate-meddpicc.sh 의 계약**이다.

## 8요소 (elements 키 — gate 계약)

`meddpicc.json` 의 `elements` 는 아래 **8키를 정확히** 포함한다(더도 덜도 아님):

| 키 | 요소 | 검증 질문 |
|----|------|----------|
| `metrics` | Metrics(정량 가치) | 고객이 합의한 정량 ROI/지표가 있는가 |
| `economic_buyer` | Economic Buyer | 예산 서명권·거부권을 가진 실권자가 식별·접촉됐는가 |
| `decision_criteria` | Decision Criteria | 기술/상업 선정 기준을 알고 그에 맞췄는가 |
| `decision_process` | Decision Process | 결재 단계·일정·관여자를 아는가 |
| `paper_process` | Paper Process | 법무·조달·보안심사·인증 경로를 아는가 |
| `identify_pain` | Identify Pain | 정량화된 고통과 미해결 시 비용이 검증됐는가 |
| `champion` | Champion | 내부에서 나를 위해 싸우는 영향력자가 있는가(coach ≠ champion) |
| `competition` | Competition | 경쟁(타사 + **do-nothing/현상유지**)을 파악했는가 |

## status 규격 (gate 계약)

각 element 는 `{"status": "unknown|identified|verified", "evidence": "…"}`:
- **unknown**: 아직 모름. evidence 비워도 됨.
- **identified**: 파악함(가설). evidence **비공백 필수**.
- **verified**: 증거로 검증됨. evidence **비공백 필수**.
- 게이트 판정: unknown 개수 **≤ 3**, status≠unknown → evidence 비공백, close_date ≥ TODAY.

## deal-qualifier 반증 관점 (verified 과대평가 공격)

deal-qualifier(checker, Edit 미보유)가 반증하는 흔한 과대평가:
1. **EB 착각** — "CFO 미팅"을 실권 증거로 봤으나 예산 서명권 증거 부재 → verified→identified 강등.
2. **coach를 champion으로** — 정보 제공자를 정치적 지지자로 오인.
3. **do-nothing 누락** — 최대 경쟁은 현상유지(예산 미집행)인데 타사만 봄.
4. **paper_process 낙관** — 조달·보안심사가 unknown 인데 close_date 를 낙관.

판정: **COMMIT / DOWNGRADE(필드 강등) / DISQUALIFY**. `gtm/deals/<id>/verdict.json` 으로 물화.

## deal_id·금액·마감

`meddpicc.json` 상위 필드: `deal_id`, `amount`(number), `close_date`(YYYY-MM-DD), `forecast_category`(revops-pipeline-schema enum 과 동일 어휘).

## Boundaries

**Will:** 8요소 정의·status 규격·반증 관점 제공(gate-meddpicc 계약 정본).
**Will Not:** 계약·법무·개인정보 판단(→legal), 시장·경쟁 심층조사(→startup), deal-qualifier 없이 commit 확정.
