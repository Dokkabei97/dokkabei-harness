---
name: wiki-harness-feed
description: |
  observe 계측을 llm-wiki vault 로 잇는 브릿지 — observe-report 결정론 집계(--candidates 0 --followups 0, 프롬프트 원문 0)를 observe-export.js 로 마크다운 스냅샷으로 렌더하고, feed-gate.sh 2차 게이트 + 사용자 승인 후 .planning/observe-export/<env>-<주차>.md 로 물화해 /wiki-feed 로 ingest 한다. 환경 라벨(personal|company)별 주간 시계열이 vault 에 축적되고, 부채 카운터가 큐레이션 시점을 안내한다. 원시 트레이스·원문 필드는 어떤 형태로도 ingest 하지 않는다. Use when: "하네스 스냅샷 위키에 넣어줘", "observe 리포트 vault 에 축적", 주간 하네스 건강 기록, 하네스 사용 이력 영속화 시.
  Bridges observe telemetry into the llm-wiki vault: renders the raw-text-free deterministic aggregate into a markdown snapshot, double-gates it (renderer fail-closed + feed-gate.sh), and ingests via /wiki-feed as an env-labeled weekly time series with a curation debt counter. Use when: feeding harness health snapshots into the knowledge vault, persisting harness usage history.
---

# /wiki-harness-feed — 하네스 건강 스냅샷 투입

observe(생산)와 wiki-ops(소비)를 잇는 브릿지 스킬이다. 결합은 하드 의존이 아니라
**파일 존재 검사**다(mvp↔startup 브릿지 선례) — observe 미설치·트레이스 부재 시 중단하고 안내한다.
observe 는 어떤 파일도 쓰지 않으므로(stdout-온리 계약) 물화·ingest 는 전부 이 스킬의 책임이다.

## When to Apply

- 주간 하네스 건강 스냅샷을 vault 시계열로 축적할 때 (권장 주기: 주 1회 수동)
- 트레이스가 10MB 로테이션으로 소실되기 전에 사용 이력을 영속화할 때
- description 튜닝 근거를 "이번 주 수치"에서 "N주 연속 claim"으로 상향하고 싶을 때

## Usage

```
/wiki-harness-feed --env personal|company [--vault <dir>] [--window 7] [--provider fake]
```

| 인자 | 의미 |
|------|------|
| `--env` | 환경 라벨 (**필수, 기본값 없음** — 잘못된 라벨은 시계열을 오염시킨다) |
| `--vault` | vault 경로 (생략 시 `$LLMWIKI_VAULT` → 둘 다 없으면 **진행하지 않고** 질문 1회 — fail-closed) |
| `--window` | 집계 윈도우 일수 (기본 7 — 주간 슬롯) |
| `--provider fake` | 파이프 전체 결정론 dry-run (Ollama·네트워크 0, 구조 검증 전용) |

## Flow

1. **Phase 0 — 존재 검사**: ① `.claude/skill-trace.jsonl` ② observe 설치본의 `bin/observe-export.js`
   ③ vault 경로. 하나라도 없으면 중단 — ①은 `OBSERVE_TRACE=1` 활성화(다음 세션부터 유효),
   ②는 `/plugin install observe`, ③은 vault 준비(`/wiki-feed` 의 Stage 0)를 안내한다.
2. **Phase 1 — 주간 슬롯 고정 + 렌더 + 2차 게이트**: 스냅샷 대상은 **지난 완결 ISO 주**다.
   슬롯 타임스탬프를 결정론 계산해 집계·렌더 **양쪽**에 주입한다 — 이 고정이 없으면
   `idle_days` 등 벽시계 파생값이 주중 재실행마다 변해 멱등(skipped) 계약이 깨진다:
   `SLOT=$(node -e 'const d=new Date();const w=d.getUTCDay()||7;d.setUTCDate(d.getUTCDate()-w);d.setUTCHours(23,59,59,0);console.log(d.toISOString())')`
   (직전 일요일 23:59:59Z = 지난 완결 주의 끝) →
   `node <observe>/bin/observe-report.js --json --window 7 --candidates 0 --followups 0 --now "$SLOT"`
   → `node <observe>/bin/observe-export.js --env <env> --now "$SLOT"` (1차: 원문 필드 fail-closed exit 2)
   → 임시 파일에 받아 `bin/feed-gate.sh <file>` (2차: 정형 비밀·경로·attr:, 차단 exit 1).
   어느 게이트든 실패하면 ingest 없이 소견을 보고하고 중단한다.
3. **Phase 2 — 승인 게이트**: 렌더 **전문**을 사용자에게 제시하고 승인을 받는다.
   ingest 는 vault raw/ 와 git history 에 영구 고정되므로 승인 없는 인입은 없다.
4. **Phase 3 — 물화**: 프로젝트 `.gitignore` 에 `.planning/observe-export/` 를 idempotent
   등록한 뒤(스냅샷이 프로젝트 레포에 커밋되는 경로 차단) `.planning/observe-export/<env>-<ISO주차>.md`
   로 저장 — 주차는 SLOT 이 가리키는 지난 완결 주차(스냅샷 H1 과 일치). 같은 주차 파일이
   이미 있고 내용이 다르면 "재실행은 새 source 페이지를 추가한다(supersede 없음)"를 고지한
   뒤 진행 여부를 묻는다.
5. **Phase 4 — ingest 위임**: `/wiki-feed` 로 위임 (락·dirty·에러 프로토콜은 도구 계약 소관).
   ingest 는 스냅샷 디렉토리를 cwd 로 **파일명 상대경로**로 호출한다 — llmwiki 는 전달된
   경로 문자열을 source_path frontmatter 에 그대로 영구 기록하므로(실측: 상대 호출 시
   `source_path: <파일명>`), 절대경로 호출은 홈 경로 준식별자를 vault 에 남긴다. uv 폴백은
   cwd 를 바꾸는 `--directory` 대신 `uv run --project "$LLMWIKI_REPO" llmwiki`(cwd 보존,
   실측 확인)를 쓴다. 판정은 exit 0 ∧ commit 해시 존재. `skipped:true` 는 실패가 아니라
   **정상 멱등**(동일 주차 재실행)으로 구분 보고한다.
6. **Phase 5 — 부채 카운터**: `grep -l '하네스 건강 스냅샷' <vault>/wiki/sources/*.md | wc -l`
   결정론 집계로 스냅샷 소스 페이지 수를 세고, 12 초과 시 `/wiki-curate` 로 구 주차 정리를
   안내한다 (stale lint 는 주차별 신규 파일에 구조적으로 미발화 — `references/snapshot-format.md`).

## Boundaries

Will: 원문 0 집계 스냅샷의 렌더·이중 게이트·승인·물화·ingest 위임, env 라벨 시계열 축적,
멱등/신규 구분 영수증(source_id·commit·claims), 부채 카운터 보고
Will Not: 원시 트레이스(`skill-trace.jsonl`)·원문 필드(candidates/followups/why/args)의 ingest,
승인 없는 자동 feed, vault 미지정 시 진행(fail-closed), ingest 우회 wiki/ 직접 쓰기,
회사 어휘 유래 제안의 공개 레포 라우팅(회사 도메인 용어는 회사 프로젝트-로컬 CLAUDE.md 소관),
환경 간 트레이스 파일 병합·운반(환경 구분은 머신·vault 분리로 성립)
