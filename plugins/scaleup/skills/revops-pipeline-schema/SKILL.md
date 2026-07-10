---
name: revops-pipeline-schema
description: |
  RevOps 파이프라인 스키마·위생 가이드 — 세일즈 stage 와 forecast_category enum 을 정의하고(references/pipeline-enums.json 이 게이트가 읽는 정본), 위생 룰셋(amount>0·open 딜 close_date 미래성·stale 체류일)을 references/hygiene-rules.md 로 집약한다. gate-pipeline-hygiene.sh 가 이 enum 을 상대경로로 참조하며 하드코딩하지 않는다.
  Use when: 파이프라인 감사 스키마 확인, stage/forecast_category enum 참조, CRM export 정규화, /pipeline-audit 작성 시.
  RevOps pipeline schema and hygiene guide defining the sales stage and forecast_category enums (references/pipeline-enums.json is the source the gate reads) and the hygiene ruleset; gate-pipeline-hygiene reads the enum by relative path rather than hardcoding.
  Use when: normalizing a CRM export, referencing pipeline enums, or auditing pipeline hygiene.
metadata:
  version: 1.0.0
  category: scaleup
---

# RevOps Pipeline Schema — 파이프라인 스키마·위생

파이프라인 감사(`gtm/pipeline/YYYY-MM-DD-audit.json`)의 스키마와 위생 룰. **enum 정본은 [references/pipeline-enums.json](references/pipeline-enums.json)** — gate-pipeline-hygiene.sh 가 상대경로로 읽으므로 게이트·스킬·데이터 파일 3자가 항상 일치해야 한다(값 변경 시 이 문서와 JSON 동기화).

## enum (정본 = references/pipeline-enums.json)

**stage** (세일즈 단계):
`prospecting` → `qualification` → `proposal` → `negotiation` → `closed_won` | `closed_lost`

**forecast_category** (포캐스트 카테고리):
`pipeline` · `best_case` · `commit` · `closed_won` · `closed_lost` · `omitted`

- **open 딜** = forecast_category ∉ {`closed_won`,`closed_lost`}(= pipeline/best_case/commit/omitted). 위생 룰의 close_date·stale 검사는 open 딜에만 적용.

## audit.json 스키마

```json
{
  "audited_at": "YYYY-MM-DD",
  "stale_max_days": 30,
  "deals": [
    {"id","stage","amount_krw":<num>,"close_date":"YYYY-MM-DD","forecast_category","last_activity":"YYYY-MM-DD"}
  ]
}
```

## 위생 룰셋

상세는 [references/hygiene-rules.md](references/hygiene-rules.md). 요약(gate-pipeline-hygiene 계약):
1. stage·forecast_category ∈ enum
2. amount_krw > 0 전건
3. open 딜 close_date ≥ TODAY (마감일 도과 미갱신 = 위생 위반)
4. open 딜 last_activity 경과 ≤ stale_max_days(기본 30)

## 정규화 (jq)

CRM export(CSV/JSON)를 위 스키마로 jq 정규화한다. 비표준 stage/forecast 값은 정규화 단계에서 enum 으로 매핑하고, 매핑 불가 값은 그대로 두어 게이트가 잡게 한다(은폐 금지).

## Boundaries

**Will:** stage/forecast enum·audit 스키마·위생 룰 제공(gate 계약 정본), export 정규화 가이드.
**Will Not:** SaaS CRM API 연동(export 입력만), 매출 수치 재무 검증(→finance), 딜 자격 판정(→meddpicc-qualification/deal-qualifier).
