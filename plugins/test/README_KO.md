> [English](README.md) · **한국어**

# test

> 테스트 우선 가이드와 브라우저 E2E 검증 — 강한 시니어도 놓치는 테스트 함정 인덱스 포함.

## 설치

```
/plugin install test@dokkabei-harness
```

## 개요

`test` 는 두 축이다. `tdd-workflow` 는 RED → GREEN → REFACTOR 사이클을 짧게 두고, 본문은 스페셜리스트 테스트 함정으로
가는 트리아지 인덱스 역할을 한다(Spring 컨텍스트 캐시 파편화, Kotest 훅 순서, `runTest` 가상 시간, Go 테스트 캐시·`synctest`,
fake timer + Promise, DB 롤백 격리, Elasticsearch refresh·샤드별 IDF, 뮤테이션 테스트). 브라우저 검증은 모델이 쓰는
체크리스트(`e2e-chrome` — claude-in-chrome / Playwright MCP)와 저장소에 남는 Playwright 스펙을 만드는 사용자 호출 커맨드(`/e2e`)로 나뉜다.

스택을 단정하지 않는다. 각 가이드는 먼저 빌드 파일·기존 테스트·`CLAUDE.md`/`.claude/rules` 를 읽는다. 커버리지 수치는 강제가 아니라 가이드다.

## 구성요소

### 스킬

- `tdd-workflow` (`test:tdd-workflow`) — 테스트 우선 사이클, Prove-It 버그 재현, 테스트 레벨 선택, 커버리지 해석, 증상 → 레퍼런스 표.
  레퍼런스(각 항목은 `TST-JVM-01` 같은 ID 와 적용·신호·메커니즘·처방·반례·검증·근거를 가짐):
  `jvm-kotlin.md`, `go.md`, `typescript.md`, `python.md`, `integration-data.md`, `coverage-mutation.md`.
- `e2e-chrome` (`test:e2e-chrome`) — 브라우저 검증 체크리스트: 도구 선택, 사전 확인, 시나리오 분해, 단계별 증거(스냅샷·스크린샷·콘솔·네트워크),
  완료 판정, 리포트 형식. 레퍼런스: `browser-tools.md`(claude-in-chrome / Playwright MCP 운용), `playwright.md`(`TST-PW-01~10`).

### 커맨드

- `/e2e <여정>` — 저장소에 남는 Playwright 스펙 작성·실행, 트레이스 기반 실패 진단, flaky 확인, `/loop-run --gate-cmd` 게이트화.
  사용자 호출 전용(`disable-model-invocation: true`).

### 에이전트

- `chrome-e2e-runner` — 브라우저 검증 계획을 별도 컨텍스트에서 실행하고 단계별 증거와 PASS/FAIL/SKIP 리포트를 돌려준다.
  세션의 MCP 브라우저 도구를 상속(`tools` 제한 없음), `e2e-chrome` 스킬 사전 로드.

## 사용법

- 테스트 우선 작업, flaky·느린 테스트: 상황을 말하면 `tdd-workflow` 가 쓰이거나 `/test:tdd-workflow` 로 직접 호출.
- "이 페이지 브라우저에서 확인해줘": `e2e-chrome` 이 쓰이고, 긴 여정은 `chrome-e2e-runner` 에 위임 가능.
- 저장소에 회귀 E2E 테스트 추가: `/e2e 저장된 카드로 결제`.

## 의존성

필수 없음. 함께 쓰면 좋은 것:

- `harness` — 테스트 명령을 `/loop-run --gate-cmd` 로 넘겨 그린까지 반복.
- 스택 플러그인(`kotlin-spring`, `go-mux`, `python-fastapi`, `nextjs`, `search`) — 스택별 성능·GC·동시성 지식.

## 참고

- claude-in-chrome 은 사용자의 실제 프로필·세션을 조작한다. 되돌릴 수 없는 동작은 확인 후 진행.
- 2026-10 정리: `/tdd` 커맨드(→ `tdd-workflow` 로 병합), `/e2e-chrome` 커맨드(→ `e2e-chrome` 스킬로 재작성). 원본은 `archive/components/test/commands/`.
