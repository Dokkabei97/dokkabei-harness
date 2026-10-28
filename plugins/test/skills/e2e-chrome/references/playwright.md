# Playwright 테스트 함정 (flaky · 느림 · 환경)

적용 전 확인: `playwright.config.ts`(retries, trace, projects, webServer), `@playwright/test` 버전.

### TST-PW-01 · `waitForTimeout`·`networkidle` 로 기다리지 않는다
- 적용: 페이지 준비를 시간·네트워크 정지로 판단하는 테스트
- 신호: `page.waitForTimeout(…)`, `waitForLoadState('networkidle')`, CI 에서만 타임아웃
- 메커니즘: 공식 문서상 `networkidle` 은 DISCOURAGED — 폴링·웹소켓·분석 스크립트가 있으면 영원히 idle 이 안 되거나, 반대로 렌더 전에 idle 이 된다. 고정 sleep 은 느린 머신에서 부족하고 빠른 머신에서 낭비.
- 처방: 사용자 관점 준비 신호에 web-first assertion(`await expect(page.getByRole('heading', { name: '주문' })).toBeVisible()`), 특정 API 완료가 기준이면 `page.waitForResponse`.
- 반례: 애니메이션 시각 비교 직전 등 정말 시간이 기준인 경우만 — 그것도 `page.clock`(TST-PW-09)이 낫다.
- 검증: `--repeat-each=20` 로 반복 실행.
- 근거: https://playwright.dev/docs/api/class-page#page-wait-for-load-state

### TST-PW-02 · `expect(await locator.textContent())` 는 재시도하지 않는다
- 적용: 값을 꺼내서 일반 matcher 로 비교하는 코드
- 신호: 간헐적으로 빈 문자열·이전 값과 비교해 실패
- 메커니즘: web-first assertion(`await expect(locator).toHaveText()`)은 타임아웃까지 자동 재시도한다. 값을 먼저 꺼내면 그 순간의 스냅샷 1회 비교다.
- 처방: locator 를 matcher 에 직접 넘긴다(`toHaveText`, `toHaveCount`, `toHaveURL`, `toHaveValue`). DOM 이 아닌 조건(API 상태 등)은 `expect.poll(() => …)` 또는 `expect(async () => {…}).toPass()`.
- 반례: 재시도가 의미 없는 정적 값(설정 상수)은 일반 matcher.
- 검증: 동일.
- 근거: https://playwright.dev/docs/test-assertions

### TST-PW-03 · `.first()` 는 모호한 locator 를 숨긴다
- 적용: 여러 요소에 매칭되는 locator
- 신호: `strict mode violation` 에러를 `.first()`/`.nth()` 로 "해결"
- 메커니즘: Playwright locator 는 strict — 동작 시 2개 이상 매칭이면 에러를 내 모호함을 알려준다. `.first()` 는 DOM 순서가 바뀌면 다른 요소를 누른다.
- 처방: 범위를 좁힌다(`page.getByRole('row', { name: '주문 1001' }).getByRole('button', { name: '취소' })`), `filter({ hasText })`. 앱에 `data-testid` 를 더하는 것도 정당한 수정.
- 반례: 목록의 "첫 항목" 자체가 요구사항이면 OK.
- 검증: 데이터 순서를 바꾼 fixture 로 실행.
- 근거: https://playwright.dev/docs/locators#strictness

### TST-PW-04 · `trace: 'on-first-retry'` 인데 retries 가 0 이면 트레이스는 없다
- 적용: 생성기 기본 설정(`trace: 'on-first-retry'`, `retries: process.env.CI ? 2 : 0`)
- 신호: 로컬 실패를 조사하려는데 trace.zip 이 없음
- 메커니즘: 트레이스는 첫 재시도에서만 기록된다. 로컬 retries 0 이면 재시도가 없어 기록도 없다.
- 처방: 로컬 조사 시 `npx playwright test --trace on` 후 `npx playwright show-trace`. CI 는 artifacts 로 `test-results/`, `playwright-report/` 업로드.
- 반례: 모든 테스트에 `trace: 'on'` 상시는 느리고 용량이 크다.
- 검증: `test-results/` 에 trace.zip 생성 확인.
- 근거: https://playwright.dev/docs/trace-viewer

### TST-PW-05 · 병렬 워커가 같은 계정을 쓰면 서버 상태가 서로 덮인다
- 적용: `storageState` 로 로그인 재사용 + 서버 쪽 상태(장바구니, 설정, 주문)를 바꾸는 테스트 + `fullyParallel`/workers > 1
- 신호: 단독 실행 그린, 병렬에서 다른 테스트의 데이터가 보임
- 메커니즘: 세션 쿠키 재사용은 브라우저 상태만 분리한다. 서버 상태는 계정 단위로 공유된다.
- 처방: 서버 상태를 바꾸는 테스트는 공식 가이드의 "워커당 계정 하나"(`testInfo.parallelIndex` 로 계정 선택) 패턴. 인증 파일은 `playwright/.auth/` 에 두고 `.gitignore` (쿠키·헤더가 들어 있다).
- 반례: 읽기 전용 테스트는 공용 계정 하나로 충분.
- 검증: `--workers=4 --repeat-each=5`.
- 근거: https://playwright.dev/docs/auth

### TST-PW-06 · `page.route` 가 안 먹는다 = 서비스 워커(MSW 등)가 요청을 가로챔
- 적용: 앱이 서비스 워커(PWA, MSW 개발 모드)를 등록
- 신호: route 핸들러가 호출되지 않음, 네트워크 이벤트 누락
- 메커니즘: 서비스 워커가 처리한 요청은 Playwright 라우팅에 도달하지 않는다.
- 처방: 컨텍스트 옵션 `serviceWorkers: 'block'`(config 의 `use` 에 설정). route 는 해당 요청이 나가기 전(`goto` 전)에 등록.
- 반례: 서비스 워커 동작 자체를 검증하는 테스트.
- 검증: route 핸들러 호출 횟수 로그.
- 근거: https://playwright.dev/docs/network

### TST-PW-07 · 스크린샷 베이스라인은 OS·브라우저별 파일이다
- 적용: `toHaveScreenshot()` 시각 비교
- 신호: 로컬(macOS)에서 만든 베이스라인으로 Linux CI 가 전부 실패, 또는 CI 용 베이스라인 파일이 없음
- 메커니즘: 베이스라인 파일명에 브라우저(또는 프로젝트명)와 플랫폼이 붙는다(예: `…-chromium-darwin.png`). 렌더링은 OS·버전·설정·하드웨어에 따라 다르다.
- 처방: 베이스라인은 CI 와 같은 환경(같은 OS 이미지/컨테이너)에서 생성·갱신(`--update-snapshots`). 동적 영역은 `mask`, 애니메이션은 비활성 옵션.
- 반례: 픽셀 비교가 필요 없는 기능 검증에 스크린샷 assert 를 쓰지 않는다 — 텍스트/역할 assert 가 덜 깨진다.
- 검증: CI 아티팩트의 diff 이미지.
- 근거: https://playwright.dev/docs/test-snapshots

### TST-PW-08 · `reuseExistingServer` 는 로컬에서 엉뚱한 서버를 검증하게 만든다
- 적용: `webServer: { command, url, reuseExistingServer: !process.env.CI }`
- 신호: 수정했는데 E2E 결과가 그대로, 다른 브랜치·이전 빌드 동작이 보임
- 메커니즘: 로컬에선 해당 포트에 이미 떠 있는 서버(다른 터미널의 dev 서버, 다른 worktree)를 그대로 쓴다.
- 처방: 검증 전 포트 점유 프로세스·브랜치 확인. 프로덕션 빌드를 검증하려면 `command` 를 build+start 로, 포트를 dev 와 분리.
- 반례: 빠른 로컬 반복에는 재사용이 이득.
- 검증: 앱에 빌드 해시/버전을 노출해 테스트 시작 시 로그.
- 근거: https://playwright.dev/docs/test-webserver

### TST-PW-09 · 시간 의존 UI 는 `page.clock` 으로
- 적용: 카운트다운, 세션 만료, "n분 전" 표시, 디바운스
- 신호: 테스트 안에서 실제로 기다림, 날짜에 따라 결과가 바뀜
- 메커니즘: Clock API 는 페이지의 `Date`·타이머를 제어한다 — `setFixedTime`(현재 시각 고정, 타이머는 진행), `install` 후 `pauseAt`/`fastForward`/`runFor`.
- 처방: `await page.clock.install({ time: new Date('2026-01-01T09:00:00+09:00') })` 후 `await page.clock.fastForward('05:00')`. 페이지 로드 전에 설정.
- 반례: 서버 시간 기준 로직은 브라우저 시계로 제어되지 않는다 — 서버 쪽 시간 주입 필요.
- 검증: 테스트 wall time.
- 근거: https://playwright.dev/docs/clock

### TST-PW-10 · E2E 로 모든 경계값을 덮으려 하지 않는다
- 적용: 폼 검증·계산 로직의 경우의 수를 E2E 로 나열하는 스위트
- 신호: E2E 수십~수백 개, 스위트 수십 분, flaky 재시도 증가
- 메커니즘: E2E 1건은 단위 테스트 수백~수천 배 비용이고 실패 원인 특정도 어렵다.
- 처방: E2E 는 핵심 여정의 "연결" 검증(각 여정 성공 1 + 대표 실패 1), 경우의 수는 단위/컴포넌트 테스트(`tdd-workflow`)로 내린다. 느린 스위트는 `--shard=i/n` 로 CI 분할.
- 반례: 브라우저 간 차이·실제 인증 흐름처럼 E2E 에서만 드러나는 것은 E2E 가 맞다.
- 검증: 스위트 시간·flaky 비율 추이.
- 근거: https://playwright.dev/docs/best-practices · https://playwright.dev/docs/test-sharding
