> [English](CLAUDE.md) · **한국어**

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 정체

Claude Code 플러그인 마켓플레이스(`dokkabei-harness`). 플러그인 12종이 `plugins/<name>/`에 살고
`.claude-plugin/marketplace.json`에 등록된다. 설치: `/plugin install <name>@dokkabei-harness`.

## 명령

- 레포 내 테스트 스위트·CI 없음(`tests/`와 GitHub Actions 워크플로는 2026-10 제거) — 훅 변경은 실데이터 샘플이나
  픽스처 payload 를 스크립트에 직접 파이프해 exit 코드·stdout 바이트·기록된 레코드를 수동 확인한다
- 훅 JSON 검증: `jq . plugins/*/hooks/hooks.json`
- 셸 훅 린트(로컬): `shellcheck --severity=error plugins/**/{hooks,bin}/**/*.sh`
- package.json 없음 — npm 스크립트를 찾지 말 것

## 절대 규칙 (실측 사고 이력 기반)

- hooks.json `matcher`는 **툴명 regex만** 유효(`Bash`, `Edit|Write`). `tool == "X"` 표현식이나 명령
  내용 필터를 matcher에 넣으면 **조용히 미발화**한다(실측 2026-07) — 명령/인자 필터링은 반드시
  훅 스크립트 내부에서 한다.
- hooks.json **matcher 그룹은 `matcher`·`hooks` 2키만** 가진다(최상위 예외는 `$schema` 하나).
  `timeout`/`args`/`async`/`if`는 핸들러 엔트리 소속이며, `description` 같은 스키마 외 키는 무시되고
  세션 시작마다 `hooks.json: unknown key "..." ignored` 경고를 낸다(실측 2026-09, CC 2.1.278) —
  훅 설명은 스크립트 헤더 주석에 적는다. `/verify-flow` 규칙 HK-004로 가드.
- **Stop 훅은 연속 8회 블록 후 오버라이드**된다 — Claude Code 가 훅과 무관하게 턴을 종료한다(2026-09-20 실측, 3/3 시행:
  훅이 9회 호출되고 9번째 `exit 2` 가 무시됨). 따라서 턴당 실효 상한은 `LOOP_MAX_ITER`(기본 12)가 아니라 **8 반복**이다.
  generic 엔진은 `stop_hook_active` 로 턴 단위 연속 블록(loop-state.json `turn_blocks`)을 세고, 상한 도달 시
  progress.md 에 핸드오프를 남기고 loop-active 를 유지한 채 exit 0 한다(LOOP-011). 누적 `iteration` 으로 판정하지 말 것.
- 플러그인은 **레포 소스에서만 편집**한다. `~/.claude/plugins/cache`·marketplaces 클론 직접 수정
  금지(실측된 캐시 드리프트 사고 이력). 공식 반영 경로는 커밋 후 `/plugin update`이며,
  훅·설정 변경은 다음 세션부터 유효하다.
- 플러그인 버전은 **두 곳 수동 동기화 필수**: `plugins/<name>/.claude-plugin/plugin.json` ↔
  `.claude-plugin/marketplace.json`의 해당 플러그인 엔트리.
- 훅을 수정하면 같은 변경에서 실데이터 샘플이나 픽스처 payload 로 수동 검증한다(직접 파이프 — 명령 절 참고).
  갱신할 회귀 스위트는 없다. PreToolUse 차단은 exit 2 (exit 1은 비차단 경고로 통과된다).

## 컨벤션

- 커밋: Conventional Commits + 한국어 본문 (`feat(scope): …`, `fix(base): …`)
- 컴포넌트 description(스킬/커맨드/에이전트 frontmatter)은 **이중언어**: 한글 원문 먼저, 그 뒤에
  영어 요약 + `Use when: …` 트리거절을 덧붙인다 (한/영 프롬프트 양쪽에서 발화 유지;
  총 1,400자 이하 — 스킬 목록은 1,536자에서 잘림)
- 컴포넌트 규칙·검증 룰셋: `plugins/harness/skills/flow-validation/` (`/verify-flow`가 사용;
  SKILL.md 토큰 예산 <3.5k 최적)
- 스캐폴딩 템플릿: `plugins/harness/skills/flow-scaffolding/` (`/create-flow`가 사용)
- 하네스 v2(upstream revfactory/harness v2.1.0 동기화): `TeamCreate`/팀 객체 없음 — 팀 정의는 오케스트레이터의
  `## Team Members` 표, 하네스 변경 이력은 CLAUDE.md 표가 아니라 git 커밋 본문(`harness:evolve`)
- Claude Code v2.1.3+에서 command/skill 통합 — 신규 컴포넌트는 skill 포맷 권장

## 헷갈리기 쉬운 구조

- `claude/` = 전역 `~/.claude` 배포 템플릿이다 — 이 파일(프로젝트 메모리)과 무관.
- `HANDOFF.md`는 `/handoff` 커맨드(명시 호출)로만 작성된다 — 자동 기록 훅은 없다
  (PreCompact/SessionEnd 스냅샷 훅은 2026-09 제거).
- 훅 스크립트는 2계열: base는 Node(`bin/hooks/*.js`, `_lib/hook-stdin.js` 컨벤션), harness generic 루프는
  bash(`hooks/generic-loop-stop-hook.sh` + `hooks/test-guard.sh`).
- `archive/` = 은퇴 플러그인(mvp·feature-loop·startup·scaleup·enterprise·eng-gov·legal·finance·hr·analyze·etc —
  실사용 0으로 2026-10 archive)과 그 bats(`archive/tests/hooks/`). 설치 불가(`.claude-plugin/` 없음)·marketplace.json
  미등재·CI 미실행. 복원 = 원위치 이동 + manifest·marketplace 엔트리 재추가.
- `archive/infra/otel/` = 은퇴한 로컬 OTel/Grafana 스택(2026-10 archive). observe 는 OTel 과 연동하지 않는다.
- `.tracer/` = observe 플러그인의 런타임 기록 폴더(자체 `.gitignore` `*` 로 git 에서 무시, `~/.tracer/` 는 `--all` 용 전역 층) —
  프로젝트 메모리나 이 파일과 무관하다. 구 `.claude/skill-trace.jsonl` 은 그 v0 경로다.
- `docs/` = GitHub Pages 랜딩 사이트(`index.html`, self-contained, EN/KO 토글) — 특정 플러그인과 무관하며
  공개 홈페이지(`dokkabei97.github.io/dokkabei-harness`)다. 플러그인의 `references/` 문서와 혼동 금지.
