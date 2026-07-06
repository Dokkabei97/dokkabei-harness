---
name: wiki-curate
description: |
  llm-wiki vault 큐레이션 루프 — lint 3종(구조·무결성·스키마) 게이트가 그린이 될 때까지 소견 해소 편집을 반복한다. Use when: "위키 정리해줘", "lint 소견 해소", 감사 소견이 쌓여 일괄 정리가 필요할 때. harness generic 루프 엔진(/loop-run, engine=generic)에 위임 — 자체 훅 없음, 가드레일은 max 12회/60분/no-progress 2회, 킬스위치는 /loop-stop. 편집 불변식: raw/ 수정 금지, claim 삭제로 integrity 통과 금지. harness 플러그인 필수.
  Curation loop for an llm-wiki vault: resolves lint findings until the three deterministic gates are green, delegating loop mechanics to the harness generic engine (/loop-run). Guardrails: 12 iterations / 60 min / no-progress ×2; kill switch /loop-stop. Requires the harness plugin. Use when: cleaning up audit findings until gates pass.
---

# /wiki-curate — 큐레이션 루프

얇은 진입점이다 — 루프 절차는 `wiki-ops-orchestrator` Stage 3과
[gate-recipes](../wiki-ops-orchestrator/references/gate-recipes.md)가 정의한다.
루프 판정은 모델이 아니라 harness generic Stop훅(exit code)이 한다.

## When to Apply

- `/wiki-audit` 소견이 쌓여 일괄 정리가 필요할 때
- 대량 feed 후 orphan·missing_crossref·data_gap을 게이트 그린까지 해소할 때
- raw 원본 갱신으로 stale 소견이 다수 발생했을 때 (재-ingest 정리)

## Usage

```
/wiki-curate [--vault <dir>] [--max-iter N] [--max-minutes M]
```

## Flow

1. 게이트 시운전: gate-cmd 1회 직접 실행 — exit 0이면 "이미 그린" 즉시 종료,
   exit 2/127이면 진입 금지 (원인 해결 먼저), exit 1이면 진입
2. 이중 가동 확인: `.planning/loop-active`가 타 엔진(mvp/floop)이면 가동 거부 + 해당 킬스위치 안내
3. `/loop-run` 위임 — gate-cmd = lint 3종 `&&` 사슬(1행),
   promise = `<promise>WIKI_CURATE_COMPLETE</promise>`,
   Usage로 받은 `--max-iter`/`--max-minutes`는 /loop-run에 그대로 전달
4. 반복: 소견 해소 편집 → `lint --schema` 자가 확인 → vault 커밋 → 종료 시도 (훅이 판정)

## 가드레일 · 킬스위치

- generic 엔진 기본: max 12회 / 60분 / no-progress 연속 2회 → BLOCKED.md
- 수동 중단: `/loop-stop` (engine=generic만 해제, 멱등)
- 모순 소견은 루프에서 해소하지 않는다 — ★사용자 결정으로 이관 (원장은 자동 해소 금지)

## Boundaries

Will: 소견 해소 편집·커밋, generic 루프 위임, BLOCKED 시 사유 보고
Will Not: 자체 Stop훅 생성, raw/ 편집, claim 삭제로 게이트 통과(사용자 승인 필요),
semantic을 게이트에 포함, 타 엔진 loop-active 침범
