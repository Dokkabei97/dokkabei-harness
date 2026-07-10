---
name: pipeline-audit
description: |
  CRM export(CSV/JSON)를 위생 감사한다 — 메인 세션이 jq 로 정규화해 pipeline/YYYY-MM-DD-audit.json 을 만들고, gate-pipeline-hygiene 가 stage/forecast_category enum·amount>0·open 딜 close_date 미래성·stale 체류일을 결정론 판정한다(대표 쇼케이스 게이트). SaaS CRM API 연동 없이 export 입력만 받는다.
  Audits a CRM export (CSV/JSON): the main session normalizes it with jq into a pipeline audit JSON, and gate-pipeline-hygiene deterministically checks stage/forecast_category enums, amount>0, open-deal close_date futurity, and stale age (the showcase gate). Use when: auditing pipeline hygiene, rolling up forecast categories, cleaning CRM data. Export input only, no SaaS CRM API integration.
category: scaleup
complexity: intermediate
mcp-servers: []
personas: []
---

# /pipeline-audit — 파이프라인 위생 감사

RevOps CRM 위생 룰을 `.planning/scaleup/gtm/pipeline/YYYY-MM-DD-audit.json` 으로 물화하고 결정론 게이트로 검증한다. 전 하네스 최고 결정론 영역 — SaaS API 연동 없이 CSV/JSON export 만 입력받는다.

## Triggers
- 주간/분기 파이프라인 위생 점검
- 포캐스트 카테고리 롤업
- "파이프라인 감사", "CRM 데이터 정리"

## Usage
```
/pipeline-audit <export.csv|export.json> [옵션]
Options:
  --stale-days N   stale_max_days 기준(기본 30)
```

## Behavioral Flow

### Phase 0: 사전 점검
- export 파일 존재 확인. revops-pipeline-schema 스킬의 stage/forecast_category enum(references/pipeline-enums.json)을 정본으로 로드.

### Phase 1: 정규화 (메인 세션, jq)
- export 를 `{audited_at, stale_max_days, deals:[{id, stage, amount, close_date, forecast_category, last_activity}]}` 스키마로 jq 정규화.
- stage/forecast_category 는 enum 값으로 매핑(비표준 값은 정규화 단계에서 교정, 불명은 그대로 두어 게이트가 잡게 함).

### Phase 2: 결정론 게이트
- `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-pipeline-hygiene.sh"`:
  - stage·forecast_category ∈ enum, amount>0 전건
  - open 딜 close_date ≥ TODAY, last_activity 경과 ≤ stale_max_days
  - 위반 딜 id 나열. 정본: scaleup-orchestrator/references/gate-policy.md.

## Examples

```
/pipeline-audit ./crm-export.csv
/pipeline-audit ./deals.json --stale-days 21
```

## Boundaries

**Will:** export 위생 감사·정규화, 포캐스트 롤업, gate-pipeline-hygiene 판정.
**Will Not:**
- SaaS CRM/보드포털 API 직접 연동(export 입력만)
- 실적·매출 수치의 재무 검증 → **finance 위임**
- 딜 자격 판정(→ `/deal-review`)
