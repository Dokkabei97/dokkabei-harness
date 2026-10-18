---
name: gov-dora
description: |
  DORA 4 Keys 리포트 커맨드(읽기 전용, 상태 무변경) — git 태그·머지 타임스탬프로 배포 빈도(DF)·리드타임(LT)을 산출하고, 포스트모템 원장(postmortems/·audit-log)과 조인해 변경실패율(CFR)·평균복구시간(MTTR) 추세를 리포트한다. mvp-status와 동형의 읽기 전용 조회로 어떤 상태도 쓰지 않는다. SLI 실측이 필요한 값은 observe/infra-otel 연계 지점을 안내하고 자체 수집기는 구현하지 않는다. Use when 배포 성능(DORA 4대 지표) 추세를 확인하거나 팀 딜리버리 건강도를 조회할 때.
  DORA 4 Keys report command (read-only, no state change): derives deployment frequency (DF) and lead time (LT) from git tags/merge timestamps, and joins the postmortem ledger (postmortems/, audit-log) to report change failure rate (CFR) and MTTR trends. A read-only lookup like mvp-status that writes no state; for values needing real SLI it points to observe/infra-otel rather than building a collector. Use when: checking deployment-performance (DORA) trends or team delivery health.
category: workflow
complexity: intermediate
mcp-servers: []
personas: []
---

# /gov-dora — DORA 4 Keys 리포트 (읽기 전용)

git 히스토리와 포스트모템 원장으로 DORA 4대 지표를 산출하는 **읽기 전용** 리포트. `mvp-status` 패턴 — 어떤 `.planning` 상태도 변경하지 않는다.

## Triggers
- 배포 빈도·리드타임·변경실패율·MTTR 추세를 확인할 때
- 팀 딜리버리 성능을 정기 회고할 때
- "DORA 지표", "배포 성능 추세", "우리 딜리버리 어때?" 요청

## Usage
```
/gov-dora [옵션]
Options:
  --since <date|tag>   집계 시작점(기본 최근 90일)
  --format <md|table>  출력 형식(기본 table)
```

## Behavioral Flow

### Phase 1: 배포 빈도(DF) — git 태그
1. `git tag`·`git log`로 릴리즈 태그(예: `v*`) 타임스탬프를 수집.
2. 기간별 배포 횟수 → DF(일/주 단위) 산출. 태그 규약이 없으면 main 머지 커밋으로 폴백(가정 명시).

### Phase 2: 리드타임(LT) — 머지 타임스탬프
1. 커밋 최초 작성 시각 → 릴리즈 태그 시각 간격으로 변경 리드타임 분포(중앙값·p75) 산출.
2. squash/rebase로 히스토리가 압축된 경우 한계를 명시(추정치).

### Phase 3: 변경실패율(CFR)·MTTR — 포스트모템 원장 조인
1. `.planning/gov/postmortems/`·`audit-log.jsonl`에서 사고·핫픽스를 수집.
2. CFR = (사고 유발 배포 / 전체 배포). MTTR = 포스트모템 타임라인의 탐지→복구 간격 평균.
3. 데이터가 부족하면(포스트모템 少) "표본 부족 — 추세 신뢰 낮음"을 명시.

### Phase 4: 추세 리포트
- 4 지표를 기간 비교(이번 vs 직전)로 제시. DORA 성능 밴드(Elite/High/Medium/Low)는 참고 라벨로만(단정 금지).
- SLI 실측이 필요한 정밀 값(가용성 등)은 observe/infra-otel 연계 지점을 안내.

## Tool Coordination
- **Bash**: `git tag`/`git log`/`git show`로 타임스탬프·간격 산출(읽기 전용)
- **Read**: `postmortems/`·`audit-log.jsonl`(CFR·MTTR 조인 입력)
- **연계**: observe/infra-otel(정밀 SLI 필요 시 안내만)

## Boundaries

**Will:** git·포스트모템 원장 기반 DORA 4 Keys 산출, 기간 추세 비교, 데이터 한계 명시(읽기 전용).
**Will Not:**
- 어떤 `.planning` 상태도 기록·변경(순수 조회 — mvp-status 패턴)
- SLI 실측 수집기 구현(→ observe/infra-otel 연계)
- 성능 밴드를 근거 없이 단정하거나 개인 성과 평가로 사용(팀 시스템 지표로만)
