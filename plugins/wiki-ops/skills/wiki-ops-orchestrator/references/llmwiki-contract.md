# llmwiki 도구 계약 (실측 기반)

wiki-ops의 모든 에이전트/스킬이 llmwiki CLI를 구동할 때 따르는 운영 계약.
근거: llm-wiki 소스 실측 (cli.py / lint.py / ingest.py / store.py / mcp_server.py).

## 실행형 결정 (LLMWIKI_BIN)

우선순위대로 결정하고 세션 내내 고정한다:

1. `command -v llmwiki` 성공 → `llmwiki` (uv tool install 됨)
2. `LLMWIKI_REPO` 환경변수 존재 → `uv run --directory "$LLMWIKI_REPO" llmwiki`
3. 둘 다 없으면 사용자에게 llm-wiki 체크아웃 경로를 1회 질문

모든 호출에 `--vault <절대경로>`를 명시한다 (cwd 기본값에 의존하지 않는다).

## 종료 코드 계약

| exit | 의미 | 에이전트 대응 |
|------|------|---------------|
| 0 | OK | **성공 ≠ 유효 결과** — 아래 '0인데 실패' 참조 |
| 1 | 검사 실패 (lint 소견 존재 / ingest 롤백됨) | 소견 triage 또는 원인 보고 |
| 2 | 사용자·환경 오류 (vault 아님, 미지원 포맷, **Ollama 다운/모델 부재**) | 원인 해결 후 재실행 (ingest는 롤백돼 있어 재시도 안전) |
| 3 | 상태 오류 (dirty tree / 작성자 락 30s 초과) | dirty→커밋 또는 --allow-dirty 판단, 락→backoff 후 1회 재시도 |
| 4 | --airgap 하 비루프백 호출 차단 | 정책 위반 — 사용자에게 보고, 우회 금지 |

**exit 0인데 실패인 경우** (필드로 판정할 것):

- `query` 히트 0 → `citations: []` + `answer_md: ""` 인데 exit 0. **citations 길이로 판정**
- `watch` → `failed > 0` 이어도 exit 0. failed 필드 확인
- `query --persist` 조건 미달(distinct source < 2) → `synthesis_persisted: false`로 조용히 통과
- `ingest` 동일 내용 재투입 → `skipped: true` (정상 멱등, LLM 0회·커밋 0회)

## --json 핵심 필드

모든 --json 출력에 `provider_calls`와 `exit_code`가 항상 포함된다.
stdout = JSON 1줄, stderr = 진행/에러 (에러는 --json이어도 stderr에 중복 출력).

| 명령 | 판정 필드 |
|------|-----------|
| `init` | `idempotent_noop`, `git_commit` |
| `ingest <f>` | `source_id`, `skipped`, `claims`, `contradictions`, `entity_upserts[].contradictions`, `commit` |
| `query "<q>"` | `citations[]`(비면 근거 없음), `synthesis_persisted`, `synthesis_path`, `accessed_raw`(항상 false여야 정상) |
| `lint` | `finding_count`, `findings[]` (orphan/concept_without_page/stale/missing_crossref/data_gap) |
| `lint --integrity` | `verdict`(pass/fail/n/a), `pass_rate`, `threshold`(기본 0.90), `results[].status` |
| `lint --schema` | `violation_count`, `violations[]`(path/field/problem) |
| `lint --semantic` | `finding_count`(CONTRADICTS만), `ledger`(원장 경로), `pairs` |
| `research "<q>"` | `sub_questions[]`, `citations[]`, `web_sources[]`, `synthesis_path` |
| `graph --format json` | **--json 플래그 없이도 stdout이 JSON** (유일한 예외) |

## lint 4종 = 게이트 위계

| 모드 | LLM | 결정론 | 용도 |
|------|-----|--------|------|
| `lint` (구조) | 0회 | ✅ (자동 reindex 포함) | **루프 게이트** |
| `lint --integrity` | 0회 | ✅ (raw[span]==quote 순수 문자열 비교, fail-closed) | **루프 게이트** |
| `lint --schema` | 0회 | ✅ (frontmatter 계약 — 멀티에이전트 드리프트 방지) | **루프 게이트** |
| `lint --semantic` | 쌍당 1회 | ❌ (Ollama 필요, exit 2 가능) | **감사 전용 — 게이트 금지** |

semantic의 CONTRADICTS는 `wiki/_reports/contradictions.md` 원장에 append(pair-sha12 dedupe)되며
**절대 자동 해소되지 않는다** — 모순 처리는 항상 인간 결정 사항이다.
세 lint 플래그는 상호배타 (동시 지정 exit 2).

## 락 · dirty · 롤백

- **단일 작성자 락** `.llmwiki/locks/ingest.lock` (30s 타임아웃 → exit 3): ingest, watch 재-ingest,
  `--persist`/research의 synthesis 쓰기, semantic 원장 append, MCP write가 전부 공유한다.
  → **같은 vault에 병렬 쓰기는 무의미** — 항상 순차 실행. 읽기(query, lint, graph)는 락 프리.
- **dirty 가드**: ingest는 락 획득 후 git status를 검사한다. vault 안의 미추적 파일(`.planning/` 등)도 걸린다
  → Stage 0에서 vault `.gitignore`에 세션 파일을 등록해 둘 것. `raw/*`·`.llmwiki/`·`graph.html`은 원래 ignore.
- **touch-only 롤백**: 실패한 ingest는 저널된 파일만 pre-image 바이트로 복원한다 (`git reset --hard` 절대 없음).
  실패 후 재실행은 항상 안전. Ctrl-C만 롤백 밖(고아 `.ingested` 가능 — 재-ingest가 복구).
- **git 커밋 규약**: ingest 1건 = 커밋 1건 (`ingest: src-<id>`). 커밋 해시를 신뢰 신호로 쓸 수 있는 건 ingest뿐
  (synthesis/원장 커밋은 실패해도 조용히 통과한다).

## 프로바이더

- `--provider fake`: 네트워크 0, 바이트 결정론. **구조·인용·exit code 검증 전용** — 요약/답변 텍스트는
  고정 문자열이므로 품질 판단 금지. claims/quote/span은 코드 유래라 fake여도 진짜다.
- `--provider ollama`(기본): 루프백 전용. 다운/모델 부재 → 실행 가능한 한 줄 에러 + exit 2 (스택트레이스 없음).
- `--airgap`: CLI 플래그만 유효 (**LLMWIKI_AIRGAP env는 MCP write 경로 전용** — CLI에는 안 먹는 함정).
- 임베딩(`query --hybrid`)은 별도 모델(LLMWIKI_OLLAMA_EMBED_MODEL) — 없으면 hybrid만 포기하면 된다.

## vault 불변식 (에이전트 행동 규칙)

1. `raw/` 아래는 **절대 수정 금지** — 특히 `raw/.ingested/`는 인용 무결성의 ground truth
2. `wiki/` 직접 편집은 허용된 설계다 — 단 편집 후 `lint --schema` 통과 + 직접 커밋 필수
3. **claim·페이지 삭제로 integrity pass-rate를 올리는 것 금지** — 삭제는 사용자 승인 후에만
4. 소스 파일이 1바이트라도 바뀌면 새 source_id로 **별도 페이지**가 생긴다 (교체가 아님 — 구 페이지는 stale로 감지됨)
5. 판정 신호 위계: exit code → --json 필드(verdict/finding_count/citations) → `.llmwiki/runs/*.json`(감사 로그) → `wiki/_reports/contradictions.md`(커밋되는 원장)
