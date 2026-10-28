---
name: e2e
description: |
  Playwright E2E 테스트 코드 생성·실행 — 사용자 여정을 Playwright 스펙으로 작성해 저장소에 남기고, 실행·실패 아티팩트(스크린샷·트레이스) 확인, flaky 원인 분석, 루프 게이트화까지.
  Generates and runs Playwright E2E specs for a user journey, inspects failure artifacts (screenshots, traces), diagnoses flaky tests, and wires the suite as a loop gate.
  Use when: writing a Playwright E2E test, running or fixing the E2E suite, adding a regression test for a user flow.
argument-hint: "<검증할 사용자 여정>"
disable-model-invocation: true
---

# /e2e — Playwright E2E 테스트 작성·실행

대상 여정: $ARGUMENTS

브라우저로 한 번 눈으로 확인하는 것이 목적이면 이 커맨드 대신 `e2e-chrome` 스킬(체크리스트)로 충분하다.
이 커맨드는 **저장소에 남는 Playwright 테스트**를 만든다.

## 1. 프로젝트 확인 (단정하지 말 것)

- `package.json` 에 `@playwright/test` 가 있는가, 버전은? 없으면 설치·초기화(`npm init playwright@latest`)를 **사용자에게 제안**하고 진행 여부를 묻는다.
- `playwright.config.ts`: `testDir`, `baseURL`, `projects`(브라우저), `retries`, `trace`, `webServer`
- 기존 E2E 테스트 1~2개: 디렉터리 구조, Page Object 사용 여부, 로그인 방식(`storageState` setup 프로젝트 등), 셀렉터 컨벤션(`getByRole` vs `data-testid`)
- 프로젝트 `CLAUDE.md`/`.claude/rules` 의 E2E 규칙(대상 환경, 금지 플로우)

## 2. 시나리오 → 스펙

1. 여정을 단계와 관찰 가능한 기대 결과로 분해해 사용자에게 보여준다(성공 1 + 대표 실패 1 이 기본).
2. 기존 컨벤션대로 스펙 작성. 원칙:
   - locator 는 `getByRole`/`getByLabel`/`getByText` 우선, 필요 시 `data-testid`. CSS 클래스·nth 대신 역할 기반으로 — 마크업 변경에 깨지고 모호한 매치를 숨긴다(TST-PW-03)
   - 대기는 web-first assertion(`await expect(locator).toBeVisible()`) — `waitForTimeout`/`networkidle` 은 느리거나 flaky 해지므로 대신 쓴다(TST-PW-01)
   - 테스트 간 독립 — 각 테스트가 자기 데이터를 준비
   - 서버 상태를 바꾸는 테스트는 계정/데이터 격리(워커당 계정)
3. 되돌릴 수 없는 외부 효과(실결제·실메일)가 있는 플로우는 스테이징·샌드박스 전용으로 가드(`test.skip(condition, reason)`).

## 3. 실행·진단

```bash
npx playwright test <spec> --project=chromium        # 우선 단일 브라우저
npx playwright test <spec> --trace on                # 실패 조사용 트레이스
npx playwright show-trace test-results/<...>/trace.zip
npx playwright test <spec> --repeat-each=10          # flaky 확인
npx playwright show-report
```

- RED 확인: 기능이 없거나 버그가 있는 상태에서 **의도한 이유로** 실패하는지 먼저 본다.
- 실패 시 트레이스의 액션 타임라인·네트워크·콘솔로 원인을 특정하고, 재시도·타임아웃 증가로 덮지 않는다.
- flaky·환경 함정은 `${CLAUDE_PLUGIN_ROOT}/skills/e2e-chrome/references/playwright.md` (TST-PW-01~10) 참조
  (`${CLAUDE_PLUGIN_ROOT}` 미치환 런타임이면 이 플러그인의 `skills/e2e-chrome/references/playwright.md`).

## 4. 결과 보고

- 추가/수정한 스펙 파일, 실행한 명령과 결과(통과/실패 수, 브라우저), 아티팩트 위치
- flaky 의심이 있으면 반복 실행 결과와 원인 가설

## 5. 루프 게이트로 쓰기

`playwright.config.ts` 에 `webServer` 가 있어 비대화형으로 앱을 띄우고 종료 코드로 끝나면 harness generic 루프 게이트로 쓸 수 있다:
`/loop-run "<목표>" --gate-cmd "npx playwright test"`. E2E 는 느리므로 단위 게이트 뒤에 체이닝(`--gate-cmd "pnpm test && npx playwright test"`)을 권장.
