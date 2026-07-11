> [English](README.md) · **한국어**

# workflow

> 개발 라이프사이클 전반(계획 → 스펙 → 리뷰 → 머지 후처리 → 회고)을 커맨드·스킬·훅으로 자동화하는 워크플로우 플러그인.

## 개요

`workflow`는 코드 자체를 짜는 플러그인이 아니라, 코드를 둘러싼 개발 프로세스를 자동화한다.
아이디어 정제·스펙 게이팅 같은 사전 단계부터 MR 코드 리뷰, 세션 핸드오프, 릴리즈 노트,
머지 후 이슈 종료·문서 최신화, 그리고 세션에서 얻은 교훈을 자산화하는 회고까지 한 플러그인에 묶는다.
GitLab(`glab`)·Plane·Outline 같은 외부 도구/위키와 연동하는 스킬은 해당 도구가 있을 때만 동작하는 opt-in 구성이며,
계획·스펙·배포·폐기 가이드류는 외부 의존 없이 순수 방법론으로 활성화된다.
`/retro` 회고 라우터와 세션 자동 스냅샷 훅은 다른 세션·다른 플러그인(base·harness)과 소유권 경계를 지키도록 설계되어,
루프 하네스가 도는 세션에서는 스스로 물러나 충돌을 피한다.

## 구성요소

### 커맨드

- `/handoff` — 세션 컨텍스트(목표·시도·다음 단계 + git 상태)를 `HANDOFF.md`에 저장해 다음 세션이 이어받게 한다. 컨텍스트 한계 임박·세션 종료 시 사용.
- `/release-notes` — 직전 릴리즈 태그 이후 머지된 MR을 `glab`으로 수집, conventional commit/MR 제목으로 변경 유형을 분류해 한국어 체인지로그·릴리즈 노트 초안을 만들고 다음 semver 버전과 태그·Release 생성 명령을 제안한다(원격 반영은 승인 후).
- `/retro` — 이번 세션의 교정·실수·발견을 추출해 유형별로 라우팅하는 회고 컴파운딩 라우터. 컨벤션 변화는 `sync-claude-md`로, 반복 실수는 `tasks/lessons.md`(가드 훅 후보 태그 포함)로, 도메인 지식은 스킬 수정 제안으로 분배한다. 모든 적용은 사용자 승인 게이트를 거친다.
- `/review-mr` — GitLab MR diff를 분석해 버그·보안 취약점·로직 오류를 탐지하고 MR에 리뷰 코멘트를 작성한다. diff 성격에 따라 `analyze` 플러그인의 전문 에이전트(arch-reviewer/perf-reviewer/sql-analyzer)를 선택 디스패치하고, confidence 기반으로 low 지적사항을 제외·강등한다.

### 스킬

- `spec-driven-dev` — 코드 작성 전 스펙을 먼저 확정하는 게이트 워크플로우(SPECIFY → PLAN → TASKS → IMPLEMENT)로 범위 이탈·재작업을 방지한다.
- `planning-guide` — 모호한 아이디어를 구체적 계획과 실행 가능한 태스크로 변환(아이디어 정제·의존성 매핑·수직 슬라이싱·태스크 사이징).
- `shipping-guide` — 프로덕션 배포 전후 검증(사전 체크리스트·피처 플래그·단계적 롤아웃·롤백·런칭 후 모니터링).
- `deprecation-guide` — 시스템/모듈/API 폐기와 소비자 마이그레이션의 체계적 프로세스(폐기 판단 프레임워크·Strangler/Adapter/Feature Flag·안전 제거).
- `issue-tracker` — `plane-cli` 기반 Plane 이슈 연동. 브랜치명에서 이슈 자동 감지, 상태 추적, 변경 이력 기록, 서브태스크 분할 제안.
- `document-latest` — 코드 변경 완료 후 Outline 위키 문서를 자동 최신화. 문서 유형 자동 분류, 신규/갱신 판단, 한국어 작성, 민감정보 자동 마스킹.
- `post-merge` — MR 머지 후 `issue-tracker`와 `document-latest`를 연계 실행해 Plane 이슈 종료와 Outline 문서 갱신을 일괄 처리하는 오케스트레이터.
- `sync-claude-md` — 커밋/PR 전 코드 변경을 분석해 `CLAUDE.md` 갱신 필요 여부를 판단하고, 아키텍처·통합·컨벤션·환경 변화가 있으면 갱신을 제안·실행한다. 커밋/푸시/PR·MR 요청 시 조용히 자동 발화한다.
- `retro-compound` — `/retro`가 따르는 회고 방법론. 재현·일반화·판정 가능성 기준으로 교훈을 필터링하고 유형별 라우팅 표에 따라 분배하며, 중복·상충 검사와 저품질 규칙 축적 방지 원칙을 담는다. CLAUDE.md 반영은 `sync-claude-md`, 가드 훅 스캐폴딩은 `harness:create-flow`에 위임.
- `doc-collab-guide` — 기획서·제안서·보고서 등 장문 문서를 사용자와 공동 작성하기 위한 얇은 규약. 공식 `doc-coauthoring` 스킬 설치 안내, 아웃라인 승인 게이트만 정의하고 작성 기법 자체는 공식 스킬에 위임한다.

### 훅

- `PreToolUse(Bash)` → `hooks/remind-claude-md-sync.js` — `git commit`/`git push`를 세션당 1회 exit 2로 차단해 `sync-claude-md` 검토(CLAUDE.md 갱신 필요 여부)를 결정론적으로 강제한다. 검토 후 같은 명령을 재시도하면 통과하며, CLAUDE.md 없는 프로젝트에서는 발동하지 않는다. 킬스위치: `CLAUDE_MD_SYNC_REMIND=0`.
- `PreCompact` / `SessionEnd` → `hooks/session-snapshot.sh` — 컴팩션 직전·세션 종료 시점에 git 상태(브랜치·변경 파일·최근 커밋)와 미완 마커 수를 `HANDOFF.md`의 `<!-- auto-snapshot -->` 마커 섹션에만 결정론적으로 기록한다. 마커 밖의 수동 작성 내용은 어떤 경로에서도 건드리지 않으며, 실패해도 항상 exit 0으로 세션을 방해하지 않는다. `.planning/loop-active`가 있는 루프 세션에서는 즉시 물러난다(앵커는 mvp/floop 소관).

## 사용법

- 사전 단계: 새 기능은 `spec-driven-dev`로 스펙을 게이팅하고, 모호한 요구는 `planning-guide`로 태스크까지 분해한 뒤 착수한다.
- 개발 중: MR이 열리면 `/review-mr [번호|URL]`(인자 없으면 현재 브랜치 자동 감지)로 리뷰한다. 커밋/PR 시점에는 `sync-claude-md`가 자동으로 CLAUDE.md 갱신 필요 여부를 점검한다.
- 세션 관리: 컨텍스트가 길어지거나 작업을 넘길 때 `/handoff`로 의미 요약을 남기고, 기계적 git 상태는 스냅샷 훅이 `HANDOFF.md`에 자동 보존한다(둘은 상호 보완).
- 머지 후: `post-merge`로 Plane 이슈 종료 + Outline 문서 갱신을 일괄 처리하고, 릴리즈 마감 시 `/release-notes`로 체인지로그·다음 버전을 정리한다.
- 마무리: 작업/리뷰/루프 종료 시 `/retro`로 세션 교훈을 추출해 lessons.md·CLAUDE.md·스킬로 라우팅한다(모든 적용 전 승인).

## 의존성

- 별도의 플러그인 `requires`는 없다. 다만 일부 구성요소는 외부 도구/플러그인이 있을 때만 완전히 동작한다.
  - `/review-mr`, `/release-notes` — GitLab CLI `glab` 필요. `/review-mr`는 `analyze` 플러그인의 리뷰 에이전트(arch-reviewer/perf-reviewer/sql-analyzer)를 선택 디스패치한다.
  - `issue-tracker` — `plane-cli`(Plane) 필요. `document-latest` — Outline MCP 필요. `post-merge` — 둘 다 필요(Plane + Outline).
  - `retro-compound` — 가드 훅 스캐폴딩은 `harness:create-flow`에 위임.
  - `doc-collab-guide` — 공식 `doc-coauthoring` 스킬(anthropics/skills) 설치가 전제.

## 참고

- 원격에 영향을 주는 작업(태그·GitLab Release 생성, CLAUDE.md·문서 갱신, lessons/스킬 반영)은 항상 사용자 승인 후 실행한다.
- `sync-claude-md`는 커밋/푸시/PR·MR 흐름에서 조용히 자동 발화하며, 갱신이 불필요하면 아무 것도 하지 않고 넘어간다.
- 외부 연동 스킬(`glab`/Plane/Outline)은 해당 도구·인증이 없으면 활성화되지 않는 opt-in 구성이다.
