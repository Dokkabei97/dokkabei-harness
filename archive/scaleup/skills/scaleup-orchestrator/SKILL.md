---
name: scaleup-orchestrator
description: |
  Series A~C 스케일업 실행 OS 오케스트레이터. OKR 케이던스(분기 플랜→주간 체크인→분기말 스코어링), 조직 스케일링, 보드·투자자 보고, 엔터프라이즈 딜 검증(MEDDPICC)·파이프라인 위생을 파일 계약 + 결정론 게이트 + maker/checker 분리로 물화한다. 3계열(분기 OKR 사이클·이벤트성 조직/보드·딜 단위 GTM)을 라우팅한다.
  Use when: "OKR 세팅", "보드덱", "헤드카운트 플랜", "딜 검증", "파이프라인 감사", /okr-plan·/board-deck·/deal-review 실행, Series A~C 스케일업 실행 관리 시. 기존 코드베이스 기능 작업에는 미발동.
  Orchestrator of the Series A-C scale-up execution OS: routes OKR cadence, org scaling, board/investor reporting, and enterprise deal qualification through file contracts, deterministic gates, and maker/checker separation.
  Use when: managing OKR cadence, org scaling, board reporting, or enterprise deal qualification; on /okr-plan, /board-deck, /deal-review, /pipeline-audit. Not for single-feature code work.
metadata:
  version: 1.0.0
  category: scaleup
---

# Scaleup Orchestrator — 스케일업 실행 OS

Series A~C 스케일업의 실행을 게이트 기반 파이프라인으로 완주시키는 오케스트레이터. `.planning/scaleup/` 파일이 상태를 보장하고(compaction 의존 금지), 각 단계의 maker/checker 를 전문 에이전트에게 위임하며, 판정은 결정론 게이트(exit 0/1)가 한다.

핵심 명제: **"완료·통과 판정은 모델이 아니라 하네스(게이트+마커)가 한다."** 대외 산출물(OKR·보드덱·딜 커밋)은 항상 사람 승인 전제.

## When to Apply

**발동:** OKR 플래닝/체크인/스코어링, 조직·헤드카운트 플랜, 보드덱·투자자 업데이트, 딜 MEDDPICC·파이프라인 감사. `/okr-plan`·`/okr-checkin`·`/okr-score`·`/stage-check`·`/org-plan`·`/board-deck`·`/investor-update`·`/deal-review`·`/pipeline-audit`·`/scaleup-from-startup`.

**미발동(위임 경계):**
- 기존 코드베이스 기능 작업 → 스택별 플러그인
- 사업 가설·시장조사·유닛이코노믹스·콘텐츠 → **startup**(읽기 승계는 `/scaleup-from-startup`)
- 재무제표·세무·실적 수치 → **finance** / 법률 판단 → **legal** / JD·온보딩 → **hr**
- GRC·전사 경영계획·M&A 스크리닝 → **enterprise**

## Architecture

- **패턴**: 3계열 파이프라인 + 단계 내부 Producer(maker)-Reviewer(checker). checker 는 Edit 미보유 + verdict.json 물화 → 후속 게이트가 결정론 재검.
- **메모리**: `.planning/scaleup/` + git = 상태. `scaleup-master.json`(status/현재 분기/완료 단계)이 사이클 상태를 보장.
- **판정**: 결정론 게이트 6종(`hooks/gates/*.sh`, exit 0/1). 커맨드가 `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-x.sh"` 로 직접 호출.

## Team Members

| ID | 에이전트 | 구분 | 산출물 |
|----|----------|------|--------|
| OP | `org-planner` | maker | org-chart.md, headcount.json |
| BR | `board-reporter` | maker | board/*-deck.md, kpi-pack.json, investor/*.md |
| OC | `okr-checker` | checker(Edit 미보유) | okr/verdict.json (ADOPT/REWRITE/DROP) |
| DQ | `deal-qualifier` | checker(Edit 미보유) | gtm/deals/*/verdict.json (COMMIT/DOWNGRADE/DISQUALIFY) |
| SC | `scale-checker` | checker(Edit 미보유) | org/stage-verdict.json (ADVANCE/HOLD/NOT-YET) |

OKR 초안·체크인·스코어링·딜 초안·파이프라인 정규화는 **메인 세션**이 operating-cadence·revops-pipeline-schema 스킬을 참조해 직접 수행한다.

## Pipelines (결선표)

**① 분기 OKR 사이클** (①플랜 → ②체크인 반복 → ③스코어링):
- `/okr-plan` → (메인+operating-cadence) → `okr-checker` → `gate-okr --require-verdict`
- `/okr-checkin` → 메인 → `gate-cadence`
- `/okr-score` → 메인 → `gate-okr --scored`

**② 이벤트성 조직·보드**:
- `/stage-check` → 메인(산술 선계산) → `scale-checker`(org/stage-verdict.json) — 게이트 없음
- `/org-plan` → `org-planner` → `gate-headcount`
- `/board-deck` → `board-reporter` → `gate-board-deck`
- `/investor-update` → `board-reporter` — 게이트 없음(legal 위임 문구)

**③ 딜 단위 GTM**:
- `/deal-review` → 메인 초안 → `deal-qualifier` → `gate-meddpicc --require-verdict`
- `/pipeline-audit` → 메인(jq 정규화) → `gate-pipeline-hygiene`

**브릿지**: `/scaleup-from-startup`(`.planning/business/` 승계, 부재 시 인터뷰 폴백).

## Gate Policy (자율 통과 + 실패 시만 보고)

| 결과 | 동작 |
|------|------|
| 통과 | 1줄 보고 후 진행 |
| 실패 | 중단. 실패 게이트·원인·시도·옵션 보고 |
| 모호(파일 부재 등) | 중단. 불명확 지점 + 권장안 보고 |

**사용자 승인 게이트**(자율 통과 금지): OKR 최종 채택(`/okr-plan` 종료), 딜 commit(`/deal-review` DISQUALIFY/DOWNGRADE 시), 대외 산출물(보드덱·투자자 업데이트) 배포.

> 게이트별 판정 기준·산출물 스키마 정본은 [references/gate-policy.md](references/gate-policy.md). enum 데이터 정본은 각 스킬 references/(pipeline-enums.json 등).

## Producer-Reviewer 규약

- 표면 체크(필드 존재·형식)는 **게이트가 선처리**. checker 는 의미 판단 잔여분만(outcome vs activity, EB 실권, 조기 사업부제 등).
- 반증 실패 시 통과가 기본값. 반증에는 구체 근거 요구(과잉 강등 방지). max 2라운드.
- 자기발견 제외: checker 는 maker 산출물만 검증(완전 분리, Edit 미보유).

## Boundaries

**Will:** 3계열 파이프라인 라우팅, maker/checker 디스패치, 게이트 판정 위임·보고, `.planning/scaleup/` 상태 유지.
**Will Not:**
- 게이트/checker 없이 대외 산출물 확정
- 부서 경계 침범(finance·legal·hr·startup·enterprise 위임 준수)
- 자유 대화형 가상 임원 회의(반증 관점 다양화 외 페르소나 배제)
