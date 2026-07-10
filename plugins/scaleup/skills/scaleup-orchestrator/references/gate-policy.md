# Gate Policy — scaleup 게이트 판정 기준 · 산출물 스키마 정본

scaleup 결정론 게이트 6종의 판정 기준과 산출물 스키마를 정의하는 **단일 진실 원천**이다. 커맨드는 이 문서를 참조하고 판정 로직을 중복 기술하지 않는다.

## 공통 규약

| 항목 | 규약 |
|------|------|
| 실행 위치 | `${CLAUDE_PROJECT_DIR:-.}`. `.planning/` 경로는 상대 |
| 호출 | `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-<대상>.sh" [플래그]` |
| exit | `0`=통과 / `1`=실패(stderr `[gate-X] 실패: …` 1줄씩) |
| 경고 | `[gate-X] 경고: …` 는 exit 무영향 |
| 날짜 | `TODAY="${GATE_TODAY:-$(date +%F)}"`, 기한은 YYYY-MM-DD 사전식 비교, 일수는 BSD/GNU date 이중 관용구 |
| 크로스파일 | 양쪽 파일 존재 시에만 실패. 한쪽 부재 시 경고+skip |
| enum | 하드코딩 금지 — references/ 데이터 파일 참조(pipeline-enums.json). |
| 최신 파일 | 파일명 사전식 최대(분기 YYYYQn·주차 YYYY-Www·날짜 YYYY-MM-DD 규약) |

## 산출물 스키마 (게이트가 읽는 최소 필드 = 상한. optional 필드는 무시)

`.planning/scaleup/`:
- `okr/okr-YYYYQn.json`: `{"quarter","objectives":[{"id","title","owner","krs":[{"id","statement","owner","baseline":num,"target":num,"unit","due":"YYYY-MM-DD","confidence":0~1,"score":null|0~1}]}]}` — objectives 1..5, krs 1..4
- `okr/verdict.json`: `{"items":[{"id":"<KR id>","verdict":"ADOPT|REWRITE|DROP","reason"}],"coverage":["…"],"riskiest"}` — coverage 비공백
- `checkins/YYYY-Www.md`: frontmatter `date: YYYY-MM-DD` + `## 스코어카드` 섹션(지표 5~15)
- `score/YYYYQn-retro.md`, `scaleup-master.json`({status,현재 분기,완료 단계})
- `org/headcount.json`: `{"fiscal_year","current_fte","rows":[{"role","dept","level","start_quarter":"YYYYQn","fte":num,"annual_cost_krw":num,"milestone"}]}`
- `org/stage-verdict.json`: verdict ∈ {ADVANCE,HOLD,NOT-YET}
- `board/YYYYQn-deck.md`(§덱 표준 헤딩) + `board/kpi-pack.json`, `investor/YYYY-MM.md`
- `gtm/deals/<id>/meddpicc.json`: `{"deal_id","amount_krw":num,"close_date":"YYYY-MM-DD","forecast_category","elements":{8키: metrics,economic_buyer,decision_criteria,decision_process,paper_process,identify_pain,champion,competition — 각 {"status":"unknown|identified|verified","evidence"}}}`
- `gtm/deals/<id>/verdict.json`: verdict ∈ {COMMIT,DOWNGRADE,DISQUALIFY}
- `gtm/pipeline/YYYY-MM-DD-audit.json`: `{"audited_at","stale_max_days":num,"deals":[{"id","stage","amount_krw":num,"close_date","forecast_category","last_activity"}]}`

크로스파일: `.planning/enterprise/budget-*.json`(enterprise 소유)의 `personnel_total_krw` — 존재 시에만 gate-headcount 가 참조.

## gate-okr.sh [--scored] [--require-verdict]

최신 `okr/okr-*.json` 대상. 통과 조건:
1. objectives 1..5 배열, 각 objective 의 krs 1..4
2. objective.owner 비공백, 각 KR statement/owner 비공백
3. KR baseline·target 은 number, due 는 `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`
4. id 중복 0 (objective id + KR id 전역 유일)
- `--scored`: 전 KR `score` 가 0..1 number
- `--require-verdict`: `okr/verdict.json` 존재 + coverage 비공백 + 전 items verdict ∈ {ADOPT,REWRITE,DROP} + items 가 전 KR id 커버 + **non-ADOPT(REWRITE/DROP) 1건 이상 → 실패**(항목 나열)

## gate-cadence.sh

최신 `checkins/*.md` 대상(jq 불요). 통과 조건:
1. frontmatter `date: YYYY-MM-DD` 추출 성공
2. (TODAY − date) ≤ 7일
3. `## 스코어카드` 헤딩 존재
- 지표 5~15개 범위 밖 → 경고만(EOS Scorecard/4DX)

## gate-headcount.sh

`org/headcount.json` 대상. 통과 조건:
1. rows 각 항목 필수 6필드(role,dept,level,start_quarter,fte,annual_cost_krw)
2. fte>0, annual_cost_krw>0(number), start_quarter `^[0-9]{4}Q[1-4]$`
3. 크로스파일: `enterprise/budget-*.json` + `personnel_total_krw` 존재 시 `|Σannual_cost − pt| / pt > 0.05 → 실패`
- 분기 누적 FTE(current_fte 기반)가 10/30/50인 교차 → 경고(취업규칙/노사협의회/산안위 — 대응 legal/hr 위임)

## gate-board-deck.sh

최신 `board/*-deck.md` 대상(jq 불요). 통과 조건:
1. 필수 H2 헤딩 전부 존재(§덱 표준 — board-governance 스킬과 동일 문자열): `## 실적 요약` / `## KPI 스코어카드` / `## 하이라이트·로우라이트` / `## 재무·런웨이` / `## 전략·OKR 진척` / `## Asks`
2. 전분기 덱 존재 시 `^## ` 헤딩 목록 diff == 0
3. `## Asks` 각 항목 `담당:` 개수 == `기한: YYYY-MM-DD` 개수, ≥ 1

## gate-meddpicc.sh [--require-verdict]

`gtm/deals/*/meddpicc.json` 전 딜 대상. 통과 조건:
1. elements 키 집합 == 8요소 정확히
2. 각 element status ∈ {unknown,identified,verified}
3. status ≠ unknown → evidence 비공백
4. unknown 개수 ≤ 3
5. close_date ≥ TODAY
- `--require-verdict`: 딜 디렉토리 `verdict.json` 존재 + coverage 비공백 + verdict ∈ {COMMIT,DOWNGRADE,DISQUALIFY}

## gate-pipeline-hygiene.sh (대표 쇼케이스)

최신 `gtm/pipeline/*-audit.json` 대상. enum 정본: `../../skills/revops-pipeline-schema/references/pipeline-enums.json`. 통과 조건:
1. 전 딜 stage ∈ enum, forecast_category ∈ enum
2. amount_krw > 0 전건
3. open 딜(forecast_category ∉ {closed_won,closed_lost}) close_date ≥ TODAY
4. open 딜 last_activity 경과 ≤ stale_max_days(기본 30) — 위반 딜 id 나열

## 회귀 테스트

게이트 수정 시 `tests/hooks/scaleup-gates.bats` 동반 갱신(게이트별 정상/위반/날짜/verdict/크로스파일/jq 부재 케이스). 날짜 케이스는 `export GATE_TODAY=YYYY-MM-DD` 주입으로 결정론화.
