> [English](README.md) · **한국어**

# dokkabei-harness

Claude Code 플러그인 마켓플레이스. 처음에는 sub agent 모음에서 시작했으나, 지금은
에이전트·커맨드·스킬·훅을 하나로 묶은 **플러그인 19종**을 `plugins/` 아래에 담고,
`.claude-plugin/marketplace.json` 으로 설치·배포한다.

## 설치

```
/plugin marketplace add <이 저장소 경로 또는 git URL>
/plugin install <플러그인명>@dokkabei-harness
```

예: `/plugin install base@dokkabei-harness`, `/plugin install search@dokkabei-harness`.

## 구조

```text
├── .claude-plugin/marketplace.json   # 마켓플레이스 등록면(플러그인 19종)
├── plugins/<name>/                    # 각 플러그인
│   ├── .claude-plugin/plugin.json     #   매니페스트(name/description/version)
│   ├── agents/                        #   서브 에이전트
│   ├── commands/                      #   슬래시 커맨드(레거시 포맷)
│   ├── skills/<name>/SKILL.md         #   스킬(권장 포맷)
│   ├── hooks/hooks.json               #   훅 등록면
│   └── bin/hooks/*.js                 #   훅 스크립트(Node)
├── claude/                            # Claude Code 루트 세팅용 배포본(CLAUDE.md·settings.json·output-styles)
├── tests/hooks/*.bats                 # 훅·루프 엔진 회귀 테스트(bats)
└── .github/workflows/                 # CI(ubuntu+macos 매트릭스)
```

## 플러그인 목록

### 기반·하네스 구축
- **base** — 공통 가드 훅 16종(보안 경고 `warn-security`, 포맷/컴파일 체크, tmux 강제 등) + LSP. 루프 하네스의 기반 계층.
- **harness** — 하네스 구축용 메타 플러그인: `team-harness` 설계, `/create-flow`·`/verify-flow`, 경량 범용 루프(`/loop-run`·`/loop-stop`).
- **observe** — 하네스 사용 관측·개선. 훅 6종이 스킬/에이전트 호출·완주·세션 경계를 `.claude/skill-trace.jsonl`에 상관 기록(`OBSERVE_TRACE=1` opt-in)하고, `/observe-report`가 집계→미발화 판정→개선 제안서(description 튜닝·사장 자산)를 산출.

### 개발 워크플로우
- **analyze** — 코드 품질/보안/성능/아키텍처/SQL 종합 분석.
- **test** — TDD 워크플로우, E2E(Playwright/Chrome) 테스트 생성·실행.
- **workflow** — PE/MR 리뷰, 세션 핸드오프, CLAUDE.md 동기화, 문서화, 이슈 추적, 머지 후처리, 스펙/계획/배포/폐기 관리, 회고 컴파운드.

### 루프 엔지니어링
- **mvp** — 신규 서비스 MVP 루프. 아이디어→PRD→디자인→스택 선택·스캐폴딩→PRD-driven 개발을 Stop훅 루프 엔진 + 게이트 상태기계로 완주.
- **feature-loop** — 브라운필드 코드베이스용 루프. 자연어 요청을 작업 분해(tasks.json)→baseline 캡처→회귀 안전 개발 루프로 완주.

### 백엔드 스택
- **backend-shared** — 언어 공통: API 설계(REST/GraphQL), DB 마이그레이션, 헥사고날 아키텍처, 관측성/캐싱/이벤트/회복탄력성/보안/DTO 패턴, 백엔드 테스트.
- **kotlin-spring** / **python-fastapi** / **go-mux** — 스택 특화 코드 생성·가이드·스캐폴딩(backend-shared와 조합).
- **nextjs** — Next.js App Router 프론트엔드 특화.
- **search** — Elasticsearch 검색 엔지니어링: 쿼리 최적화, 관련성 튜닝, 벡터/하이브리드 검색(kNN/RRF), 데이터 파이프라인 연동(Kafka/Spark), 인덱스 수명주기.

### 도메인
- **legal** — 한국법 법무(계약·기업/투자·노동·IP·규제·형사 리스크). Expert Pool + Fan-out.
- **finance** — 운영 재무·세무(경비 적격성, 재무제표 해석, 세무 리스크 스크리닝).
- **hr** — 채용·피플옵스(JD 초안, 면접 킷, 온보딩). 노동법 판단은 legal로 위임.
- **startup** — 린 캔버스, 아이디어 검증, 시장 조사, 유닛 이코노믹스, 성장 계획, 피치덱.
- **etc** — 유틸(웹 페치, 교차 모델 CLI 라우팅).

## 개발

```
bats tests/hooks           # 훅·루프 엔진 회귀 테스트
jq . plugins/*/hooks/hooks.json   # 훅 등록면 파싱 검증
```

- 훅 스크립트는 `bin/hooks/_lib/hook-stdin`의 `readEvent`/`passthrough` 컨벤션을 따른다
  (이벤트 파싱 → 조건부 경고 stderr → 원본 passthrough stdout; PreToolUse 차단은 exit 2).
- 컴포넌트 규약과 검증 룰은 `plugins/harness/skills/flow-validation/`,
  스캐폴딩 템플릿은 `plugins/harness/skills/flow-scaffolding/` 참조.
