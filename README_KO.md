> [English](README.md) · **한국어**

# dokkabei-harness

Claude Code 플러그인 마켓플레이스. 처음에는 sub agent 모음에서 시작했으나, 지금은
에이전트·커맨드·스킬·훅을 하나로 묶은 **플러그인 23종**을 `plugins/` 아래에 담고,
`.claude-plugin/marketplace.json` 으로 설치·배포한다.

## 설치

```
/plugin marketplace add <이 저장소 경로 또는 git URL>
/plugin install <플러그인명>@dokkabei-harness
```

예: `/plugin install base@dokkabei-harness`, `/plugin install search@dokkabei-harness`.

## ★ 대표 플러그인: `observe` — 스스로를 계측하는 하네스

대부분의 플러그인이 일을 한다면, **`observe`는 하네스 그 자체를 지켜본다** — 어떤 스킬·에이전트가
실제로, *왜* 발화하고, 완주하는지 — 그리고 그것을 구체적 개선으로 바꾼다.

> Claude Code 네이티브 `/usage`가 **비용·토큰**을 본다면, observe는 그 위층을 본다 — **어떤 스킬·
> 에이전트가 왜 발화하고, 완주하며, 어느 것이 정체·미교정되는가** — 비용 지표로는 얻을 수 없는
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

# 2. 평소대로 작업한다 — 6종 훅이 프롬프트 → 스킬 → 에이전트 → 결과 → 세션을
#    .claude/skill-trace.jsonl 에 상관 로깅 (session_id / prompt_id 로 조인)

# 3. 리포트를 요청한다: 결정론 집계 → LLM 해석 → 개선 제안
/observe-report   # 미사용 & stale/archive 후보 · 놓친 발화
                  # 교정 신호 · description 튜닝 초안
```

### 로컬 관측 — SaaS 없음

호스팅 서비스는 없다; 전부 당신의 기기에서 돈다. observe의 트레이스는 로컬 `.jsonl` 이다.
비용/토큰 쪽은 `infra/otel`의 Grafana 스택 — **직접 띄우는 docker-compose** — 가 담당한다.
Claude Code 내장 OpenTelemetry(비용·토큰·이벤트)를 수신해 스킬 트레이스 옆에서 보여주며,
전부 **루프백에만** 바인딩된다. 프롬프트도 메트릭도 노트북을 떠나지 않는다.

```sh
cd infra/otel && docker compose up -d
# Grafana → http://localhost:3000  (Claude Code 비용/토큰 대시보드, EN/KO)
```

**왜 SaaS가 아니라 docker-compose인가?** 하네스에 대한 신뢰는 빌린 대시보드가 아니라 직접
돌려보는 데서 온다. 이 스택은 **로컬에서 직접 확인**하라고 있는 것이다 — 띄워서 숫자를 보고,
내리면 끝. 아무것도 업로드되지 않고, 아무것도 팔지 않는다. (상세: [`infra/otel/README_KO.md`](infra/otel/README_KO.md).)

## 구조

```text
├── .claude-plugin/marketplace.json   # 마켓플레이스 등록면(플러그인 23종)
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
- **eng-gov** — 개발 거버넌스: ADR·변경 증적·위협모델·공급망·SLO 게이트를 로컬 `exit 0/1` 스크립트로 물화(mvp/feature-loop/generic 루프의 `gate-cmd` 계약과 결합 가능), `/gov-audit`로 한국어 심사 증적 생성.

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
- **scaleup** — PMF 이후 실행 OS: OKR 케이던스(플랜→체크인→스코어), 조직 스케일링·헤드카운트 플랜, 보드덱·투자자 업데이트, MEDDPICC 딜 검증, RevOps 파이프라인 위생.
- **enterprise** — 중견·대기업 거버넌스 OS: GRC 파이프라인(리스크 레지스터→통제 매트릭스→정책 체계→ISMS-P 갭→의무 캘린더) + 전사 계획(전략 캐스케이드, 경영계획, 롤링 포캐스트, M&A 스크리닝).
- **etc** — 유틸(웹 페치, 교차 모델 CLI 라우팅).

> **비즈니스 수명주기**: **startup**으로 가설을 검증하고, `/mvp-from-startup`으로 코드에 넘기고, PMF 이후는 **scaleup**(`/scaleup-from-startup`)으로 실행하고, 거버넌스가 필요해지면 **enterprise**(`/enterprise-from-scaleup`)로 정식화한다 — 딜리버리 쪽은 **eng-gov**가 증적 게이트로 경화한다. 각 단계는 독립 설치 가능하며, 브릿지는 상류 `.planning/` 산출물이 있을 때만 활성화된다.

## 개발

```
bats tests/hooks           # 훅·루프 엔진 회귀 테스트
jq . plugins/*/hooks/hooks.json   # 훅 등록면 파싱 검증
```

- 훅 스크립트는 `bin/hooks/_lib/hook-stdin`의 `readEvent`/`passthrough` 컨벤션을 따른다
  (이벤트 파싱 → 조건부 경고 stderr → 원본 passthrough stdout; PreToolUse 차단은 exit 2).
- 컴포넌트 규약과 검증 룰은 `plugins/harness/skills/flow-validation/`,
  스캐폴딩 템플릿은 `plugins/harness/skills/flow-scaffolding/` 참조.
