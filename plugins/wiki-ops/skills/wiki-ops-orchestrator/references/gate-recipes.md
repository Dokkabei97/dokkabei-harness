# 게이트 레시피 — generic 루프 엔진 연동

wiki-ops는 자체 Stop훅을 갖지 않는다. 큐레이션 루프는 **harness 플러그인의 generic 루프 엔진**
(`.planning/loop-active`, engine=generic)을 `/loop-run` 위임으로 재사용한다.

## 결정론 게이트 사슬 (gate-cmd 1행)

`<VAULT>`는 절대경로로 치환. LLMWIKI_BIN에 따라 둘 중 하나:

PATH형 (`llmwiki`가 PATH에 있을 때):

```
llmwiki --vault "<VAULT>" lint && llmwiki --vault "<VAULT>" lint --integrity && llmwiki --vault "<VAULT>" lint --schema
```

uv형 (`LLMWIKI_REPO` 체크아웃 사용 시):

```
uv run --directory "<LLMWIKI_REPO>" llmwiki --vault "<VAULT>" lint && uv run --directory "<LLMWIKI_REPO>" llmwiki --vault "<VAULT>" lint --integrity && uv run --directory "<LLMWIKI_REPO>" llmwiki --vault "<VAULT>" lint --schema
```

규칙:

- gate-cmd는 첫 1행만 읽힌다 — 반드시 한 줄 `&&` 사슬 (개행 금지)
- 세 lint 모두 LLM-0 결정론 — **Ollama가 죽어 있어도 게이트는 돌아간다**
- `--semantic`은 게이트에 절대 넣지 않는다 (LLM 비결정 + Ollama 다운 시 exit 2 → no-progress 시그니처 오염)
- Stop훅 timeout 600초 안에 완료돼야 한다 — lint 3종은 대형 vault도 수 초 수준
- exit 0이어도 출력에 `N fail/error`(N≥1) 표지가 있으면 엔진이 보수적 red 처리한다 — 게이트에 임의 echo를 덧붙이지 말 것

## Stage 0 vault 준비 (dirty 가드 예방)

vault 루트에서 1회 (세션 프로젝트 = vault인 표준 모드):

```
grep -qxF '.planning/' .gitignore 2>/dev/null || { printf '.planning/\nHANDOFF.md\n' >> .gitignore && git add .gitignore && git commit -m "chore: wiki-ops session files ignored"; }
```

이유: ingest의 dirty 가드는 미추적 파일도 잡는다 — 루프 상태 파일(`.planning/*`)이
ingest exit 3을 유발하는 것을 예방한다.

## 게이트 시운전 (헛루프 예방)

루프 진입 전 gate-cmd를 1회 직접 실행해 exit code를 확인한다:

| exit | 판정 | 행동 |
|------|------|------|
| 0 | 이미 그린 | 루프 불필요 — 즉시 완료 보고 |
| 1 | 소견 존재 | 정상 진입 |
| 2 | vault/인자 오류 | 진입 금지 — 원인 해결 먼저 |
| 127 | LLMWIKI_BIN 미해결 | 진입 금지 — 실행형 재결정 |

## /loop-run 위임 (Stage 3)

```
/loop-run "wiki 큐레이션: lint 3종(구조·무결성·스키마) 그린까지 소견 해소" --gate-cmd '<위 1행 사슬>' --promise "<promise>WIKI_CURATE_COMPLETE</promise>" [--max-iter N] [--max-minutes M]
```

- **이중 가동 금지**: 기존 `.planning/loop-active`가 engine=mvp/floop이면 가동하지 말고
  해당 킬스위치(`/mvp-stop`·`/floop-stop`)를 안내한다. 타 엔진 파일을 삭제·덮어쓰지 않는다 (비침범 규약)
- 킬스위치: `/loop-stop` (engine=generic만 해제, 멱등)
- 가드레일 (generic 기본): max 12회 / 60분 / no-progress 연속 2회 → BLOCKED.md
- 조정: `/loop-run`의 `--max-iter`·`--max-minutes` 옵션 우선 — 사용자 지정 상한은 반드시 옵션으로 전달. env `LOOP_MAX_ITER`·`LOOP_MAX_MINUTES`는 미전달 시 대안 (훅 우선순위: env > loop-state.json > 기본값)

## 루프 반복 규율 (메인 세션이 체화)

1. 게이트 출력에서 소견 1~n건 선택 → 해소 편집 (llmwiki-contract.md의 vault 불변식 준수)
2. `lint --schema` 자가 확인 → `git add wiki/ && git commit -m "curate: <요지>"` (미커밋 편집은 다음 ingest를 exit 3으로 막는다)
3. 완료라고 판단되면 progress.md에 promise 기록 후 종료 시도 — **판정은 훅이 한다** (게이트 red면 재주입됨)
