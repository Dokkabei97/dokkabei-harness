> [English](CLAUDE.md) · **한국어**

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 정체

Claude Code 플러그인 마켓플레이스(`dokkabei-harness`). 플러그인 19종이 `plugins/<name>/`에 살고
`.claude-plugin/marketplace.json`에 등록된다. 설치: `/plugin install <name>@dokkabei-harness`.

## 명령

- 훅·루프 엔진 회귀 테스트: `bats tests/hooks` (bats-core 로컬 설치 전제; CI는 ubuntu+macOS 매트릭스)
- 훅 JSON 검증: `jq . plugins/*/hooks/hooks.json`
- 셸 훅 린트(CI와 동일): `shellcheck --severity=error plugins/**/{hooks,bin}/**/*.sh`
- package.json 없음 — npm 스크립트를 찾지 말 것

## 절대 규칙 (실측 사고 이력 기반)

- hooks.json `matcher`는 **툴명 regex만** 유효(`Bash`, `Edit|Write`). `tool == "X"` 표현식이나 명령
  내용 필터를 matcher에 넣으면 **조용히 미발화**한다(실측 2026-07) — 명령/인자 필터링은 반드시
  훅 스크립트 내부에서 한다.
- 플러그인은 **레포 소스에서만 편집**한다. `~/.claude/plugins/cache`·marketplaces 클론 직접 수정
  금지(캐시 드리프트 사고 이력 — tasks/todo.md). 공식 반영 경로는 커밋 후 `/plugin update`이며,
  훅·설정 변경은 다음 세션부터 유효하다.
- 플러그인 버전은 **두 곳 수동 동기화 필수**: `plugins/<name>/.claude-plugin/plugin.json` ↔
  `.claude-plugin/marketplace.json`의 해당 플러그인 엔트리.
- 훅을 수정하면 `tests/hooks/*.bats` 회귀 테스트를 같이 갱신한다. PreToolUse 차단은 exit 2
  (exit 1은 비차단 경고로 통과된다).

## 컨벤션

- 커밋: Conventional Commits + 한국어 본문 (`feat(scope): …`, `fix(base): …`)
- 컴포넌트 description(스킬/커맨드/에이전트 frontmatter)은 **이중언어**: 한글 원문 먼저, 그 뒤에
  영어 요약 + `Use when: …` 트리거절을 덧붙인다 (한/영 프롬프트 양쪽에서 발화 유지;
  총 1,400자 이하 — 스킬 목록은 1,536자에서 잘림)
- 컴포넌트 규칙·검증 룰셋: `plugins/harness/skills/flow-validation/` (`/verify-flow`가 사용;
  SKILL.md 토큰 예산 <3.5k 최적)
- 스캐폴딩 템플릿: `plugins/harness/skills/flow-scaffolding/` (`/create-flow`가 사용)
- Claude Code v2.1.3+에서 command/skill 통합 — 신규 컴포넌트는 skill 포맷 권장

## 헷갈리기 쉬운 구조

- `claude/` = 전역 `~/.claude` 배포 템플릿이다 — 이 파일(프로젝트 메모리)과 무관.
- `HANDOFF.md` 상단 `<!-- auto-snapshot -->` 블록은 PreCompact/SessionEnd 훅이 기계 기록한다 —
  손으로 고치지 말 것. 의미 요약은 `/handoff`로 채운다.
- 훅 스크립트는 2계열: base는 Node(`bin/hooks/*.js`, `_lib/hook-stdin.js` 컨벤션), 루프
  플러그인(harness/mvp/feature-loop)은 bash Stop훅(`hooks/*-stop-hook.sh`).
- `infra/otel/` = 로컬 관측 스택(Claude Code 내장 OTel 수신, Grafana localhost:3000) —
  observe 플러그인의 `.claude/skill-trace.jsonl`과 직교 보완재.
