---
name: deal-review
description: |
  엔터프라이즈 딜별 MEDDPICC 스코어카드(8요소)를 생성·갱신하고 deal-qualifier 를 디스패치해 'verified' 과대평가를 반증한다. 메인 세션이 초안을 잡고 deal-qualifier 가 COMMIT/DOWNGRADE/DISQUALIFY 판정을 물화하며 gate-meddpicc --require-verdict 로 검증한다. 계약·법무 판단은 legal 위임.
  Creates/updates the per-deal MEDDPICC scorecard (8 elements) and dispatches deal-qualifier to refute 'verified' overclaims: the main session drafts, deal-qualifier records COMMIT/DOWNGRADE/DISQUALIFY, and gate-meddpicc --require-verdict validates. Use when: reviewing or qualifying an enterprise deal, updating a MEDDPICC scorecard. Contract/legal judgments to legal.
category: scaleup
complexity: advanced
mcp-servers: []
personas: []
---

# /deal-review — 엔터프라이즈 딜 리뷰

딜별 MEDDPICC 스코어카드를 `.planning/scaleup/gtm/deals/<deal-id>/meddpicc.json` 으로 물화하고, `deal-qualifier`(kill-check 의 딜 버전, Edit 미보유)로 반증한다.

## Triggers
- 엔터프라이즈 딜 자격 검증(commit 전)
- MEDDPICC 갱신·딜 리뷰 미팅 준비
- "이 딜 검토해줘", "MEDDPICC 채워줘"

## Usage
```
/deal-review <deal-id> [옵션]
Options:
  --map   gtm/deals/<deal-id>/map.md 관계도(coach/champion/blocker)도 작성
```

## Behavioral Flow

### Phase 0: 사전 점검
- `gtm/deals/<deal-id>/` 존재 여부 확인. 기존 meddpicc.json 있으면 갱신 모드.

### Phase 1: 초안 작성 (메인 세션)
- 8요소(metrics, economic_buyer, decision_criteria, decision_process, paper_process, identify_pain, champion, competition)를 각 `{status: unknown|identified|verified, evidence}` 로 작성.
- `status ≠ unknown` 이면 evidence 비공백. amount·close_date(YYYY-MM-DD)·forecast_category 기록.
- 조달·보안심사·인증 등 규제 관문이 있는 딜이면 관문 마일스톤을 map(decision_process·paper_process)에 표기.

### Phase 2: deal-qualifier 반증
- `deal-qualifier` 디스패치 → COMMIT/DOWNGRADE/DISQUALIFY 판정을 `gtm/deals/<deal-id>/verdict.json` 으로 물화(EB 실권·coach vs champion·do-nothing 경쟁 반증).

### Phase 3: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-meddpicc.sh" --require-verdict`: 8요소 키·status enum·evidence·unknown≤3·close_date≥TODAY + verdict 검증(정본: gate-policy.md).

## Examples

```
/deal-review acme-corp
/deal-review acme-corp --map     # 관계도 동반
```

## Boundaries

**Will:** MEDDPICC 스코어카드 작성·갱신, deal-qualifier 반증, gate-meddpicc 판정.
**Will Not:**
- 계약 조건·법무·개인정보 판단 → **legal 위임**
- 시장조사·경쟁 심층 분석 → **startup 위임**(1차 웹 재확인은 deal-qualifier 내)
- deal-qualifier 없이 딜 commit 확정
