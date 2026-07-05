# test

> TDD 워크플로우와 E2E 테스트(Playwright / Chrome)를 한 플러그인으로 묶은 테스트 자동화 도구.

## 개요

`test`는 개발 사이클 전 구간의 테스트를 자동화한다. 코드를 작성하기 전에 실패하는 테스트부터 쓰게 강제하는 **TDD 루프**(RED → GREEN → REFACTOR, 80%+ 커버리지)와, 완성된 사용자 여정을 검증하는 **E2E 테스트** 두 축으로 구성된다. E2E는 목적에 따라 두 경로로 갈린다. CI/CD 회귀·다중 브라우저·헤드리스 자동화는 Playwright 기반 `/e2e`가, 인증 세션이 필요하거나 로컬에서 눈으로 빠르게 확인하려는 시각적 검증은 Chrome Extension 기반 `/e2e-chrome`가 맡는다.

TypeScript(Jest/Vitest/Playwright)와 Kotlin(Kotest/MockK/Spring Boot Test) 스택을 함께 지원한다. `/e2e`는 `mvp` 플러그인 Stage 4 루프의 **E2E 수용 게이트(②ᴱ)** 로도 재사용되도록 설계되어, 단위 게이트는 매 반복에서, 느린 E2E 스위트는 완주 직전에 한 번만 돌린다.

## 구성요소

### 커맨드

- `/tdd` — TDD 방법론을 강제한다. 인터페이스 스캐폴드 → 실패 테스트 작성(RED) → 최소 구현(GREEN) → 리팩터(REFACTOR) → 커버리지 80%+ 확인 순으로 진행. `tdd-workflow` 스킬을 적용하며 TypeScript·Kotlin 예시를 모두 제공한다.
- `/e2e` — Playwright로 E2E 테스트를 생성·유지·실행한다. Page Object Model 기반 테스트 저니 생성, 다중 브라우저(Chromium/Firefox/WebKit) 실행, 실패 시 스크린샷·비디오·트레이스 캡처, HTML/JUnit 리포트, flaky 테스트 탐지·격리. `playwright` MCP 서버(있을 때) 또는 `npx playwright` CLI로 메인 세션이 직접 구동한다.
- `/e2e-chrome` — Chrome Extension으로 실제 브라우저를 제어해 자연어 시나리오를 시각적으로 검증한다. 자연어를 테스트 단계로 분해하고 단계별 스크린샷·콘솔 에러를 확인, 실패 원인과 수정안을 담은 체크리스트 리포트를 낸다. `--url` / `--gif` / `--viewport` 옵션 지원. 로컬 전용이며 `chrome-e2e-runner` 에이전트를 디스패치한다.

### 에이전트

- `chrome-e2e-runner` — `claude --chrome` 모드에서 실제 Chrome/Edge 브라우저를 제어하는 시각적 E2E 전문 에이전트. 브라우저의 기존 인증 세션을 활용해 자연어 여정을 실행하고, 매 단계 DOM·콘솔·스크린샷으로 검증, 세션 GIF와 심각도별 이슈 표를 포함한 리포트를 산출한다. (도구: Read/Grep/Glob/Bash, 모델: opus)

### 스킬

- `tdd-workflow` (`test:tdd-workflow`) — 새 기능·버그 수정·리팩터 시 테스트 우선 개발을 강제하는 스킬. 테스트 피라미드(단위 ~80% / 통합 ~15% / E2E ~5%), Test Double 선호 계층(Real > Fake > Stub > Mock), 테스트 코드의 DAMP > DRY 원칙, 버그 재현 테스트를 먼저 쓰는 Prove-It 패턴을 담는다. `/tdd` 커맨드가 이 스킬을 적용한다.

## 사용법

- **TDD**: `/tdd <구현하려는 기능 설명>` — 예) `/tdd I need a function to calculate market liquidity score`. 스킬이 인터페이스를 먼저 정의하고 실패 테스트를 생성한 뒤, 통과할 만큼의 최소 코드와 리팩터, 커버리지 리포트까지 이끈다. 버그 수정이라면 재현 테스트(RED)부터 작성한다.
- **Playwright E2E**: `/e2e <검증할 사용자 여정>` — 예) `/e2e Test the market search and view flow`. 시나리오를 분석해 테스트 코드를 생성하고 다중 브라우저에서 실행, 실패 아티팩트를 남긴다. `mvp` 루프에 연동하려면 실행 명령을 `.planning/e2e-gate-cmd`에 한 줄(예: `npx playwright test`)로 기록하면 모든 스토리가 통과한 뒤 Stop 훅이 자동 실행한다(파일이 없으면 E2E는 생략, 회귀 0).
- **Chrome 시각 검증**: `/e2e-chrome <자연어 시나리오>` — 예) `/e2e-chrome --gif 회원가입 폼을 작성하고 이메일 인증 페이지로 리다이렉트되는지 확인`. `claude --chrome` 모드가 필요하며, 미활성 시 `claude --chrome -c`로 현재 세션을 유지한 채 재시작하도록 안내한다.

### `/e2e` vs `/e2e-chrome` 선택

| 상황 | 커맨드 |
|------|--------|
| CI/CD 회귀·다중 브라우저·헤드리스 | `/e2e` (Playwright) |
| 로컬 시각 확인·인증 세션·외부 서비스(Google 등) | `/e2e-chrome` |
| 팀에 GIF로 결과 공유 | `/e2e-chrome` |

## 의존성

플러그인 자체에 필수 의존성은 없다. 함께 쓰면 좋은 조합:

- `mvp` — `/e2e`를 Stage 4 루프의 E2E 수용 게이트(②ᴱ)로 물려 완주 직전 사용자 여정 전체를 검증한다.

## 참고

- **`/e2e-chrome` 전제**: `claude --chrome` 모드, Claude in Chrome Extension v1.0.36+, Claude Code v2.0.73+, Chrome 또는 Edge 브라우저. CI/CD에서는 동작하지 않는 로컬 전용 경로이며, Playwright 코드를 생성하지 않는다(그 역할은 `/e2e`).
- **금전 관련 플로우 주의**: 실제 자금이 오가는 E2E는 반드시 testnet/staging에서만 실행하고 프로덕션 대상 자동 테스트는 하지 않는다. 금융 테스트에는 `test.skip(process.env.NODE_ENV === 'production')` 가드와 소액 테스트 지갑을 사용한다.
- **커버리지 기준**: 전 코드 80% 최소, 금융 계산·인증·보안·핵심 비즈니스 로직은 100%를 권장한다.
- `chrome-e2e-runner`는 사용자 인증 정보를 저장·전송하지 않으며 활성 테스트 탭 밖의 브라우저 데이터에 접근하지 않는다.
