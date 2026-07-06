---
name: wiki-ops-orchestrator
description: |
  llmwiki CLI를 도구로 구동해 인용 기반 지식 vault를 운영하는 지식 운영 하네스 오케스트레이터. 문서 투입(feed)→결정론 감사(lint 구조·무결성·스키마)→큐레이션 루프(harness generic 루프 엔진 재사용)→인용 질의응답(ask)의 게이트 기반 상태기계. "위키/vault에 문서 넣어줘", "지식 베이스 감사·정리해줘", "vault에서 답 찾아줘" 요청과 /wiki-feed·/wiki-audit·/wiki-curate·/wiki-ask 실행 시 발동. llm-wiki 소스코드 개발에는 발동하지 않음 — feature-loop·스택 플러그인에 위임. Outline 사내위키 문서화는 workflow:document-latest 소관.
  Knowledge-ops orchestrator that drives the llmwiki CLI to operate a cited knowledge vault: gated feed → deterministic audit (structure/integrity/schema lint) → curation loop (reuses the harness generic loop engine) → cited Q&A. Use when: ingesting documents into an llm-wiki vault, auditing or curating wiki health, or answering questions from the compiled wiki. Does not fire for developing the llm-wiki source code itself.
---

# Wiki-Ops Orchestrator — 지식 운영 하네스

한 줄 요지: 문서를 던지면 **코드가 검증한 인용 위키**가 쌓인다.

핵심 명제: **위키의 신뢰는 모델이 아니라 코드가 만든다.** llmwiki의 lint 3종(구조·무결성·스키마)은
LLM-0 결정론 게이트다 — 이 하네스는 게이트를 새로 만들지 않고 도구에 내장된 게이트를 루프
정지조건으로 조립한다. 완료 판정은 모델이 아니라 하네스(exit code)가 한다.

## When to Apply

발동:
- 문서·디렉토리를 vault에 투입/컴파일할 때 ("위키에 넣어줘", "이 문서들 지식베이스로")
- vault 건강 감사·정리가 필요할 때 ("위키 감사", "모순 확인", "lint 소견 해소")
- 컴파일된 위키 기반 질의응답·synthesis 축적이 필요할 때 ("vault에서 답해줘")
- /wiki-feed · /wiki-audit · /wiki-curate · /wiki-ask · /wiki-status 실행 시

미발동 (위임 경계):
- llm-wiki 소스코드 개발·버그픽스 → feature-loop(브라운필드)·python-fastapi 등 스택 플러그인
- Outline 사내위키 문서화 → workflow:document-latest
- 웹 기반 심층 리서치 리포트 → deep-research (vault 근거 리서치는 /wiki-ask --research)

## Architecture

| 축 | 결정 |
|---|---|
| 패턴 | Pipeline (feed→audit→curate→ask) + Producer-Reviewer (wiki-curator maker ↔ wiki-auditor checker) |
| 실행 모드 | Sub-agents (산출물 파일 경유, 교차 통신 불필요). Stage 3 루프 주체는 **메인 세션** — Stop훅이 메인 세션 종료를 가로채는 구조적 제약 (mvp와 동일) |
| 루프 엔진 | **harness generic 엔진 재사용** (engine=generic, /loop-run 위임) — 자체 훅 0줄. 플러그인 의존성: harness |
| 메모리 | vault 자체(git history) + `.planning/wiki-feed-report.md`·`wiki-audit.md` + generic 루프 파일(`.planning/loop-*`) |
| 도구 계약 | [references/llmwiki-contract.md](references/llmwiki-contract.md) — **에이전트 디스패치 프롬프트에 3요소(vault 절대경로 · LLMWIKI_BIN · 이 파일의 절대경로)를 반드시 포함** (서브에이전트는 이전 대화를 모른다) |

## Team Members

| ID | 에이전트 | 역할 | 산출물 | 도구 경계 |
|----|---------|------|--------|----------|
| WC | agents/wiki-curator.md | maker — 대량 ingest, lint 소견 해소 편집 | vault 커밋, .planning/wiki-feed-report.md | Edit 보유 |
| WA | agents/wiki-auditor.md | checker — lint 실행·triage, 큐레이션 사기 적발 | .planning/wiki-audit.md | **Edit 미보유** (검증 대상을 못 고침) |
| WL | agents/wiki-librarian.md | 질의·synthesis — query/research 라우팅 | 인용 답변 (syntheses는 llmwiki가 씀) | 읽기 + Bash |

## Orchestration Phases

### Stage 0 — Intake & Vault 준비 (담당: 메인 세션)

- Input: vault 경로 (인자 → `$LLMWIKI_VAULT` → 사용자 질문 1회)
- 절차:
  1. LLMWIKI_BIN 결정 — contract의 우선순위 (PATH → `$LLMWIKI_REPO` → 질문)
  2. vault 판정: `init --json` — 기존 vault면 `idempotent_noop:true`, 빈 디렉토리면 신규 스캐폴딩.
     비어있지 않은 비-vault 디렉토리는 exit 2 → 사용자에게 경로 재확인
  3. dirty 가드 예방: vault `.gitignore`에 `.planning/`·`HANDOFF.md` 등록+커밋 ([gate-recipes](references/gate-recipes.md))
  4. 프로바이더 결정: 기본 ollama. 파이프라인 검증 목적이면 `--provider fake` (품질 판단 금지)
- Output: vault 절대경로 + LLMWIKI_BIN 확정 (세션 내 고정)
- 결정론 게이트: `init` exit 0 ∧ `lint --schema` exit 0

### Stage 1 — Feed (담당: 소량 ≤5개 메인 세션 / 대량 WC 디스패치 1회)

- Input: 소스 파일 목록 (md/markdown/txt/pdf만 — 그 외 exit 2) + vault 절대경로·LLMWIKI_BIN (Stage 0 산출, 세션 고정 — WC 디스패치 시 3요소로 전달)
- 절차: 파일별 `ingest --json` **순차** 실행 (단일 작성자 락 — 병렬 무의미).
  에러 프로토콜: exit 2(Ollama 다운)→중단·보고 / exit 3(dirty)→원인 파일 확인 후 커밋 or --allow-dirty /
  exit 3(락)→15초 후 1회 재시도 / exit 4→정책 위반 보고. `skipped:true`는 정상 멱등.
- Output: `.planning/wiki-feed-report.md` — 파일별 {source_id, claims, contradictions, commit|skipped|실패 사유}
- 결정론 게이트: 신규 ingest 전건에 commit 해시 존재

### Stage 2 — Audit (담당: WA 디스패치)

- Input: 디스패치 3요소 (vault 절대경로·LLMWIKI_BIN·contract 절대경로) + gate-recipes 절대경로 + .planning/wiki-feed-report.md (신규 ingest 건 식별)
- 절차: lint 3종 `--json` 실행 → 소견 유형별 triage. `--semantic` 요청 시(Ollama 필요) 모순 원장 확인.
  사기 적발: git diff로 claim 삭제·quote 변조 검사 (integrity pass-rate 조작 반증)
- Output: `.planning/wiki-audit.md`
- ★사용자 게이트 G1: 모순 원장(`wiki/_reports/contradictions.md`)에 미해소 모순이 있으면
  처리 방향(어느 소스를 신뢰할지)은 **반드시 사용자가 결정** — 자동 해소 금지 (llmwiki 설계 불변식)

### Stage 3 — Curate 루프 (담당: 메인 세션이 WC 규율 체화 + generic 루프)

- Input: .planning/wiki-audit.md 소견 목록 + vault 절대경로·LLMWIKI_BIN (Stage 0 산출)
- 진입 조건: Stage 2 소견 > 0 이고 사용자가 정리를 원할 때
- 절차:
  1. 게이트 시운전 (gate-recipes — exit 0이면 루프 불필요, exit 127/2면 진입 금지)
  2. `/loop-run` 위임: gate-cmd = lint 3종 `&&` 사슬, promise = `<promise>WIKI_CURATE_COMPLETE</promise>`
  3. 반복 규율: 소견 해소 편집 → `lint --schema` 자가 확인 → vault 커밋("curate: …") → 종료 시도 (판정은 훅)
  4. 편집 불변식: raw/ 수정 금지, claim 삭제로 integrity 통과 금지(사용자 승인 필요), stale은 재-ingest로 해소
- 정지 조건(훅 판정): 게이트 그린 ∧ promise. 가드레일: max 12회 / 60분 / no-progress 2회 → BLOCKED.md
- 킬스위치: `/loop-stop`. 타 엔진(mvp/floop) loop-active 발견 시 가동 거부 + 해당 킬스위치 안내
- Output: 게이트 그린 vault + progress.md

### Stage 4 — Ask (담당: 경량 질의 메인 세션 / 다면 리서치 WL 디스패치)

- Input: 사용자 질문 + 컴파일된 vault (Stage 3 게이트 그린 산출 — 미큐레이션 상태면 잔존 소견을 답변 한계에 명시)
- 라우팅: 단일 질문→`query` / 재사용 가치→`--persist`(distinct source ≥2일 때만 물화) / 다면 질문→`research`
- `citations`가 비면 지어내지 않고 "근거 없음 — 관련 소스를 feed하라" 정직 보고 (exit 0 함정)
- Output: 인용 답변 (+ `wiki/syntheses/` reuse_count 복리)

## Gate Policy

- 결정론 게이트 통과 → 자율 진행, 1줄 보고. 실패·모호 → 중단하고 보고 (게이트 우회 금지)
- 사용자 게이트는 정확히 1개 (★G1 모순 처리 방향) — 나머지 판정은 전부 exit code가 한다

## Error Handling

| 상황 | 대응 |
|------|------|
| Ollama 다운 (exit 2) | LLM-0 경로(lint 3종·reindex·graph·MCP-read)는 계속 가능 — feed/ask만 중단 보고 |
| 작성자 락 30s 초과 (exit 3) | 동시 세션 확인 → 15초 후 1회 재시도 → 재실패 시 보고 |
| dirty tree (exit 3) | git status로 원인 식별 — 큐레이션 편집이면 커밋, 미지 파일이면 사용자 확인 |
| no-progress BLOCKED | BLOCKED.md 확인 — 동일 소견 반복이면 해소 불가 사유 보고 + 사용자 에스컬레이션 |
| airgap 위반 (exit 4) | 우회 금지 — 정책 보고 |
| loop-active가 타 엔진 | 가동 거부 + `/mvp-stop`·`/floop-stop` 안내 (비침범 규약) |

## Completion Criteria

- [ ] 투입 소스 전건 처리 (commit 해시 또는 skipped 근거)
- [ ] lint 3종 exit 0 (결정론 게이트 그린)
- [ ] 미해소 모순 0건, 또는 사용자 결정 대기로 명시 이관
- [ ] `.planning/` 리포트 2종 최신화

## Re-run Support

상태는 vault git history + `.planning/`이 전부다 (대화 컨텍스트에 의존하지 않는다).
재진입 시 lint 3종 `--json`과 최근 커밋으로 현황을 재구성해 미완 Stage부터 재개한다.
루프 재개는 `/loop-run` 재실행 (잔존 loop-active 충돌은 loop-run이 검사한다).

## Boundaries

Will:
- llm-wiki vault 운영 전반 (feed / audit / curate / ask / status)
- llmwiki CLI 구동과 --json 필드 기반 결정론 판정
- harness generic 루프 엔진에 큐레이션 루프 위임

Will Not:
- llm-wiki 소스코드 수정 (→ feature-loop / 스택 플러그인)
- vault의 raw/ 편집, 모순 자동 해소, `--semantic`을 루프 게이트로 사용
- 타 루프 엔진(mvp/floop)의 loop-active 침범

## References

- [references/llmwiki-contract.md](references/llmwiki-contract.md) — 도구 계약 (종료코드·JSON 필드·락·불변식)
- [references/gate-recipes.md](references/gate-recipes.md) — 게이트 사슬·loop-run 위임·vault 준비 레시피
