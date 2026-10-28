> [English](README.md) · **한국어**

# workflow

> 개발 라이프사이클 전반(계획 → 스펙 → 리뷰 → 머지 후처리 → 회고)을 커맨드·스킬·훅으로 자동화하는 워크플로우 플러그인.

## 개요

`workflow`는 코드 자체를 짜는 플러그인이 아니라, 코드를 둘러싼 개발 프로세스를 자동화한다.
아이디어 정제·스펙 게이팅 같은 사전 단계부터 MR 코드 리뷰, 세션 핸드오프, 릴리즈 노트,
머지 후 이슈 종료·문서 최신화, 그리고 세션에서 얻은 교훈을 자산화하는 회고까지 한 플러그인에 묶는다.
GitLab(`glab`)·Plane·Outline 같은 외부 도구/위키와 연동하는 스킬은 해당 도구가 있을 때만 동작하는 opt-in 구성이며,
계획·스펙·배포·폐기 가이드류는 외부 의존 없이 순수 방법론으로 활성화된다.
`project-rules`는 프로젝트의 스택(빌드 파일 버전·도구·git 호스트)을 감지해 프로젝트 CLAUDE.md 의 스택 사실 블록과
`.claude/rules/` 의 스페셜리스트 규칙(스택 플러그인 항목 중 해당 버전에 맞는 것만)을 제안하는 진입점이다.
사용자가 직접 실행하는 외부 연동·생성 작업은 `disable-model-invocation: true` 로 모델 자동 발화에서 빠져 있다(슬래시로만 실행).

## 구성요소

### 커맨드 (모두 사용자 직접 실행 전용)

- `/handoff` — 세션 컨텍스트(목표·시도·다음 단계 + git 상태)를 `HANDOFF.md`에 저장해 다음 세션이 이어받게 한다. 컨텍스트 한계 임박·세션 종료 시 사용.
- `/release-notes` — 직전 릴리즈 태그 이후 머지된 MR을 `glab`으로 수집, conventional commit/MR 제목으로 변경 유형을 분류해 한국어 체인지로그·릴리즈 노트 초안을 만들고 다음 semver 버전과 태그·Release 생성 명령을 제안한다(원격 반영은 승인 후).
- `/review-mr` — GitLab MR diff를 분석해 버그·보안 취약점·로직 오류를 탐지하고 MR에 리뷰 코멘트를 작성한다. confidence 기반으로 low 지적사항을 제외·강등한다.

### 스킬

- `project-rules` — 프로젝트 스택 감지(JDK/Kotlin/Spring Boot, go.mod, pyproject, next, ES 클라이언트·매핑, 마이그레이션 도구, ORM 유무, git 호스트) → 프로젝트 CLAUDE.md 마커 블록(`<!-- project-rules:start/end -->`, ≤30줄)과 `.claude/rules/<stack>-specialist.md`(`paths` 스코프, 해당 버전에 맞는 스페셜리스트 항목 ≤15개를 ID 로 선별)를 diff 로 제안하고, 스택 플러그인을 `--scope local` 로 켜는 명령을 안내한다. `--check` 는 버전 드리프트·없는 도구·사라진 ID·200줄 초과를 보고. 모든 쓰기는 승인 후.
- `retro` (`/retro`) — 이번 세션의 교정·실수·발견을 추출해 유형별로 라우팅하는 회고. 컨벤션 변화는 `sync-claude-md`로, 반복 실수는 `tasks/lessons.md`(가드 훅 후보 태그 포함)로, 도메인 지식은 스킬 수정 제안으로 분배한다. 판정 기준은 `references/compound-criteria.md`(구 `retro-compound` 스킬을 2026-10 병합). 모든 적용은 승인 후.
- `spec-driven-dev` — 코드 작성 전 스펙을 먼저 확정하는 게이트 워크플로우(SPECIFY → PLAN → TASKS → IMPLEMENT)로 범위 이탈·재작업을 방지한다.
- `planning-guide` — 모호한 아이디어를 구체적 계획과 실행 가능한 태스크로 변환(아이디어 정제·의존성 매핑·수직 슬라이싱·태스크 사이징).
- `shipping-guide` — 프로덕션 배포 전후 검증(사전 체크리스트·피처 플래그·단계적 롤아웃·롤백·런칭 후 모니터링).
- `deprecation-guide` — 시스템/모듈/API 폐기와 소비자 마이그레이션의 체계적 프로세스(폐기 판단 프레임워크·Strangler/Adapter/Feature Flag·안전 제거).
- `issue-tracker` (직접 실행 전용) — `plane-cli` 기반 Plane 이슈 연동. 브랜치명에서 이슈 자동 감지, 상태 추적, 변경 이력 기록, 서브태스크 분할 제안.
- `document-latest` (직접 실행 전용) — 코드 변경 완료 후 Outline 위키 문서를 최신화. 문서 유형 자동 분류, 신규/갱신 판단, 한국어 작성, 민감정보 자동 마스킹.
- `post-merge` (직접 실행 전용) — MR 머지 후 `issue-tracker`와 `document-latest`를 연계 실행해 Plane 이슈 종료와 Outline 문서 갱신을 일괄 처리하는 오케스트레이터.
- `sync-claude-md` — 커밋/PR 전 코드 변경을 분석해 `CLAUDE.md` 갱신 필요 여부를 판단하고, 아키텍처·통합·컨벤션·환경 변화가 있으면 최소 diff 를 제안하고 승인 후 적용한다. `project-rules` 블록은 건드리지 않는다.
- `doc-collab-guide` — 기획서·제안서·보고서 등 장문 문서를 사용자와 공동 작성하기 위한 얇은 규약. 공식 `doc-coauthoring` 스킬 설치 안내, 아웃라인 승인 게이트만 정의하고 작성 기법 자체는 공식 스킬에 위임한다.

### 훅

- `PreToolUse(Bash)` → `hooks/remind-claude-md-sync.js` — 세션 첫 `git commit`/`git push` 에 `sync-claude-md` 검토를 권하는 한 줄을 `additionalContext` 로 넣는 비차단 넛지(exit 0, 권한 흐름 불간섭). 안내는 명령 결과와 함께 도착하므로 필요한 갱신은 후속 커밋으로 반영한다. CLAUDE.md 없는 프로젝트에서는 발동하지 않는다. 킬스위치: `CLAUDE_MD_SYNC_REMIND=0`.

## 사용법

- 프로젝트 시작: "이 프로젝트 세팅" / `/project-rules` 로 스택 사실·스페셜리스트 규칙을 만들고, 버전을 올린 뒤엔 `/project-rules --check` 로 드리프트를 확인한다.
- 사전 단계: 새 기능은 `spec-driven-dev`로 스펙을 게이팅하고, 모호한 요구는 `planning-guide`로 태스크까지 분해한 뒤 착수한다.
- 개발 중: MR이 열리면 `/review-mr [번호|URL]`(인자 없으면 현재 브랜치 자동 감지)로 리뷰한다. 첫 커밋/푸시 때 훅이 `sync-claude-md` 검토를 한 줄로 권한다.
- 세션 관리: 컨텍스트가 길어지거나 작업을 넘길 때 `/handoff`로 세션 요약과 git 상태를 `HANDOFF.md`에 남긴다 — 명시 호출 전용이며, 자동으로 기록되는 경로는 없다.
- 머지 후: `post-merge`로 Plane 이슈 종료 + Outline 문서 갱신을 일괄 처리하고, 릴리즈 마감 시 `/release-notes`로 체인지로그·다음 버전을 정리한다.
- 마무리: 작업/리뷰/루프 종료 시 `/retro`로 세션 교훈을 추출해 lessons.md·CLAUDE.md·스킬로 라우팅한다(모든 적용 전 승인).

## 의존성

- 별도의 플러그인 `requires`는 없다. 다만 일부 구성요소는 외부 도구/플러그인이 있을 때만 완전히 동작한다.
  - `/review-mr`, `/release-notes` — GitLab CLI `glab` 필요.
  - `issue-tracker` (직접 실행 전용) — `plane-cli`(Plane) 필요. `document-latest` — Outline MCP 필요. `post-merge` — 둘 다 필요(Plane + Outline).
  - `retro` — 가드 훅 스캐폴딩은 `harness:create-flow`에 위임.
  - `project-rules` — 스페셜리스트 항목은 설치된 스택 플러그인(`kotlin-spring`, `go-mux`, `python-fastapi`, `nextjs`, `search`, `backend-shared`, `test`)의 references 에서 읽는다(항목 포맷 `### <PREFIX>-<AREA>-<NN> · 제목` + `- 적용:` 줄에 의존).
  - `doc-collab-guide` — 공식 `doc-coauthoring` 스킬(anthropics/skills) 설치가 전제.

## 참고

- 원격에 영향을 주는 작업(태그·GitLab Release 생성, CLAUDE.md·문서 갱신, lessons/스킬 반영)은 항상 사용자 승인 후 실행한다.
- `sync-claude-md`는 강제되지 않는다 — 훅은 안내만 하고, 갱신이 불필요하면 무시하면 된다.
- 외부 연동 스킬(`glab`/Plane/Outline)은 해당 도구·인증이 없으면 활성화되지 않는 opt-in 구성이다.
