> [English](CONTRIBUTING.md) · **한국어**

# dokkabei-harness 기여 가이드

관심 가져주셔서 감사합니다. 이 저장소는 **Claude Code 플러그인 마켓플레이스**입니다 — `plugins/<name>/`
아래 20개 플러그인이 `.claude-plugin/marketplace.json`에 등록돼 있습니다. distinct-domain 플러그인
추가, 기존 컴포넌트 개선, 루프 엔진 강화 모두 환영합니다.

## 먼저 ground truth

무엇을 바꾸기 전에 [`CLAUDE.md`](CLAUDE.md)를 읽으세요 — 실측 사고 이력에서 뽑은 절대 규칙이 담겨
있습니다. 특히 이 규칙들은 어기면 **조용히** 물립니다:

- **`hooks.json`의 `matcher`는 tool명 regex만 받습니다** (`Bash`, `Edit|Write`). `tool == "X"` 표현식이나
  명령 내용 필터를 matcher에 넣으면 훅이 **조용히 미발화**합니다. 명령/인자 필터는 훅 스크립트 내부에서 하세요.
- **플러그인은 레포 소스에서만 편집합니다.** `~/.claude/plugins/cache` 클론을 직접 수정하지 마세요
  (캐시 드리프트 사고 이력). 전파 경로는 커밋 → `/plugin update`입니다.
- **플러그인 버전은 두 곳에서 동기화합니다**: `plugins/<name>/.claude-plugin/plugin.json` ↔
  `.claude-plugin/marketplace.json`의 해당 엔트리. 문자열까지 일치해야 합니다.
- **훅을 수정하면 같은 변경에서 실데이터 샘플이나 픽스처 payload 로 검증하세요**
  (JSON 을 스크립트에 파이프해 exit 코드·stdout 바이트·기록된 레코드를 확인).
  PreToolUse 차단은 exit 2입니다 (exit 1은 비차단 경고로 통과됩니다).

## 개발 환경

**`package.json`이 없습니다** — npm 프로젝트가 아닙니다. CI 와 레포 내 테스트 스위트는 없습니다(`tests/`는
2026-10 제거). PR 전에 로컬에서 돌릴 검사:

```sh
jq . plugins/*/hooks/hooks.json                             # hooks.json 유효성
shellcheck --severity=error plugins/**/{hooks,bin}/**/*.sh  # 셸 훅/러너 린트
```

훅이나 셸 러너를 건드리면 픽스처 payload 로 직접 실행해 확인하세요(macOS 에서는 `md5sum`→`md5`/`shasum`
폴백과 bash 3.2 이식성에 유의).

## 컴포넌트 만들기

직접 손으로 스캐폴딩하지 마세요. 이 레포는 자체 도구를 제공합니다:

- **`/create-flow`** (`harness` 플러그인) — 아래 모든 컨벤션을 따르는 에이전트·커맨드·스킬·훅 대화형 스캐폴딩.
- **`/verify-flow`** (`harness` 플러그인) — 컴포넌트를 룰셋(`plugins/harness/skills/flow-validation/`)에
  대조 검증하고 심각도별 헬스 스코어를 보고.

신규 컴포넌트는 **스킬 형식**을 우선하세요 (Claude Code v2.1.3+ command/skill 통합). 생성 전 재사용:
기존 플러그인이 이미 그 도메인을 커버하면 근사-중복을 추가하지 말고 기존 것을 확장하세요 — 겹치는
컴포넌트는 트리거 충돌과 유지보수 부채를 만듭니다.

## 컨벤션

- **커밋**: Conventional Commits + 한국어 body — `feat(scope): …`, `fix(base): …`.
- **컴포넌트 description**(스킬/커맨드/에이전트 frontmatter)은 **이중언어**: 한국어 원문 먼저, 그다음
  영어 요약 + `Use when: …` 트리거 절. 한국어·영어 프롬프트 양쪽에서 발화가 되도록 유지합니다. 총
  1,400자 이내로 유지하세요 (스킬 리스팅이 1,536에서 잘립니다).
- **README는 쌍**: 영어 `README.md`가 메인, 한국어는 `README_KO.md`.
- **스킬 토큰 예산**: SKILL.md는 500줄 이내, 오케스트레이터 스킬은 500줄 이내(최적 < 300). 무거운
  템플릿/프리셋은 `references/`로 분리하세요.

## Pull request 체크리스트

1. `main`에서 브랜치를 따세요 (`main`에 직접 커밋 금지).
2. `jq`·`shellcheck` 클린 + 변경한 훅은 픽스처 payload 로 수동 검증.
3. 컴포넌트를 추가/변경했다면 `/verify-flow`가 Critical/High 소견 0.
4. 플러그인을 추가했다면 버전 2곳 동기 + 마켓플레이스 엔트리 완비.
5. PR 템플릿을 채우세요 — 무엇을 왜 바꿨고 어떻게 검증했는지.

## 버그 신고 & 기능 요청

[이슈 템플릿](.github/ISSUE_TEMPLATE/)을 사용하세요. 버그는 결정론적으로 재현되는 최소 훅 payload(stdin
JSON)가 가장 빠른 수정 경로입니다. 기능은 신규 플러그인이 소유할 **distinct domain**을 명시하세요 —
신규 플러그인의 기준은 "기존 어떤 플러그인도 흡수할 수 없다"입니다.

## 라이선스

기여함으로써, 귀하의 기여가 저장소의 [Apache-2.0](LICENSE) 라이선스로 배포되는 데 동의합니다.
