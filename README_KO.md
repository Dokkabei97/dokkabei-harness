> [English](README.md) · **한국어**

# dokkabei-harness

Claude Code 플러그인 마켓플레이스. 처음에는 sub agent 모음에서 시작했으나, 지금은
에이전트·커맨드·스킬·훅을 하나로 묶은 **플러그인 12종**을 `plugins/` 아래에 담고,
`.claude-plugin/marketplace.json` 으로 설치·배포한다.

## 설치

```
/plugin marketplace add <이 저장소 경로 또는 git URL>
/plugin install <플러그인명>@dokkabei-harness
```

예: `/plugin install base@dokkabei-harness`, `/plugin install search@dokkabei-harness`.

## ★ 대표 플러그인: `observe` — 스스로를 계측하는 하네스

대부분의 플러그인이 일을 한다면, **`observe`는 하네스 그 자체를 지켜본다** — 어떤 스킬·에이전트가
실제로, *왜* 발화하고, 그 턴이 어떻게 끝나는지(커밋·취소·교정) — 그리고 그것을 구체적 개선으로 바꾼다.

> Claude Code 네이티브 `/usage`가 **비용·토큰**을 본다면, observe는 그 위층을 본다 — **어떤 스킬·
> 에이전트가 왜 발화하고, 그 턴이 어떻게 끝나며, 어느 것이 정체·미교정되는가** — 비용 지표로는 얻을 수 없는
> 하네스 건강 관점이다.

Nous Research의 **Hermes Agent**에서 영감을 받았다: Hermes가 경험에서 스킬을 자율 *생성*하며
성장한다면, observe는 **평가 우선** 경로를 택한다 — *계측하고 제안*한다. Hermes curator의
**결정론 절반**(사용 라이프사이클: stale / archive 후보, 교정 신호)을 이식했고, 사장·정체 자산,
놓친 발화, 교정 없이 끝난 스킬 실행을 드러낸 뒤 수정안을 초안까지 만든다.
**승인은 당신이 하며, 어떤 파일도 조용히 고치지 않는다.**

세 단계로 사용한다:

```sh
# 1. 계측을 켠다 (opt-in — 프롬프트 원문이 로컬에 기록되므로 기본은 꺼짐)
export OBSERVE_TRACE=1

# 2. 평소대로 작업한다 — 훅이 프롬프트 → 스킬 → 에이전트 → 결과 → 턴 결과 → 세션을
#    <repo>/.tracer/ 에 기록 (자기 gitignore). Codex 는 같은 훅을 쓰고, Antigravity 와
#    지난 Codex 세션은 observe-backfill.js 로 들어온다. git 훅은 opt-in

# 3. 리포트를 요청한다: 결정론 집계 → LLM 해석 → 개선 제안
/observe-report   # 미사용 & stale/archive 후보 · 놓친 발화
                  # 교정 신호 · description 튜닝 초안
                  # 마지막에 추천마다 수락 / 거절 / 보류를 묻는다
```

### 로컬 관측 — SaaS 없음

호스팅 서비스는 없다; 전부 당신의 기기에서 돈다. observe의 트레이스는 레포의 git 무시 폴더 `.tracer/` 에 있고
(프롬프트 원문은 시크릿 레드액션 후 `raw/` 에만), 아무것도 업로드되지 않고 아무것도 팔지 않는다. OTel(Claude Code 내장 텔레메트리)은 지원하지 않는다 —
observe 는 OTel 을 읽지도 내보내지도 않는다.

## 구조

```text
├── .claude-plugin/marketplace.json   # 마켓플레이스 등록면(플러그인 12종)
├── plugins/<name>/                    # 각 플러그인
│   ├── .claude-plugin/plugin.json     #   매니페스트(name/description/version)
│   ├── agents/                        #   서브 에이전트
│   ├── commands/                      #   슬래시 커맨드(레거시 포맷)
│   ├── skills/<name>/SKILL.md         #   스킬(권장 포맷)
│   ├── hooks/hooks.json               #   훅 등록면
│   └── bin/hooks/*.js                 #   훅 스크립트(Node)
├── claude/                            # Claude Code 루트 세팅용 배포본(CLAUDE.md·settings.json·output-styles)
├── archive/                           # 은퇴 플러그인; archive/components/<plugin>/ = 은퇴한 개별 컴포넌트
└── .github/                           # 이슈·PR 템플릿(CI 워크플로 없음)
```

## 플러그인 목록

### 기반·하네스 구축
- **base** — 공통 가드 훅 15종(보안 경고 `warn-security`, 포맷/컴파일 체크, tmux 강제 등) + LSP. 루프 하네스의 기반 계층.
- **harness** — 하네스 구축용 메타 플러그인: `team-harness` 설계(v2 실행 모드 3종)·`evolve` 진화, `/create-flow`·`/verify-flow`, 경량 범용 루프(`/loop-run`·`/loop-stop`).
- **observe** — 하네스 사용 관측·개선. Claude Code·Codex 훅(Antigravity 는 백필)이 스킬/에이전트 호출·턴별 작업 다이제스트(툴 흐름·커밋·결과: 커밋/취소/…)·세션 경계를 자기 gitignore 되는 `<repo>/.tracer/`에 상관 기록(원문은 시크릿 레드액션 후 `raw/` 로 분리, `OBSERVE_TRACE=1` opt-in)하고, opt-in git 훅이 커밋을 세션에 연결하며(`/observe-git-hooks`), `/observe-report`가 집계→미발화 판정→개선 제안서(description 튜닝·사장 자산)를 산출하고 수락/거절/보류 응답을 기록.

### 개발 워크플로우
- **test** — 테스트 우선 가이드(`tdd-workflow`, ID 붙은 테스트 함정 인덱스), 브라우저 E2E 검증 체크리스트(`e2e-chrome`, Claude in Chrome / Playwright MCP), 사용자 실행 Playwright 스펙 생성(`/e2e`).
- **workflow** — `/project-rules`(스택 감지 → 프로젝트 CLAUDE.md 스택 사실 블록·`.claude/rules/<stack>-specialist.md` 제안, `--check` 로 드리프트 점검), MR 리뷰, 세션 핸드오프, 릴리즈 노트, CLAUDE.md 동기화(비차단 안내), 문서화, 이슈 추적, 머지 후처리, 스펙/계획/배포/폐기 가이드, `/retro` 교훈 컴파운딩.

### 백엔드·프론트엔드 스택 — 스페셜리스트 지식 레이어
스택 플러그인은 모델이 이미 아는 관용구를 되풀이하지 않는다. 각 플러그인은 **스페셜리스트 지식 레이어**다: 짧은
트리아지 스킬(증상 → 항목 ID)이 `references/` 항목(`### <PREFIX>-<AREA>-<NN> · 제목` + 적용/신호/메커니즘/처방/반례/검증/근거)을
가리키며, 강한 시니어 제너럴리스트도 놓치는 기본값·버전 경계·내부 동작을 담는다. 스택 버전을 가정하지 않고 모든
진입점이 프로젝트 빌드 파일부터 확인하며, 어느 항목 ID 가 이 레포에 해당하는지는 `/project-rules`(workflow)가 기록한다.
사용자가 직접 실행하는 생성·리뷰 커맨드는 `disable-model-invocation: true`(슬래시 메뉴 전용).

- **backend-shared** — PostgreSQL / Kafka / Valkey / 분산 호출 함정 허브(`async-event-patterns`), 마이그레이션 안전성, DTO·직렬화 규칙, Context7 조회 규약; 커맨드 `/api-design`·`/api-doc`·`/api-test`·`/api-perf`·`/bean-check`·`/event-gen`·`/graphql-check`·`/security-check`.
- **kotlin-spring** — JVM/Kotlin/Spring 트리아지(GC·컨테이너 메모리, 컬렉션, 코루틴·가상 스레드, 트랜잭션/JPA/풀, 프로파일링), 읽기 전용 진단 에이전트, `/spring-gen` 스캐폴딩.
- **python-fastapi** — 이벤트 루프·스레드 풀, psycopg 풀, Pydantic 직렬화, GIL/GC, uvicorn 배포, PostGIS 트리아지; `/fastapi-gen`·`/fastapi-api-design`.
- **go-mux** — Go 런타임·성능 항목(map, slice, GC, 동시성, net/http, pprof/PGO, database/sql) + stdlib `net/http` mux `/go-gen`·`/go-api-design`. 이름은 go-mux 지만 Go 전반을 다룬다.
- **nextjs** — 버전 인지 App Router 항목(Next 16 변경, 캐싱·렌더링, RSC 경계, 데이터 워터폴, Server Action 보안, Web Vitals, 셀프 호스팅); `/nextjs-page-design`·`/nextjs-gen`.
- **search** — Elasticsearch/Lucene 허브(성능·매핑·클러스터 운영·클라이언트·색인 파이프라인, 한국어 nori 관련성, 벡터/하이브리드 검색), 리뷰 커맨드, 사용자 실행 `/search-team-orchestrator` 에이전트 팀.

허브에 흡수되거나 대체된 컴포넌트는 `archive/components/<plugin>/` 로 `git mv` 했다 — 예: backend-shared 의
캐싱/회복탄력성/보안/관측성/헥사고날/GraphQL/테스트 패턴 스킬, `/api-gen`, `/migrate`; kotlin-spring 의
`spring-boot-patterns`/`naming-conventions`; `fastapi-patterns`; search 의 `lucene-internals`, 파이프라인/리랭킹/관측성
스킬과 에이전트 2종; test 의 `/tdd`·`/e2e-chrome` 커맨드; workflow 의 `retro-compound`(현 `retro` 스킬).

### 지식 운영
- **wiki-ops** — 인용 기반 [llm-wiki](https://github.com/Dokkabei97/llm-wiki) 지식 vault 운영: 게이트 기반 투입 → 결정론 감사 → 큐레이션 루프(harness generic 루프 기반) → 인용 질의응답.

## 개발

```
jq . plugins/*/hooks/hooks.json   # 훅 등록면 파싱 검증
```

- 훅 스크립트는 `bin/hooks/_lib/hook-stdin`의 `readEvent`/`passthrough` 컨벤션을 따른다
  (이벤트 파싱 → 조건부 경고 stderr → 원본 passthrough stdout; PreToolUse 차단은 exit 2).
- 테스트 스위트·CI 는 없다 — 훅 변경은 실데이터 샘플이나 픽스처 payload 를 스크립트에 파이프해
  exit 코드·stdout 바이트·기록된 레코드로 확인한다.
- 컴포넌트 규약과 검증 룰은 `plugins/harness/skills/flow-validation/`,
  스캐폴딩 템플릿은 `plugins/harness/skills/flow-scaffolding/` 참조.
