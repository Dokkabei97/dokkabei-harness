> [English](README.md) · **한국어**

# wiki-ops

**[llm-wiki](https://github.com/Dokkabei97/llm-wiki) CLI를 도구로 구동**해 인용 기반 plain-text
지식 vault를 운영하는 지식 운영 하네스: 게이트 기반 투입 → 결정론 감사 → 큐레이션 루프 → 인용 질의응답.

핵심 명제: **위키의 신뢰는 모델이 아니라 코드가 만든다.** llmwiki에는 LLM-0 결정론 lint 게이트
3종(구조 / 인용 무결성 / frontmatter 스키마)이 내장돼 있다 — 이 플러그인은 게이트를 새로 만들지
않고 도구에 내장된 게이트를 루프 정지조건으로 조립한다. 완료 판정은 모델의 자기평가가 아니라
exit code가 한다.

## 요구 사항

- PATH의 `llmwiki` (`uv tool install`) 또는 `LLMWIKI_REPO` 환경변수가 가리키는 llm-wiki 체크아웃
- vault 디렉토리 (빈 디렉토리면 `llmwiki init`이 스캐폴딩) + git
- 실제 요약·답변용 루프백 [Ollama](https://ollama.com) — **선택**: 게이트 lint 3종은 전부 LLM-0라
  Ollama가 죽어 있어도 동작하고, `--provider fake`로 결정론 dry-run 가능
- `harness` 플러그인 (의존성) — 큐레이션 루프가 generic Stop훅 루프 엔진을 재사용

## 구성 요소

| 구성 요소 | 종류 | 역할 |
|-----------|------|------|
| `wiki-ops-orchestrator` | 스킬 | 게이트 상태기계: Stage 0 인테이크 → 1 feed → 2 audit → 3 curate 루프 → 4 ask |
| `/wiki-feed` | 스킬 | 파일·디렉토리를 vault에 순차 ingest (파일별 리포트) |
| `/wiki-audit` | 스킬 | lint 게이트 전체 + 모순 원장 triage + 큐레이션 사기 적발 |
| `/wiki-curate` | 스킬 | 게이트 그린까지 소견 해소 (`/loop-run` 위임, engine=generic) |
| `/wiki-ask` | 스킬 | 인용 질의응답: query / `--persist` synthesis / research 라우팅 |
| `/wiki-status` | 스킬 | 읽기 전용 1화면 현황 (상태 변경 없음) |
| `wiki-curator` | 에이전트 | maker — 대량 ingest·소견 해소 편집 (Edit 보유) |
| `wiki-auditor` | 에이전트 | checker — lint triage·사기 적발 (의도적 Edit 미보유) |
| `wiki-librarian` | 에이전트 | 질의·synthesis 라우팅, "근거 없음" 정직 보고 |

## 빠른 시작

```
/wiki-feed ~/notes/*.md --vault ~/kb     # 문서를 vault로 컴파일
/wiki-audit --vault ~/kb                 # 결정론 건강 리포트 + 모순 triage
/wiki-curate --vault ~/kb                # 구조·무결성·스키마 lint 그린까지 루프
/wiki-ask "토큰은 언제 만료돼?"           # verbatim 인용 병기 답변
```

## 루프 안전 장치

큐레이션 루프는 harness generic 엔진에서 돈다: 결정론 게이트
(`lint && lint --integrity && lint --schema`), completion promise, max 12회 / 60분 /
no-progress 감지, 킬스위치 `/loop-stop`. 모순은 **절대 자동 해소하지 않는다** —
항상 인간 결정으로 에스컬레이션된다 (★G1 사용자 게이트).

## 경계

- llm-wiki 소스코드 자체의 개발 → `feature-loop` / 스택 플러그인
- 사내 위키(Outline) 문서화 → `workflow:document-latest`
- 웹 기반 심층 리서치 리포트 → `deep-research` (vault 근거 리서치는 `/wiki-ask --research`)
