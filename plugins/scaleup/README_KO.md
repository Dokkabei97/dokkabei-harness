> [English](README.md) · **한국어**

# scaleup

> Series A~C 스케일업의 실행 OS — OKR 케이던스·조직 스케일링·보드/투자자 보고·엔터프라이즈 딜 검증을 파일 계약 + 결정론 게이트로 물화한다.

## 개요

`scaleup` 은 스케일업의 **실행**을 다룬다(아이디어 검증은 `startup`). 분기 OKR 사이클·이벤트성 조직/보드·딜 단위 GTM 3계열로 일을 구조화하고, 모든 산출물을 `.planning/scaleup/` 파일로 물화한다 — 상태(사이클 상태·KR·KPI)를 세션 기억이 아니라 파일이 보장한다는 설계 원칙을 따른다.

핵심은 **maker/checker 분리 + 결정론 게이트**다. maker 가 초안을 만들고(OKR 트리·조직 플랜·보드덱·MEDDPICC), checker 는 **의도적으로 Edit 를 보유하지 않은 채** 반증해 verdict.json 으로 판정을 물화하며, 결정론 게이트(`exit 0/1`)가 계약을 재검한다. "통과 판정은 모델이 아니라 하네스가 한다." 대외 산출물(OKR·보드덱·딜 커밋)은 항상 사람 승인 전제.

경계는 명시적이다: 재무제표·세무 → `finance`, 법 판단(상법·SHA 사전동의·기업결합·공익신고) → `legal`, JD·온보딩 → `hr`, 시장조사·유닛이코노믹스·콘텐츠 → `startup`, GRC·전사 경영계획·M&A 스크리닝 → `enterprise`.

## 컴포넌트

### 커맨드 (10)

- `/okr-plan` — 분기 OKR 트리(objectives 1~5·KR 1~4, owner·baseline·target·기한). 초안 → okr-checker 반증 → 사람 승인 3단.
- `/okr-checkin` — 주간 체크인: KR별 confidence·블로커·차주 커밋 + 5~15 지표 스코어카드.
- `/okr-score` — 분기말 스코어링(0.0~1.0) + 회고 → 차기 `/okr-plan` 입력.
- `/stage-check` — Blitzscaling 5단계 진단 + 한국 인원 임계값(10/30/50인) 산술 플래그, scale-checker 반증.
- `/org-plan` — forward-looking 조직도 + 헤드카운트 플랜(AOP 정합), org-planner.
- `/board-deck` — 분기 보드덱(섹션 고정) + 표준 KPI 팩, board-reporter.
- `/investor-update` — 월간 Wins/Misses/Asks + 현금·런웨이. RCPS/SHA 정기보고 문서 겸용.
- `/deal-review` — 딜별 MEDDPICC 스코어카드, deal-qualifier 반증.
- `/pipeline-audit` — CRM export 위생 감사 + 포캐스트 롤업(대표 결정론 게이트).
- `/scaleup-from-startup` — `.planning/business/` 산출물을 사이클로 승계하는 브릿지.

### 에이전트 (5)

- `org-planner`(maker) — 조직도·헤드카운트 플랜, 마일스톤 연결, AOP 정합.
- `board-reporter`(maker) — 보드덱·KPI 팩·투자자 업데이트(Sequoia/Sacks 표준).
- `okr-checker`(checker, Edit 미보유) — KR task 위장 output 반증, ADOPT/REWRITE/DROP.
- `deal-qualifier`(checker, Edit 미보유) — MEDDPICC verified 과대평가 반증, COMMIT/DOWNGRADE/DISQUALIFY.
- `scale-checker`(checker, Edit 미보유) — 조기 단계 전환 반증, ADVANCE/HOLD/NOT-YET.

### 스킬 (6)

- `scaleup-orchestrator` — 3계열 마스터 라우터(+ `references/gate-policy.md` 게이트 판정·스키마 정본).
- `operating-cadence` — OKR/EOS/4DX 비교·미팅 리듬·'주간 세션 생략 시 2사이클 내 붕괴' 경고.
- `board-governance` — 덱 표준 헤딩(gate-board-deck 동일 문자열 정본) + 한국 거버넌스 전환점.
- `meddpicc-qualification` — 8요소 정의·status 규격(= gate-meddpicc 계약).
- `revops-pipeline-schema` — stage/forecast_category enum(+ 게이트가 읽는 `references/pipeline-enums.json`, `references/hygiene-rules.md`).
- `korea-b2b-procurement` — CSAP/BMT/나라장터·협상계약(기술 90:가격 10)·85% 컷.

### 게이트 (6, 결정론 `exit 0/1`)

`gate-okr.sh`(`--scored`/`--require-verdict`) · `gate-cadence.sh` · `gate-headcount.sh` · `gate-board-deck.sh` · `gate-meddpicc.sh`(`--require-verdict`) · `gate-pipeline-hygiene.sh`(쇼케이스). 회귀 테스트: `tests/hooks/scaleup-gates.bats`.

## 산출물 계약 (`.planning/scaleup/`)

```
scaleup-master.json                 # 사이클 상태
okr/okr-YYYYQn.json, okr/verdict.json
checkins/YYYY-Www.md, score/YYYYQn-retro.md
org/headcount.json, org/stage-verdict.json
board/YYYYQn-deck.md, board/kpi-pack.json, investor/YYYY-MM.md
gtm/deals/<id>/meddpicc.json + verdict.json
gtm/pipeline/YYYY-MM-DD-audit.json
```

파일명은 분기 `YYYYQn` / 주차 `YYYY-Www` / 날짜 `YYYY-MM-DD` 규약을 따라 게이트가 파일명만으로 날짜 산술을 할 수 있게 한다.

## 사용 흐름

- **신규 사이클**: `/scaleup-from-startup`(business 존재 시) → `/okr-plan` → 주간 `/okr-checkin` → `/okr-score`.
- **조직**: `/stage-check` → `/org-plan`(`enterprise/budget-*.json` 존재 시 정합).
- **보드/투자자**: 분기 `/board-deck`, 월간 `/investor-update`.
- **엔터프라이즈 GTM**: 딜별 `/deal-review <deal-id>`, 주간 `/pipeline-audit <export>`.

## 위임 경계

- **finance** — 재무제표·세무·실적/수치 검증(보드 재무·인건비).
- **legal** — 상법·SHA 사전동의·기업결합신고·공익신고·개인정보 판단.
- **hr** — JD·온보딩·징계 조항.
- **startup** — 시장조사·유닛이코노믹스·콘텐츠·브랜드보이스(브릿지로 읽기 승계만).
- **enterprise** — GRC·전사 경영계획·M&A 스크리닝(`budget-*.json` 은 enterprise 소유, scaleup 은 존재 시 읽기만).

## 비고

- SaaS CRM/보드포털 API 연동 없음 — CSV/JSON export 입력만.
- checker 는 설계상 Edit 미보유로 산출물을 고쳐 통과시키는 경로를 차단하며, Write 는 verdict.json 에만 한정한다.
