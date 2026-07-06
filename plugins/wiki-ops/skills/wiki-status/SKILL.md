---
name: wiki-status
description: |
  llm-wiki vault 현황 읽기 전용 1화면 조회 — vault 여부, 페이지 수, 마지막 lint 결과(.llmwiki/runs 최신), 모순 원장 미해소 건수, 큐레이션 루프(loop-active) 상태와 수동 해제법을 보고한다. 어떤 상태도 변경하지 않는다. Use when: "위키 상태 어때?", "루프 돌고 있어?", 작업 재개 전 현황 파악 시.
  Read-only one-screen status of an llm-wiki vault: vault validity, page counts, last lint result, unresolved contradiction count, and curation-loop (loop-active) state with the manual kill switch. Never mutates any state. Use when: checking vault or loop status before resuming work.
---

# /wiki-status — 현황 조회 (읽기 전용)

어떤 상태도 변경하지 않는다 — 조회만 한다. 쓰기 명령(ingest/curate)은 실행하지 않는다.

## When to Apply

- 작업 재개 전 vault·루프 현황 파악 (Re-run Support의 진입점)
- 큐레이션 루프가 돌고 있는지, 어디까지 왔는지 확인
- 감사 이력(마지막 lint)과 모순 원장 잔량 확인

## Flow

1. vault 판정: `wiki/` 디렉토리 또는 `AGENTS.md` 존재 (없으면 "vault 아님" 보고 후 종료)
2. 수집 (전부 읽기 전용):
   - 페이지 수: `wiki/sources|entities|concepts|syntheses` 파일 수
   - 마지막 lint: `.llmwiki/runs/`의 최신 `*-lint.json` (`exit_code`·`finding_count`·`verdict`)
   - 모순 원장: `wiki/_reports/contradictions.md`의 pair 수
   - 루프 상태: `.planning/loop-active`(engine 값)·`loop-state.json`(iteration/max)·BLOCKED.md 유무
3. 1화면 보고 + loop-active 존재 시 해제법(`/loop-stop` — generic일 때) 안내

## Output

```
vault: ~/kb (유효) / provider 기본: ollama
페이지: sources 42 · entities 17 · concepts 8 · syntheses 5
마지막 lint: 2026-07-06 structure 0건 · integrity pass(0.97) · schema 0건 (exit 0)
모순 원장: 미해소 2건 → /wiki-audit로 triage
루프: engine=generic iteration 3/12 (BLOCKED 없음) — 중단하려면 /loop-stop
```

## Boundaries

Will: 읽기 전용 수집·1화면 보고, 킬스위치 안내
Will Not: lint 실행(쓰기 없는 명령이지만 runs 로그를 남긴다 — 조회는 기존 로그만),
loop-active 조작, vault 파일 변경
