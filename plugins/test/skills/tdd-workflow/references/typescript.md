# TypeScript · React · Next.js 테스트 함정

적용 전 확인: `package.json` 의 러너(Vitest vs Jest)와 버전, `next` 버전(라우팅·미들웨어 파일명이 버전에 따라 다름 — Next 16 은 `middleware.ts` 대신 `proxy.ts`), 테스트 환경(jsdom/happy-dom/browser mode).

### TST-TS-01 · fake timer + Promise = 동기 advance 로는 영원히 안 끝난다
- 적용: `vi.useFakeTimers()`/`jest.useFakeTimers()` 로 debounce·retry·polling 처럼 `await` 와 타이머가 섞인 코드
- 신호: 테스트가 타임아웃, `advanceTimersByTime` 후에도 콜백 미실행
- 메커니즘: 동기 `advanceTimersByTime` 은 타이머 콜백만 실행하고 그 사이 마이크로태스크(Promise 연쇄)를 비우지 못한다. `await` 뒤에 등록되는 다음 타이머는 아직 존재하지 않는다.
- 처방: Async 변형(`await vi.advanceTimersByTimeAsync(ms)`, `await vi.runAllTimersAsync()`; Jest 도 동일 이름의 Async API). user-event 는 `userEvent.setup({ advanceTimers: vi.advanceTimersByTime })`.
- 반례: 순수 동기 타이머 로직은 동기 API 로 충분.
- 검증: 테스트 시간이 가짜 시간과 무관하게 짧은지.
- 근거: https://vitest.dev/api/vi.html#vi-advancetimersbytimeasync · https://testing-library.com/docs/user-event/options#advancetimers

### TST-TS-02 · `vi.mock`/`jest.mock` 은 파일 맨 위로 끌어올려진다
- 적용: 모듈 mock 팩토리 안에서 테스트 파일의 변수를 참조
- 신호: `Cannot access 'x' before initialization`, mock 이 적용 안 된 실제 모듈이 로드됨
- 메커니즘: 호이스팅으로 mock 호출이 import 보다 먼저 실행되므로 팩토리는 바깥 변수를 볼 수 없다. Jest 는 `mock` 접두사 변수만 예외 허용, Vitest 는 `vi.hoisted()` 로 값을 함께 끌어올린다. 이미 import 된 모듈 인스턴스는 mock 으로 바뀌지 않는다.
- 처방: `const { fn } = vi.hoisted(() => ({ fn: vi.fn() }))` 후 팩토리에서 사용. 가능하면 모듈 mock 대신 의존성 주입·MSW 같은 네트워크 경계 mock.
- 반례: 경로 문자열 오타·별칭(`@/`) 해석 차이로 "안 먹는" 경우도 많다 — 러너의 alias 설정 확인.
- 검증: 팩토리 안 `console.log` 로 실행 순서 확인.
- 근거: https://vitest.dev/api/vi.html#vi-hoisted · https://jestjs.io/docs/jest-object#jestmockmodulename-factory-options

### TST-TS-03 · Next.js async Server Component 는 단위 테스트 러너가 지원하지 않는다
- 적용: App Router 의 `async` Server Component
- 신호: RTL `render` 에서 Promise 반환 컴포넌트 에러, 억지로 `await Page()` 해서 렌더하는 테스트
- 메커니즘: Next.js 공식 문서 기준 Vitest/Jest 는 async Server Component 를 지원하지 않으며, 동기 Server/Client Component 만 단위 테스트를 권장, async 는 E2E 권장.
- 처방: 데이터 로딩·변환 로직을 순수 함수로 분리해 단위 테스트, 페이지 조립은 E2E(Playwright).
- 반례: 동기 컴포넌트·Client Component 는 RTL 로 충분.
- 검증: 해당 프로젝트 Next 버전의 testing 가이드 재확인.
- 근거: https://nextjs.org/docs/app/guides/testing/vitest

### TST-TS-04 · jsdom 에는 레이아웃이 없다
- 적용: jsdom/happy-dom 환경에서 가상 스크롤, sticky, IntersectionObserver/ResizeObserver/matchMedia 의존 컴포넌트
- 신호: `getBoundingClientRect()` 가 전부 0, observer 가 `undefined` 라 크래시 → 테스트용 stub 이 점점 늘어남
- 메커니즘: jsdom 은 DOM API 를 구현하지만 레이아웃·페인트 엔진이 없다. stub 으로 통과시키면 실제 레이아웃 버그는 검증되지 않는다.
- 처방: 레이아웃 의존 동작은 실제 브라우저(Playwright, 또는 Vitest browser mode)에서 검증하고, 단위 테스트는 로직만.
- 반례: observer 를 단순히 "존재"만 요구하는 컴포넌트는 최소 stub 으로 충분.
- 검증: 같은 시나리오를 브라우저에서 재현.
- 근거: https://github.com/jsdom/jsdom#unimplemented-parts-of-the-web-platform

### TST-TS-05 · spy·mock 은 기본으로 테스트 간 원복되지 않는다
- 적용: `vi.spyOn`/`jest.spyOn`, 모듈 레벨 mock 의 반환값 변경
- 신호: 파일 단독 실행은 그린, 순서 바꾸면 실패
- 메커니즘: 러너 설정(`clearMocks`/`mockReset`/`restoreMocks`)을 켜지 않으면 호출 기록·구현 교체가 다음 테스트로 이어진다.
- 처방: 설정 파일에 `restoreMocks: true`(필요 시 `clearMocks`) 를 두고 개별 `afterEach` 정리를 없앤다. 세 옵션의 의미 차이는 러너 버전 문서로 확인.
- 반례: 의도적으로 파일 단위 공유 mock 을 쓰는 경우 해당 파일만 예외 처리.
- 검증: `--sequence.shuffle`(Vitest) 또는 `--randomize`(Jest) 로 순서 랜덤 실행.
- 근거: https://vitest.dev/config/#restoremocks · https://jestjs.io/docs/configuration#restoremocks-boolean
