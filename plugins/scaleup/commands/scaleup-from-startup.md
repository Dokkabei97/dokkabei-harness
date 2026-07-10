---
name: scaleup-from-startup
description: |
  startup 플러그인 산출물(.planning/business/)을 scaleup 실행 OS 로 승계하는 브릿지 — 린 캔버스·유닛이코노믹스·시장조사·검증 가설·그로스 플랜을 읽어 /okr-plan 의 objective·북극성 후보와 스코어카드 초기 지표, 딜 ICP 를 프리필한다. business 부재 시 인터뷰 폴백, scaleup-master.json 기존재 시 재개 안내. outcome 재작성·최종 확정은 okr-checker 와 사람 승인 몫.
  Bridge that carries startup outputs (.planning/business/) into the scaleup OS: reads lean canvas, unit economics, market research, validated hypotheses, and growth plan to pre-fill /okr-plan objective/north-star candidates, initial scorecard metrics, and deal ICP. Use when: continuing from startup business planning into scale-up execution. Falls back to interview if business is absent; KR outcome rewrite stays with okr-checker.
category: workflow
complexity: advanced
---

# /scaleup-from-startup — 비즈니스 가설 → 스케일업 브릿지

`startup` 플러그인이 `.planning/business/` 에 남긴 산출물을 scaleup 사이클 입력으로 **승계 프리필**한다. `/okr-plan` 이 "빈 분기"에서 출발한다면, 이 커맨드는 "이미 검증된 사업 가설"에서 출발해 OKR·스코어카드·딜 인테이크 왕복을 줄인다. mvp-from-startup 브릿지와 동형.

> 사이클 로직 전체는 scaleup-orchestrator 가 수행한다. 이 커맨드는 **비즈니스 산출물 → 사이클 입력 매핑**과 진입만 담당하며, OKR/조직/보드 로직을 중복 기술하지 않는다.

## Triggers
- `/lean-canvas`·`/unit-economics` 등으로 사업 가설을 세운 뒤 "이제 실행/스케일업"으로 넘어갈 때
- `.planning/business/` 산출물이 있는 상태에서 첫 분기 OKR 사이클 시작
- "린 캔버스대로 OKR 세팅", "검증한 가설로 스케일업 시작"

## Usage
```
/scaleup-from-startup [옵션]
Options:
  --quarter YYYYQn   시작 분기 지정(기본: 현재 분기)
```

## Behavioral Flow

### Phase 0: 사전 점검
1. **재개 감지**: `.planning/scaleup/scaleup-master.json` 이 이미 있으면(레포당 사이클 1개 전제) `/okr-plan` 재개 또는 현황 확인을 안내하고 중단.
2. **비즈니스 산출물 확인**: `.planning/business/` 를 점검. `lean-canvas.md` 가 **없으면** 인터뷰 폴백(페르소나·북극성·핵심 지표를 최소 질문으로 수집). 있으면 승계 모드.

### Phase 1: 비즈니스 산출물 → 사이클 입력 매핑

| 비즈니스 산출물 | → scaleup 입력 |
|-----------------|-----------------|
| 린 캔버스 UVP·Solution·Key Metrics | `/okr-plan` O1 후보 + 북극성 지표 |
| unit-economics(CAC/LTV/번·런웨이) | 스코어카드 초기 지표(체크인) |
| market-research 세그먼트·경쟁 | 딜 ICP + MEDDPICC competition 프리필 |
| validate-idea 리스크 가설 Top | OKR 미결 이슈(`okr/issues.md`) 시드 |
| growth-plan AARRR 백로그 | KR 후보(활동형은 okr-checker 가 outcome 으로 재작성) |
| brand-voice.md | 투자자 업데이트·보드덱 **톤 참조만**(재생성 금지) |

**경계**: 매핑은 입력 프리필일 뿐 자동 OKR 확정이 아니다. 서술형 캔버스 문장을 `X→Y by when` KR 로 재구성하는 것은 `/okr-plan` + okr-checker 의 몫이다.

### Phase 2: 진입
- `scaleup-master.json` 초기화(status/현재 분기/완료 단계) 후 `/okr-plan` 으로 진입. 승계 항목/여전히 물은 항목을 1줄로 구분 보고.

## Boundaries

**Will:** business 산출물 승계 프리필, 재개/폴백 라우팅, scaleup 사이클 진입.
**Will Not:**
- 비즈니스 산출물 없이 승계 강행(→ 인터뷰 폴백 또는 `/lean-canvas` 안내)
- 캔버스를 OKR 로 자동 1:1 확정(outcome 재작성은 okr-checker)
- 시장조사·유닛이코노믹스 재생성 → **startup 위임**(읽기 승계만)
